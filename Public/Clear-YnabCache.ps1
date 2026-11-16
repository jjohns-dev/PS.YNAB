function Clear-YnabCache {
    <#
    .SYNOPSIS
        Clears the session cache of YNAB list results.
    .DESCRIPTION
        PS.YNAB caches list results for the PowerShell session, in memory only, when they are read with a plan ID, and
        keeps them current with delta requests. Clear-YnabCache removes every cached result, or only one plan's with
        -PlanId, so the next read downloads the full list. Connect-Ynab and Disconnect-Ynab also clear the cache.

        Clearing is not needed for current data: every cached read still asks YNAB for changes. Use it to free memory,
        for example after Get-YnabPlan, or to force a full download.
    .PARAMETER PlanId
        Clear only this plan's cached results. Must be a plan ID; results read with last-used or default are never
        cached.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .EXAMPLE
        PS C:\> Clear-YnabCache
        Clears every cached result.
    .EXAMPLE
        PS C:\> Clear-YnabCache -PlanId '0b5e3c1a-7d2f-4e6b-9a8c-1f2e3d4c5b6a'
        Clears one plan's cached results.
    .NOTES
        Status: Beta
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    Param(
        [Parameter(HelpMessage = 'Plan ID (UUID) whose cached results to clear')]
        [ValidatePattern('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', ErrorMessage = 'Plan ID [{0}] must be a UUID such as 0b5e3c1a-7d2f-4e6b-9a8c-1f2e3d4c5b6a; results read with last-used or default are never cached.')]
        [System.String] $PlanId
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        if ($PSBoundParameters.ContainsKey('PlanId')) {
            $planKeys = @($script:YnabCache.Keys).Where({ $script:YnabCache[$_].PlanId -eq $PlanId })
            foreach ($cacheKey in $planKeys) {
                $script:YnabCache.Remove($cacheKey)
            }
            Write-Verbose -Message ('Cleared {0} cached result(s) for plan {1}.' -f $planKeys.Count, $PlanId)
        }
        else {
            $clearedCount = $script:YnabCache.Count
            $script:YnabCache.Clear()
            Write-Verbose -Message ('Cleared {0} cached result(s).' -f $clearedCount)
        }
    }
}
