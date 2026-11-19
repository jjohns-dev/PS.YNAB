function Invoke-YnabRequest {
    <#
    .SYNOPSIS
        Sends a request to the YNAB API or YNAB's OAuth token endpoint.
    .DESCRIPTION
        The only function in the module that calls Invoke-RestMethod, and it sends only to two fixed hosts.

        API requests (the default) go to https://api.ynab.com/v1 with bearer authentication, using the Connect-Ynab
        session token unless a token is passed explicitly, and return the response's data object. In an OAuth session,
        and without an explicit token, the access token is refreshed through Update-YnabSessionToken before a request
        when it expires within 60 seconds, and once after a 401, which resends the request (ADR-0007).

        Token requests (-TokenGrant) post the given form fields to https://app.ynab.com/oauth/token without a bearer
        token and return the whole response. The form values, which include secrets, never appear in any output.

        A 429 response is retried up to three times, after waits of 15, 30 and 60 seconds. Any other HTTP error is
        raised as a terminating error carrying the HTTP status and YNAB's error id, name and detail, or, for the token
        endpoint, YNAB's OAuth error and description; the original HttpResponseException is kept as the error's
        exception. Failures with no HTTP response, such as DNS or TLS errors, are not handled here and surface
        unchanged.
    .PARAMETER Method
        HTTP method.
    .PARAMETER Path
        API path beginning with /, relative to https://api.ynab.com/v1.
    .PARAMETER Body
        Request body. Serialized to JSON and sent as application/json.
    .PARAMETER Query
        Query parameters. Each entry with a non-null value is appended as key=value, URI-escaped, in sorted key order.
    .PARAMETER Token
        Token to use instead of the session token. Used by Connect-Ynab to validate a token before storing it. An
        explicit token is never refreshed.
    .PARAMETER TokenGrant
        Form fields for YNAB's OAuth token endpoint, such as grant_type, client_id, client_secret and refresh_token.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Invoke-YnabRequest -Path '/plans/last-used/accounts'
        Returns the data object of the accounts response for the last-used plan.
    .EXAMPLE
        PS C:\> $grant = @{ grant_type = 'refresh_token'; refresh_token = $r; client_id = $id; client_secret = $secret }
        PS C:\> Invoke-YnabRequest -TokenGrant $grant
        Redeems a refresh token and returns the token response.
    .NOTES
        Status: Beta
        https://api.ynab.com/#errors
        https://api.ynab.com/#oauth-applications
    #>
    [CmdletBinding(DefaultParameterSetName = '_api')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(ParameterSetName = '_api', HelpMessage = 'HTTP method')]
        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')]
        [System.String] $Method = 'Get',

        [Parameter(Mandatory, ParameterSetName = '_api',
            HelpMessage = 'API path beginning with /, relative to https://api.ynab.com/v1')]
        [ValidatePattern('^/')]
        [System.String] $Path,

        [Parameter(ParameterSetName = '_api', HelpMessage = 'Request body, serialized to JSON')]
        [System.Object] $Body,

        [Parameter(ParameterSetName = '_api',
            HelpMessage = 'Query parameters, appended URI-escaped in sorted key order')]
        [System.Collections.IDictionary] $Query,

        [Parameter(ParameterSetName = '_api', HelpMessage = 'Token to use instead of the session token')]
        [System.Security.SecureString] $Token,

        [Parameter(Mandatory, ParameterSetName = '_grant', HelpMessage = 'Form fields for the OAuth token endpoint')]
        [ValidateNotNullOrEmpty()]
        [System.Collections.IDictionary] $TokenGrant
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        $retryDelays = 15, 30, 60
    }
    Process {
        $isGrant = $PSCmdlet.ParameterSetName -eq '_grant'
        $usesSession = -not $isGrant -and -not $PSBoundParameters.ContainsKey('Token')

        if ($isGrant) {
            # TOKEN ENDPOINT: FORM BODY, NO BEARER TOKEN. THE FORM HOLDS SECRETS, SO NOTHING FROM IT IS LOGGED
            $target = 'Post /oauth/token'
            $restParams = @{
                Uri         = 'https://app.ynab.com/oauth/token'
                Method      = 'Post'
                Body        = $TokenGrant
                ErrorAction = 'Stop'
                Debug       = $false
            }
        }
        else {
            $target = '{0} {1}' -f $Method, $Path

            # AN OAUTH SESSION WHOSE ACCESS TOKEN IS ABOUT TO EXPIRE IS REFRESHED FIRST (ADR-0007)
            $refreshBy = (Get-Date).ToUniversalTime().AddSeconds(60)
            if ($usesSession -and $script:YnabOAuth -and $script:YnabOAuth.ExpiresAt -le $refreshBy) {
                Write-Verbose -Message 'The OAuth access token expires within 60 seconds; refreshing it first.'
                Update-YnabSessionToken
            }

            # RESOLVE THE TOKEN: AN EXPLICIT TOKEN WINS OVER THE SESSION
            if ($PSBoundParameters.ContainsKey('Token')) {
                $requestToken = $Token
            }
            else {
                $requestToken = $script:YnabToken
            }
            if (-not $requestToken) {
                $errorParams = @{
                    Message      = 'Not connected to YNAB. Run Connect-Ynab first.'
                    ErrorId      = 'YnabNotConnected'
                    Category     = 'ConnectionError'
                    TargetObject = $target
                }
                Write-Error @errorParams -ErrorAction Stop
            }

            # BUILD THE REQUEST. DEBUG IS FORCED OFF BECAUSE Invoke-RestMethod'S DEBUG OUTPUT PRINTS THE
            # AUTHORIZATION HEADER, TOKEN INCLUDED, WHENEVER -Debug OR $DebugPreference IS SET
            $restParams = @{
                Uri            = 'https://api.ynab.com/v1{0}' -f $Path
                Method         = $Method
                Authentication = 'Bearer'
                Token          = $requestToken
                ErrorAction    = 'Stop'
                Debug          = $false
            }
            if ($PSBoundParameters.ContainsKey('Body')) {
                $restParams['Body'] = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
                $restParams['ContentType'] = 'application/json'
            }
            $queryString = ConvertTo-YnabQueryString -Query $Query
            if ($queryString) {
                $restParams['Uri'] = '{0}?{1}' -f $restParams['Uri'], $queryString
            }
        }
        Write-Verbose -Message ('{0} {1}' -f $restParams['Method'], $restParams['Uri'])

        # SEND, RETRYING 429 RESPONSES ON A FIXED SCHEDULE, AND AN OAUTH SESSION'S 401 ONCE AFTER A REFRESH
        $attempt = 0
        $refreshedAfter401 = $false
        $received = $false
        while (-not $received) {
            try {
                $response = Invoke-RestMethod @restParams
                $received = $true
            }
            catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                $httpError = $PSItem
                $status = [System.Int32] $httpError.Exception.Response.StatusCode

                if ($status -eq 429 -and $attempt -lt $retryDelays.Count) {
                    $delay = $retryDelays[$attempt]
                    $attempt++
                    Write-Verbose -Message ('YNAB rate limit reached (429). Retry {0} of {1} in {2} seconds.' -f $attempt, $retryDelays.Count, $delay)
                    Start-Sleep -Seconds $delay
                    continue
                }

                if ($status -eq 401 -and $usesSession -and $script:YnabOAuth -and -not $refreshedAfter401) {
                    Write-Verbose -Message 'YNAB returned 401 for an OAuth session; refreshing and resending once.'
                    $refreshedAfter401 = $true
                    Update-YnabSessionToken
                    $restParams['Token'] = $script:YnabToken
                    continue
                }

                # READ YNAB'S ERROR BODY WHEN THERE IS ONE: { error: { id, name, detail } } FROM THE API,
                # { error, error_description } FROM THE TOKEN ENDPOINT
                $errorBody = $null
                if ($httpError.ErrorDetails.Message) {
                    try {
                        $errorBody = ConvertFrom-Json -InputObject $httpError.ErrorDetails.Message -ErrorAction Stop
                    }
                    catch {
                        Write-Verbose -Message 'Error response body is not JSON.'
                    }
                }

                $ynabError = $errorBody.error
                if ($isGrant -and $ynabError -is [System.String]) {
                    $message = 'YNAB OAuth error {0} {1}: {2}' -f $status, $ynabError, $errorBody.error_description
                    $errorId = 'YnabOAuth.{0}' -f $ynabError
                }
                elseif ($isGrant) {
                    $message = 'YNAB OAuth token endpoint returned HTTP {0}' -f $status
                    $errorId = 'YnabOAuth.Http{0}' -f $status
                }
                elseif ($ynabError.name) {
                    $messageFormat = 'YNAB API error {0} {1} ({2}): {3}'
                    $message = $messageFormat -f $status, $ynabError.name, $ynabError.id, $ynabError.detail
                    $errorId = 'YnabApi.{0}' -f $ynabError.name
                }
                else {
                    $message = 'YNAB API returned HTTP {0}' -f $status
                    $errorId = 'YnabApi.Http{0}' -f $status
                }
                if ($status -eq 401 -and -not $isGrant) {
                    $message = '{0}. The token may be invalid or revoked. Run Connect-Ynab again.' -f $message.TrimEnd('.')
                }

                # A 400 FROM THE TOKEN ENDPOINT MEANS A REJECTED GRANT OR CLIENT, SO IT IS AN AUTHENTICATION ERROR
                $category = switch ($status) {
                    { $_ -eq 400 -and $isGrant } { 'AuthenticationError'; break }
                    401 { 'AuthenticationError' }
                    403 { 'PermissionDenied' }
                    404 { 'ObjectNotFound' }
                    429 { 'LimitsExceeded' }
                    default { 'InvalidOperation' }
                }

                $errorParams = @{
                    Message      = $message
                    Exception    = $httpError.Exception
                    ErrorId      = $errorId
                    Category     = $category
                    TargetObject = $target
                }
                Write-Error @errorParams -ErrorAction Stop
            }
        }

        if ($isGrant) {
            $response
        }
        else {
            $response.data
        }
    }
    Clean {
        Remove-Variable -Name 'requestToken', 'restParams', 'TokenGrant' -Force -ErrorAction Ignore
    }
}
