function ConvertTo-Milliunit {
    <#
    .SYNOPSIS
        Converts a decimal currency amount to YNAB milliunits.
    .DESCRIPTION
        The YNAB API represents every amount as an integer number of milliunits, where 1000 milliunits equal one
        currency unit. This function multiplies by 1000 and returns a System.Int64. An amount with more than three
        decimal places cannot be represented in milliunits and raises an error instead of being rounded.
    .PARAMETER Amount
        Currency amount with at most three decimal places.
    .INPUTS
        System.Decimal.
    .OUTPUTS
        System.Int64.
    .EXAMPLE
        PS C:\> ConvertTo-Milliunit -Amount 12.34
        Returns 12340.
    .NOTES
        Status: Beta
        https://api.ynab.com/#formats
    #>
    [CmdletBinding()]
    [OutputType([System.Int64])]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, HelpMessage = 'Currency amount with at most three decimal places')]
        [System.Decimal] $Amount
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $milliunit = $Amount * 1000
        if ($milliunit -ne [System.Decimal]::Truncate($milliunit)) {
            $errorParams = @{
                Message      = 'Amount [{0}] has more than three decimal places and cannot be converted to milliunits' -f $Amount
                ErrorId      = 'YnabAmountPrecision'
                Category     = 'InvalidArgument'
                TargetObject = $Amount
            }
            Write-Error @errorParams -ErrorAction Stop
        }
        [System.Int64] $milliunit
    }
}
