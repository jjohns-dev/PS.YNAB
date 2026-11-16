function Merge-YnabDelta {
    <#
    .SYNOPSIS
        Merges a YNAB delta response into a cached response object.
    .DESCRIPTION
        Changes the cached object in place, property by property, with the properties of the delta object:
        - A list of objects that all have a key (id, or month for month objects) is merged by key: an item marked
          deleted removes the cached item, an item with a known key is merged into it recursively, and an item with an
          unknown key is appended. Existing items keep their order.
        - An object is merged recursively.
        - Anything else, including a list whose items have no key, is replaced.
        Properties the delta does not carry are left as they are. Used by Invoke-YnabCachedRequest (ADR-0005).
    .PARAMETER Cached
        The cached object to change.
    .PARAMETER Delta
        The object from the delta response.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Merge-YnabDelta -Cached $entry.Data -Delta $response
        Applies the changes in $response to the cached data.
    .NOTES
        Status: Beta
        https://api.ynab.com/#deltas
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'The cached object to change')]
        [System.Management.Automation.PSObject] $Cached,

        [Parameter(Mandatory, HelpMessage = 'The object from the delta response')]
        [System.Management.Automation.PSObject] $Delta
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)

        # RETURNS 'id:<value>' OR 'month:<value>' FOR A LIST ITEM, OR NOTHING WHEN IT HAS NO KEY
        $getItemKey = {
            param ($Item)
            if ($Item -is [System.Management.Automation.PSCustomObject]) {
                foreach ($keyName in 'id', 'month') {
                    $keyProperty = $Item.PSObject.Properties[$keyName]
                    if ($keyProperty -and $null -ne $keyProperty.Value) {
                        '{0}:{1}' -f $keyName, $keyProperty.Value
                        break
                    }
                }
            }
        }
    }
    Process {
        foreach ($deltaProperty in $Delta.PSObject.Properties) {
            $name = $deltaProperty.Name
            $deltaValue = $deltaProperty.Value
            $cachedProperty = $Cached.PSObject.Properties[$name]

            if (-not $cachedProperty) {
                Add-Member -InputObject $Cached -NotePropertyName $name -NotePropertyValue $deltaValue
                continue
            }

            $isKeyedList = $deltaValue -is [System.Array] -and $cachedProperty.Value -is [System.Array]
            if ($isKeyedList) {
                foreach ($deltaItem in $deltaValue) {
                    if (-not (& $getItemKey $deltaItem)) {
                        $isKeyedList = $false
                        break
                    }
                }
            }

            if ($isKeyedList) {
                # INDEX THE CACHED ITEMS BY KEY, THEN APPLY EACH DELTA ITEM
                $merged = [System.Collections.Generic.List[System.Object]]::new()
                $positions = @{}
                foreach ($cachedItem in $cachedProperty.Value) {
                    $cachedKey = & $getItemKey $cachedItem
                    if ($cachedKey) {
                        $positions[$cachedKey] = $merged.Count
                    }
                    $merged.Add($cachedItem)
                }
                $removed = [System.Collections.Generic.HashSet[System.Int32]]::new()
                foreach ($deltaItem in $deltaValue) {
                    $deltaKey = & $getItemKey $deltaItem
                    $isDeleted = $deltaItem.PSObject.Properties['deleted'] -and $deltaItem.deleted -eq $true
                    if ($positions.ContainsKey($deltaKey)) {
                        if ($isDeleted) {
                            $null = $removed.Add($positions[$deltaKey])
                        }
                        else {
                            Merge-YnabDelta -Cached $merged[$positions[$deltaKey]] -Delta $deltaItem
                        }
                    }
                    elseif (-not $isDeleted) {
                        $positions[$deltaKey] = $merged.Count
                        $merged.Add($deltaItem)
                    }
                }
                $cachedProperty.Value = [System.Object[]] @(
                    for ($i = 0; $i -lt $merged.Count; $i++) {
                        if (-not $removed.Contains($i)) {
                            $merged[$i]
                        }
                    }
                )
            }
            elseif ($deltaValue -is [System.Management.Automation.PSCustomObject] -and $cachedProperty.Value -is [System.Management.Automation.PSCustomObject]) {
                Merge-YnabDelta -Cached $cachedProperty.Value -Delta $deltaValue
            }
            else {
                $cachedProperty.Value = $deltaValue
            }
        }
    }
}
