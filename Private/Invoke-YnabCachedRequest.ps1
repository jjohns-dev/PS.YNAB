function Invoke-YnabCachedRequest {
    <#
    .SYNOPSIS
        Sends a YNAB list request through the session cache.
    .DESCRIPTION
        Keeps one cache entry per path and query for the PowerShell session, in memory only (ADR-0005). The first call
        stores the full response's data and its server_knowledge. Each later call still sends one request, with
        last_knowledge_of_server, merges the changes into the entry with Merge-YnabDelta, and stores the new
        server_knowledge. Returns a deep copy of the entry, so neither ConvertFrom-YnabData nor the caller can change
        the cache.

        Only calls with a plan ID are cached. With last-used or default, which can mean a different plan from one call
        to the next while YNAB's list responses do not name the plan, the request goes straight to Invoke-YnabRequest
        and a verbose message says so.

        A failed request leaves the entry unchanged. If merging fails, the entry is dropped so the next call downloads
        the full list, and the error is raised.
    .PARAMETER PlanId
        Plan ID, last-used or default. Only a plan ID is cached.
    .PARAMETER Path
        API path beginning with /, relative to https://api.ynab.com/v1.
    .PARAMETER Query
        Query parameters, as for Invoke-YnabRequest.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Invoke-YnabCachedRequest -PlanId $planId -Path ('/plans/{0}/accounts' -f $planId)
        Returns the plan's accounts data, downloading only changes after the first call.
    .NOTES
        Status: Beta
        https://api.ynab.com/#deltas
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(Mandatory, HelpMessage = 'Plan ID, last-used or default')]
        [ValidateNotNullOrEmpty()]
        [System.String] $PlanId,

        [Parameter(Mandatory, HelpMessage = 'API path beginning with /, relative to https://api.ynab.com/v1')]
        [ValidatePattern('^/')]
        [System.String] $Path,

        [Parameter(HelpMessage = 'Query parameters')]
        [System.Collections.IDictionary] $Query
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $requestParams = @{ Path = $Path }
        if ($Query) {
            $requestParams['Query'] = $Query
        }

        # KEYWORD PLANS CAN CHANGE MEANING MID-SESSION AND LIST RESPONSES DON'T NAME THE PLAN, SO THEY ARE NOT CACHED
        if ($PlanId -notmatch $ynab_uuid_pattern) {
            Write-Verbose -Message ('Not cached: -PlanId is [{0}]. Set a plan ID, for example with $PSDefaultParameterValues[''*-Ynab*:PlanId''], to cache this call.' -f $PlanId)
            Invoke-YnabRequest @requestParams
            return
        }

        $cacheKey = '{0}?{1}' -f $Path, (ConvertTo-YnabQueryString -Query $Query)
        $entry = $script:YnabCache[$cacheKey]

        if (-not $entry) {
            $data = Invoke-YnabRequest @requestParams
            if ($null -eq $data.server_knowledge) {
                # NOTHING TO SEND BACK NEXT TIME, SO THERE IS NOTHING TO CACHE
                $data
                return
            }
            $entry = @{ PlanId = $PlanId; ServerKnowledge = $data.server_knowledge; Data = $data }
            $script:YnabCache[$cacheKey] = $entry
            Write-Verbose -Message ('Cached {0} at server knowledge {1}.' -f $cacheKey, $entry.ServerKnowledge)
        }
        else {
            $deltaQuery = @{}
            if ($Query) {
                foreach ($key in $Query.Keys) {
                    $deltaQuery[$key] = $Query[$key]
                }
            }
            $deltaQuery['last_knowledge_of_server'] = $entry.ServerKnowledge
            $requestParams['Query'] = $deltaQuery

            # A FAILED REQUEST RAISES HERE, BEFORE THE ENTRY IS TOUCHED
            $delta = Invoke-YnabRequest @requestParams
            try {
                Merge-YnabDelta -Cached $entry.Data -Delta $delta -ErrorAction Stop
            }
            catch {
                # A HALF-MERGED ENTRY COULD BE WRONG, SO DROP IT; THE NEXT CALL DOWNLOADS THE FULL LIST
                $script:YnabCache.Remove($cacheKey)
                Write-Error -ErrorRecord $PSItem -ErrorAction Stop
            }
            $entry.ServerKnowledge = $delta.server_knowledge
            Write-Verbose -Message ('Merged changes into {0}; server knowledge {1}.' -f $cacheKey, $entry.ServerKnowledge)
        }

        # A DEEP COPY: CALLERS CHANGE WHAT THEY GET (ConvertFrom-YnabData DOES), SO THE CACHE MUST NOT BE SHARED
        ConvertTo-Json -InputObject $entry.Data -Depth 100 -Compress | ConvertFrom-Json
    }
}
