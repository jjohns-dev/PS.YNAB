function Disconnect-Ynab {
    <#
    .SYNOPSIS
        Ends the YNAB session and clears the session token.
    .DESCRIPTION
        Disposes the token held by Connect-Ynab, and for an OAuth session also its refresh token and client secret,
        clears the session cache of list results, and clears the session, so later PS.YNAB commands fail until
        Connect-Ynab is run again. Running it with no session does nothing. Tokens stay valid in YNAB; to revoke a
        personal token or an OAuth authorization, use Developer Settings in YNAB.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Disconnect-Ynab
        Clears the current YNAB session.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param()
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # CACHED RESULTS BELONG TO THE SESSION BEING ENDED (ADR-0005)
        $script:YnabCache.Clear()

        # AN OAUTH SESSION ALSO HOLDS A REFRESH TOKEN AND CLIENT SECRET (ADR-0007)
        if ($script:YnabOAuth) {
            foreach ($secret in $script:YnabOAuth.RefreshToken, $script:YnabOAuth.ClientSecret) {
                if ($secret) {
                    $secret.Dispose()
                }
            }
            $script:YnabOAuth = $null
        }

        if ($script:YnabToken) {
            $script:YnabToken.Dispose()
            $script:YnabToken = $null
            Write-Verbose -Message 'Disconnected from YNAB.'
        }
        else {
            Write-Verbose -Message 'No YNAB session to clear.'
        }
    }
}
