function ConvertFrom-Milliunit {
    <#
    .SYNOPSIS
        Converts a YNAB milliunit amount to a decimal currency amount.
    .DESCRIPTION
        The YNAB API represents every amount as an integer number of milliunits, where 1000 milliunits equal one
        currency unit. This function divides by 1000 and returns a System.Decimal, so the result is exact. A value
        that is not a whole number of milliunits raises an error instead of being rounded.
    .PARAMETER Milliunit
        Amount in milliunits, as returned by the YNAB API. Must be a whole number.
    .INPUTS
        System.Decimal.
    .OUTPUTS
        System.Decimal.
    .EXAMPLE
        PS C:\> ConvertFrom-Milliunit -Milliunit -12340
        Returns -12.34.
    .NOTES
        Status: Beta
        https://api.ynab.com/#formats
    #>
    [CmdletBinding()]
    [OutputType([System.Decimal])]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, HelpMessage = 'Amount in milliunits, as a whole number')]
        [System.Decimal] $Milliunit
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # TYPED AS DECIMAL, NOT INT64: BINDING TO INT64 WOULD ROUND 12.34 TO 12 BEFORE THIS CHECK COULD SEE IT
        if ($Milliunit -ne [System.Decimal]::Truncate($Milliunit)) {
            $errorParams = @{
                Message      = 'Value [{0}] is not a whole number of milliunits' -f $Milliunit
                ErrorId      = 'YnabMilliunitNotWhole'
                Category     = 'InvalidArgument'
                TargetObject = $Milliunit
            }
            Write-Error @errorParams -ErrorAction Stop
        }
        $Milliunit / 1000
    }
}
