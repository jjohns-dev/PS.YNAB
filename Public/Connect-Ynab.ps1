function Connect-Ynab {
    <#
    .SYNOPSIS
        Starts a YNAB session with a personal access token or a read-only OAuth authorization.
    .DESCRIPTION
        With -Token, validates a personal access token with one GET /user request and, if it is accepted, holds a
        read-only copy of it for the rest of the PowerShell session. If validation fails, the error is raised and any
        existing session is left unchanged.

        With -ClientId and -ClientSecret, authorizes an OAuth application with the read-only scope: it opens YNAB's
        authorize page in the browser, receives the code on a loopback listener at -RedirectUri (or reads the code
        YNAB displays, with -OutOfBand), and exchanges it for a 2-hour access token and a refresh token. Add
        -RefreshToken instead to resume from a refresh token saved earlier, with no browser; it is redeemed at once,
        so an invalid one fails here.

        In an OAuth session the access token is refreshed automatically. YNAB revokes a refresh token as soon as it is
        used, so every new refresh token, starting with the first, is passed to the -OnTokenRefresh scriptblock to
        save before any further request is sent. If the scriptblock fails, a non-terminating
        YnabOAuthTokenRefreshCallbackFailed error is written and the session keeps working; an unattended job should
        set $ErrorActionPreference = 'Stop' to treat it as fatal. Each PowerShell process needs its own
        authorization: a refresh in one process revokes the tokens of any other process sharing it (ADR-0007).

        Once an OAuth token request starts, any existing session is ended; if the request fails, no session remains.
        A successful call of any kind replaces an existing session and clears the session cache of list results
        (see Clear-YnabCache).

        The module does not store tokens or client credentials anywhere: supply them from a secret store, such as
        Get-Secret from Microsoft.PowerShell.SecretManagement, or with Read-Host -AsSecureString. Never assign a
        secret to a variable as a plain string, because PSReadLine saves such lines to its history file.
    .PARAMETER Token
        YNAB personal access token, created under Developer Settings in YNAB.
    .PARAMETER ClientId
        Client ID of the OAuth application, from Developer Settings in YNAB.
    .PARAMETER ClientSecret
        Client secret of the OAuth application.
    .PARAMETER RedirectUri
        Loopback redirect URI registered for the OAuth application, on localhost, 127.0.0.1 or [::1].
    .PARAMETER TimeoutSeconds
        How long to wait for the browser to redirect back after authorizing.
    .PARAMETER OutOfBand
        Use the urn:ietf:wg:oauth:2.0:oob redirect URI, which must be registered for the application, and type the
        code YNAB displays instead of receiving a redirect. For hosts where a loopback listener cannot be reached.
    .PARAMETER RefreshToken
        Refresh token saved by -OnTokenRefresh in an earlier session.
    .PARAMETER OnTokenRefresh
        Scriptblock called with each new refresh token, before any further request. It receives one object with
        RefreshToken (a SecureString of its own) and AccessTokenExpiresAt (UTC). Without it, the session works only in
        this PowerShell process, and a warning says so.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Connect-Ynab -Token (Get-Secret -Name YnabToken)
        Starts a session with a personal access token kept in a SecretManagement vault.
    .EXAMPLE
        PS C:\> Connect-Ynab -Token (Read-Host -Prompt 'YNAB token' -AsSecureString)
        Starts a session with a personal access token typed at a prompt.
    .EXAMPLE
        PS C:\> $save = { param ($Refresh) Set-Secret -Name YnabRefreshToken -Secret $Refresh.RefreshToken }
        PS C:\> $app = @{
            ClientId     = Get-Secret -Name YnabOAuthClientId -AsPlainText
            ClientSecret = Get-Secret -Name YnabOAuthClientSecret
        }
        PS C:\> Connect-Ynab @app -OnTokenRefresh $save
        Authorizes the OAuth application in the browser and saves each new refresh token to a vault.
    .EXAMPLE
        PS C:\> Connect-Ynab @app -RefreshToken (Get-Secret -Name YnabRefreshToken) -OnTokenRefresh $save
        With $app and $save from the previous example, resumes from the saved refresh token without a browser and
        saves its replacement.
    .NOTES
        Status: Beta
        Connecting with -Token uses one request from the API's limit of 200 requests per hour per token.
        https://api.ynab.com/#authentication
        https://api.ynab.com/#oauth-applications
    #>
    [CmdletBinding(DefaultParameterSetName = '_token')]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, ParameterSetName = '_token', HelpMessage = 'YNAB personal access token')]
        [System.Security.SecureString] $Token,

        [Parameter(Mandatory, ParameterSetName = '_authorize', HelpMessage = 'OAuth application client ID')]
        [Parameter(Mandatory, ParameterSetName = '_authorizeOutOfBand')]
        [Parameter(Mandatory, ParameterSetName = '_resume')]
        [ValidateNotNullOrEmpty()]
        [System.String] $ClientId,

        [Parameter(Mandatory, ParameterSetName = '_authorize', HelpMessage = 'OAuth application client secret')]
        [Parameter(Mandatory, ParameterSetName = '_authorizeOutOfBand')]
        [Parameter(Mandatory, ParameterSetName = '_resume')]
        [System.Security.SecureString] $ClientSecret,

        [Parameter(ParameterSetName = '_authorize', HelpMessage = 'Loopback redirect URI registered for the app')]
        [ValidateNotNullOrEmpty()]
        [System.String] $RedirectUri = 'http://localhost:8765/callback',

        [Parameter(ParameterSetName = '_authorize', HelpMessage = 'Seconds to wait for the browser redirect')]
        [ValidateRange(1, 3600)]
        [System.Int32] $TimeoutSeconds = 300,

        [Parameter(Mandatory, ParameterSetName = '_authorizeOutOfBand', HelpMessage = 'Type the code YNAB displays')]
        [System.Management.Automation.SwitchParameter] $OutOfBand,

        [Parameter(Mandatory, ParameterSetName = '_resume', HelpMessage = 'Refresh token saved earlier')]
        [System.Security.SecureString] $RefreshToken,

        [Parameter(ParameterSetName = '_authorize', HelpMessage = 'Scriptblock that saves each new refresh token')]
        [Parameter(ParameterSetName = '_authorizeOutOfBand')]
        [Parameter(ParameterSetName = '_resume')]
        [System.Management.Automation.ScriptBlock] $OnTokenRefresh
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($PSCmdlet.ParameterSetName -eq '_token') {
            # COPY THE TOKEN SO DISCONNECTING NEVER DISPOSES THE CALLER'S OBJECT
            $candidate = $Token.Copy()
            $candidate.MakeReadOnly()

            # VALIDATE BEFORE TOUCHING ANY EXISTING SESSION
            try {
                $null = Invoke-YnabRequest -Path '/user' -Token $candidate
            }
            catch {
                $candidate.Dispose()
                Write-Error -ErrorRecord $PSItem -ErrorAction Stop
            }

            # END ANY PREVIOUS SESSION, PERSONAL TOKEN OR OAUTH, WHICH ALSO CLEARS THE CACHE: A NEW TOKEN MAY BELONG TO
            # ANOTHER YNAB USER (ADR-0005, ADR-0007)
            Disconnect-Ynab
            $script:YnabToken = $candidate
            Write-Verbose -Message 'Connected to YNAB.'
            return
        }

        # AUTHORIZE IN THE BROWSER UNLESS RESUMING; THE EXISTING SESSION IS KEPT UNTIL THE TOKEN REQUEST
        $grant = $null
        $refresh = $null
        if ($PSCmdlet.ParameterSetName -eq '_resume') {
            $refresh = $RefreshToken.Copy()
            $refresh.MakeReadOnly()
        }
        else {
            $redirect = if ($OutOfBand) { 'urn:ietf:wg:oauth:2.0:oob' } else { $RedirectUri }
            $request = New-YnabOAuthRequest -ClientId $ClientId -RedirectUri $redirect
            $receiveParams = @{ AuthorizeUri = $request.AuthorizeUri }
            if ($OutOfBand) {
                $receiveParams['OutOfBand'] = $true
            }
            else {
                $receiveParams['RedirectUri'] = $redirect
                $receiveParams['State'] = $request.State
                $receiveParams['TimeoutSeconds'] = $TimeoutSeconds
            }
            try {
                $code = Receive-YnabAuthorizationCode @receiveParams
            }
            catch {
                Write-Error -ErrorRecord $PSItem -ErrorAction Stop
            }
            $grant = @{
                grant_type    = 'authorization_code'
                code          = ConvertFrom-SecureString -SecureString $code -AsPlainText
                redirect_uri  = $redirect
                code_verifier = $request.CodeVerifier
            }
            $code.Dispose()
        }

        if (-not $OnTokenRefresh) {
            Write-Warning -Message ('No -OnTokenRefresh scriptblock was given, so new refresh tokens are not saved ' +
                'and any refresh token saved earlier stops working. This session works only in this PowerShell ' +
                'process.')
        }

        # REPLACE ANY PREVIOUS SESSION, THEN OBTAIN THE FIRST TOKEN PAIR; Update-YnabSessionToken HANDS THE REFRESH
        # TOKEN TO -OnTokenRefresh, AND ENDS THE SESSION IF THE REQUEST FAILS (ADR-0007)
        $secret = $ClientSecret.Copy()
        $secret.MakeReadOnly()
        Disconnect-Ynab
        $script:YnabOAuth = @{
            ClientId       = $ClientId
            ClientSecret   = $secret
            RefreshToken   = $refresh
            ExpiresAt      = [System.DateTime]::MinValue
            OnTokenRefresh = $OnTokenRefresh
        }
        $updateParams = @{}
        if ($grant) {
            $updateParams['Grant'] = $grant
        }
        try {
            Update-YnabSessionToken @updateParams
        }
        catch {
            Write-Error -ErrorRecord $PSItem -ErrorAction Stop
        }
        Write-Verbose -Message 'Connected to YNAB with a read-only OAuth authorization.'
    }
    Clean {
        Remove-Variable -Name 'candidate', 'grant', 'request', 'code', 'updateParams' -Force -ErrorAction Ignore
    }
}
