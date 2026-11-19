function New-YnabOAuthRequest {
    <#
    .SYNOPSIS
        Creates the state, PKCE pair and authorize URL for one OAuth authorization.
    .DESCRIPTION
        Generates a random state (16 bytes) and a PKCE code verifier (32 bytes, 43 base64url characters) with its
        S256 code challenge, and builds the URL of YNAB's authorize page requesting the read-only scope.

        The code verifier is a secret until the authorization code is exchanged; the caller must not write it to any
        output stream.
    .PARAMETER ClientId
        Client ID of the OAuth application.
    .PARAMETER RedirectUri
        Redirect URI registered for the application, such as http://localhost:8765/callback or
        urn:ietf:wg:oauth:2.0:oob.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject. State, CodeVerifier, CodeChallenge and AuthorizeUri.
    .EXAMPLE
        PS C:\> $request = New-YnabOAuthRequest -ClientId $id -RedirectUri 'http://localhost:8765/callback'
        Creates the values for one authorization and the URL to open in the browser.
    .NOTES
        Status: Beta
        https://api.ynab.com/#oauth-applications
        https://datatracker.ietf.org/doc/html/rfc7636
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Returns new values only; it changes no state.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Client ID of the OAuth application')]
        [ValidateNotNullOrEmpty()]
        [System.String] $ClientId,

        [Parameter(Mandatory, HelpMessage = 'Redirect URI registered for the application')]
        [ValidateNotNullOrEmpty()]
        [System.String] $RedirectUri
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)

        # BASE64URL WITHOUT PADDING (RFC 7636 APPENDIX A)
        $toBase64Url = {
            param ([System.Byte[]] $Bytes)
            [System.Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        }
    }
    Process {
        $state = & $toBase64Url ([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16))
        $verifier = & $toBase64Url ([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
        $verifierBytes = [System.Text.Encoding]::ASCII.GetBytes($verifier)
        $challenge = & $toBase64Url ([System.Security.Cryptography.SHA256]::HashData($verifierBytes))

        $query = @{
            client_id             = $ClientId
            redirect_uri          = $RedirectUri
            response_type         = 'code'
            scope                 = 'read-only'
            state                 = $state
            code_challenge        = $challenge
            code_challenge_method = 'S256'
        }

        [PSCustomObject] @{
            State         = $state
            CodeVerifier  = $verifier
            CodeChallenge = $challenge
            AuthorizeUri  = 'https://app.ynab.com/oauth/authorize?{0}' -f (ConvertTo-YnabQueryString -Query $query)
        }
    }
    Clean {
        Remove-Variable -Name 'verifier', 'verifierBytes' -Force -ErrorAction Ignore
    }
}
