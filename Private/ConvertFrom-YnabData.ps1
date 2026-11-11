function ConvertFrom-YnabData {
    <#
    .SYNOPSIS
        Applies the module's output convention to objects returned by the YNAB API.
    .DESCRIPTION
        Walks each object and every object nested in its properties and lists, and applies ADR-0004:
        amount fields named in $ynab_amount_fields are converted from milliunits to System.Decimal; every value of the
        account loan maps named in $ynab_amount_map_fields is converted the same way; each <amount>_currency
        property is removed while <amount>_formatted is kept; and items whose deleted property is true are dropped,
        both at the top level and from nested lists. Nested lists remain arrays even when one item or none is left.

        Objects are changed in place and emitted one at a time. Values that are not objects pass through unchanged.
    .PARAMETER InputObject
        Object or value from a YNAB API response.
    .INPUTS
        System.Object.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> (Invoke-YnabRequest -Path '/plans/last-used/accounts').accounts | ConvertFrom-YnabData
        Returns the plan's accounts with balances in currency units and deleted accounts removed.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, ValueFromPipeline, HelpMessage = 'Object or value from a YNAB API response')]
        [AllowNull()]
        [System.Object] $InputObject
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        # NOTHING TO EMIT FOR NULL; NON-OBJECT VALUES SUCH AS STRINGS PASS THROUGH
        if ($null -eq $InputObject) {
            return
        }
        if ($InputObject -isnot [System.Management.Automation.PSCustomObject]) {
            $InputObject
            return
        }

        # DROP DELETED ITEMS (ADR-0004)
        if ($InputObject.PSObject.Properties['deleted'] -and $InputObject.deleted -eq $true) {
            return
        }

        # ITERATE OVER A COPY BECAUSE *_currency PROPERTIES ARE REMOVED DURING THE LOOP
        foreach ($property in @($InputObject.PSObject.Properties)) {
            $name = $property.Name
            $value = $property.Value

            if ($name -in $ynab_amount_fields) {
                if ($value -is [System.Int64] -or $value -is [System.Int32]) {
                    $property.Value = ConvertFrom-Milliunit -Milliunit $value
                }
            }
            elseif ($name.EndsWith('_currency') -and $name.Substring(0, $name.Length - 9) -in $ynab_amount_fields) {
                $InputObject.PSObject.Properties.Remove($name)
            }
            elseif ($name -in $ynab_amount_map_fields) {
                if ($value -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($entry in @($value.PSObject.Properties)) {
                        if ($entry.Value -is [System.Int64] -or $entry.Value -is [System.Int32]) {
                            $entry.Value = ConvertFrom-Milliunit -Milliunit $entry.Value
                        }
                    }
                }
            }
            elseif ($value -is [System.Array]) {
                $property.Value = [System.Object[]] @(
                    foreach ($item in $value) {
                        ConvertFrom-YnabData -InputObject $item
                    }
                )
            }
            elseif ($value -is [System.Management.Automation.PSCustomObject]) {
                $null = ConvertFrom-YnabData -InputObject $value
            }
        }

        $InputObject
    }
}
