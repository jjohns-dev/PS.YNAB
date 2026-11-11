function Invoke-YnabRequest {
    <#
    .SYNOPSIS
        Sends a request to the YNAB API and returns the response data.
    .DESCRIPTION
        The only function in the module that calls Invoke-RestMethod. Sends the request to the fixed base URI
        https://api.ynab.com/v1 with bearer authentication, using the Connect-Ynab session token unless a token is
        passed explicitly. Returns the response's data object.

        A 429 response is retried up to three times, after waits of 15, 30 and 60 seconds. Any other HTTP error is
        raised as a terminating error carrying the HTTP status and YNAB's error id, name and detail; the original
        HttpResponseException is kept as the error's exception. Failures with no HTTP response, such as DNS or TLS
        errors, are not handled here and surface unchanged.
    .PARAMETER Method
        HTTP method.
    .PARAMETER Path
        API path beginning with /, relative to https://api.ynab.com/v1.
    .PARAMETER Body
        Request body. Serialized to JSON and sent as application/json.
    .PARAMETER Token
        Token to use instead of the session token. Used by Connect-Ynab to validate a token before storing it.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Invoke-YnabRequest -Path '/plans/last-used/accounts'
        Returns the data object of the accounts response for the last-used plan.
    .NOTES
        Status: Beta
        https://api.ynab.com/#errors
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(HelpMessage = 'HTTP method')]
        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')]
        [System.String] $Method = 'Get',

        [Parameter(Mandatory, HelpMessage = 'API path beginning with /, relative to https://api.ynab.com/v1')]
        [ValidatePattern('^/')]
        [System.String] $Path,

        [Parameter(HelpMessage = 'Request body, serialized to JSON')]
        [System.Object] $Body,

        [Parameter(HelpMessage = 'Token to use instead of the session token')]
        [System.Security.SecureString] $Token
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        $retryDelays = 15, 30, 60
    }
    Process {
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
                TargetObject = '{0} {1}' -f $Method, $Path
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
        Write-Verbose -Message ('{0} {1}' -f $Method, $restParams['Uri'])

        # SEND, RETRYING 429 RESPONSES ON A FIXED SCHEDULE
        $attempt = 0
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

                # READ YNAB'S ERROR OBJECT WHEN THE BODY HAS ONE
                $ynabError = $null
                if ($httpError.ErrorDetails.Message) {
                    try {
                        $ynabError = (ConvertFrom-Json -InputObject $httpError.ErrorDetails.Message -ErrorAction Stop).error
                    }
                    catch {
                        Write-Verbose -Message 'Error response body is not JSON.'
                    }
                }

                if ($ynabError.name) {
                    $message = 'YNAB API error {0} {1} ({2}): {3}' -f $status, $ynabError.name, $ynabError.id, $ynabError.detail
                    $errorId = 'YnabApi.{0}' -f $ynabError.name
                }
                else {
                    $message = 'YNAB API returned HTTP {0}' -f $status
                    $errorId = 'YnabApi.Http{0}' -f $status
                }
                if ($status -eq 401) {
                    $message = '{0}. The token may be invalid or revoked. Run Connect-Ynab again.' -f $message.TrimEnd('.')
                }

                $category = switch ($status) {
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
                    TargetObject = '{0} {1}' -f $Method, $Path
                }
                Write-Error @errorParams -ErrorAction Stop
            }
        }

        $response.data
    }
    Clean {
        Remove-Variable -Name 'requestToken', 'restParams' -Force -ErrorAction Ignore
    }
}
