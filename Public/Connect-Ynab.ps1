function Connect-Ynab {
    <#
    .SYNOPSIS
        Starts a YNAB session with a personal access token.
    .DESCRIPTION
        Validates the token with one GET /user request and, if it is accepted, holds a read-only copy of it for the
        rest of the PowerShell session so other PS.YNAB commands can authenticate. If validation fails, the error is
        raised and any existing session is left unchanged. A successful call replaces an existing session.

        The module does not store the token anywhere: supply it from a secret store, such as
        Get-Secret from Microsoft.PowerShell.SecretManagement, or with Read-Host -AsSecureString. Never assign the
        token to a variable as a plain string, because PSReadLine saves such lines to its history file.
    .PARAMETER Token
        YNAB personal access token, created under Developer Settings in YNAB.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Connect-Ynab -Token (Get-Secret -Name YnabToken)
        Starts a session with a token kept in a SecretManagement vault.
    .EXAMPLE
        PS C:\> Connect-Ynab -Token (Read-Host -Prompt 'YNAB token' -AsSecureString)
        Starts a session with a token typed at a prompt.
    .NOTES
        Status: Beta
        Each call uses one request from the API's limit of 200 requests per hour per token.
        https://api.ynab.com/#authentication
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'YNAB personal access token')]
        [System.Security.SecureString] $Token
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
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

        # REPLACE THE SESSION, THEN DISPOSE THE TOKEN IT HELD
        $previous = $script:YnabToken
        $script:YnabToken = $candidate
        if ($previous) {
            $previous.Dispose()
        }
        Write-Verbose -Message 'Connected to YNAB.'
    }
    Clean {
        Remove-Variable -Name 'candidate', 'previous' -Force -ErrorAction Ignore
    }
}
