function ConvertTo-Milliunit {
    <#
    .SYNOPSIS
        Converts a currency amount to YNAB milliunits.
    .DESCRIPTION
        The YNAB API represents every amount as an integer number of milliunits, where 1000 milliunits equal one
        currency unit. This function multiplies by 1000 and returns a System.Int64. An amount with more than three
        decimal places cannot be represented in milliunits and raises an error instead of being rounded.

        The amount is converted to System.Decimal by its type, so the result is the same on every PowerShell version:
        a decimal is used as is; a double or single is rounded to 15 or 7 significant digits, which reproduces the
        value as typed (since .NET 11, PowerShell 7.7, a plain conversion keeps the double's binary noise, so 12.34
        became 12.339999999999999857891452848); a string is parsed with the invariant culture, so the decimal
        separator is always a period; whole numbers convert exactly. Any other type raises an error.
    .PARAMETER Amount
        Currency amount with at most three decimal places, as a decimal, double, single, whole number or string.
    .INPUTS
        System.Object.
    .OUTPUTS
        System.Int64.
    .EXAMPLE
        PS C:\> ConvertTo-Milliunit -Amount 12.34
        Returns 12340.
    .EXAMPLE
        PS C:\> '-0.5', 3 | ConvertTo-Milliunit
        Returns -500 and 3000.
    .NOTES
        Status: Beta
        https://api.ynab.com/#formats
        https://learn.microsoft.com/dotnet/core/compatibility/core-libraries/11/decimal-biginteger-floating-point-conversions
    #>
    [CmdletBinding()]
    [OutputType([System.Int64])]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, HelpMessage = 'Currency amount with at most three decimal places')]
        [ValidateNotNull()]
        [System.Object] $Amount
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
        $floatStyle = [System.Globalization.NumberStyles]::Float
    }
    Process {
        # TYPED AS OBJECT: BINDING TO A DECIMAL PARAMETER WOULD CONVERT DOUBLES, AND STRINGS VIA A DOUBLE, BEFORE THIS
        # CODE RUNS, AND ON .NET 11 THAT CONVERSION KEEPS BINARY NOISE (#18)
        $decimalAmount = switch ($Amount) {
            { $_ -is [System.Decimal] } {
                $_
                break
            }
            { $_ -is [System.Double] } {
                [System.Decimal]::Parse($_.ToString('G15', $invariantCulture), $floatStyle, $invariantCulture)
                break
            }
            { $_ -is [System.Single] } {
                [System.Decimal]::Parse($_.ToString('G7', $invariantCulture), $floatStyle, $invariantCulture)
                break
            }
            { $_ -is [System.String] } {
                $parsed = [System.Decimal]::Zero
                if (-not [System.Decimal]::TryParse($_.Trim(), $floatStyle, $invariantCulture, [ref] $parsed)) {
                    $errorParams = @{
                        Message      = 'Amount [{0}] is not a number. Use a period as the decimal separator, for example 12.34.' -f $_
                        ErrorId      = 'YnabAmountNotNumber'
                        Category     = 'InvalidArgument'
                        TargetObject = $_
                    }
                    Write-Error @errorParams -ErrorAction Stop
                }
                $parsed
                break
            }
            { $_ -is [System.Int64] -or $_ -is [System.Int32] -or $_ -is [System.Int16] -or $_ -is [System.Byte] } {
                [System.Decimal] $_
                break
            }
            default {
                $errorParams = @{
                    Message      = 'Amount must be a decimal, double, single, whole number or string, not [{0}].' -f $_.GetType().FullName
                    ErrorId      = 'YnabAmountType'
                    Category     = 'InvalidType'
                    TargetObject = $_
                }
                Write-Error @errorParams -ErrorAction Stop
            }
        }

        $milliunit = $decimalAmount * 1000
        if ($milliunit -ne [System.Decimal]::Truncate($milliunit)) {
            $errorParams = @{
                Message      = 'Amount [{0}] has more than three decimal places and cannot be converted to milliunits' -f $decimalAmount
                ErrorId      = 'YnabAmountPrecision'
                Category     = 'InvalidArgument'
                TargetObject = $decimalAmount
            }
            Write-Error @errorParams -ErrorAction Stop
        }
        [System.Int64] $milliunit
    }
}
