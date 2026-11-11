function ConvertFrom-Milliunit {
    <#
    .SYNOPSIS
        Converts a YNAB milliunit amount to a decimal currency amount.
    .DESCRIPTION
        The YNAB API represents every amount as an integer number of milliunits, where 1000 milliunits equal one
        currency unit. This function divides by 1000 and returns a System.Decimal, so the result is exact.
    .PARAMETER Milliunit
        Amount in milliunits, as returned by the YNAB API.
    .INPUTS
        System.Int64.
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
        [Parameter(Mandatory, ValueFromPipeline, HelpMessage = 'Amount in milliunits')]
        [System.Int64] $Milliunit
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        [System.Decimal] $Milliunit / 1000
    }
}
