function Disconnect-Ynab {
    <#
    .SYNOPSIS
        Ends the YNAB session and clears the session token.
    .DESCRIPTION
        Disposes the token held by Connect-Ynab and clears the session, so later PS.YNAB commands fail until
        Connect-Ynab is run again. Running it with no session does nothing. The token itself stays valid in YNAB; to
        revoke it, use Developer Settings in YNAB.
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
