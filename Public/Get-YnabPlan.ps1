function Get-YnabPlan {
    <#
    .SYNOPSIS
        Gets a whole YNAB plan in one object.
    .DESCRIPTION
        Returns the full plan from GET /plans/{plan_id}: its settings plus every account, payee, payee location,
        category group, category, month, transaction, split transaction and scheduled transaction, as nested lists
        with YNAB's property names. Amounts at every level are converted from milliunits to decimal currency units,
        and deleted items are left out. The object also carries plan_id, equal to id, so it can be piped into other
        PS.YNAB commands.

        The response holds the plan's entire history, so it grows with the plan and can be large. To list plans and
        their IDs, use Get-YnabPlanList. Requires a session started with Connect-Ynab. Sends one request per plan.
    .PARAMETER PlanId
        Plan ID, or last-used (the default), or default when default plan selection is enabled. Binds from the
        plan_id property of piped plan objects.
    .INPUTS
        System.Management.Automation.PSCustomObject. Plan objects from Get-YnabPlanList, bound by plan_id.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-YnabPlan
        Gets the last-used plan.
    .EXAMPLE
        PS C:\> Get-YnabPlanList | Where-Object -Property name -EQ 'Household' | Get-YnabPlan
        Gets the plan named Household.
    .NOTES
        Status: Beta
        https://api.ynab.com/v1#/Plans/getPlanById
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Plan ID, last-used or default')]
        [Alias('plan_id')]
        [ValidateNotNullOrEmpty()]
        [System.String] $PlanId = 'last-used'
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $response = Invoke-YnabRequest -Path ('/plans/{0}' -f [System.Uri]::EscapeDataString($PlanId))
        $plan = ConvertFrom-YnabData -InputObject $response.plan
        if ($plan) {
            # plan_id LETS THE PLAN BIND TO -PlanId FROM THE PIPELINE (ADR-0004)
            Add-Member -InputObject $plan -NotePropertyName 'plan_id' -NotePropertyValue $plan.id -Force
            $plan
        }
    }
}
