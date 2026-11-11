function Get-YnabPlanList {
    <#
    .SYNOPSIS
        Lists the YNAB plans the session token can access.
    .DESCRIPTION
        Returns one summary object per plan from GET /plans, with YNAB's property names (id, name, last_modified_on,
        first_month, last_month, date_format, currency_format). Each object also carries plan_id, equal to id, so it
        can be piped into any PS.YNAB command that takes -PlanId. To get everything in one plan, use Get-YnabPlan.

        Requires a session started with Connect-Ynab. Sends one request.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-YnabPlanList
        Lists every plan with its id and name.
    .EXAMPLE
        PS C:\> Get-YnabPlanList | Where-Object -Property name -EQ 'Household' | Get-YnabAccount
        Lists the accounts of the plan named Household.
    .NOTES
        Status: Beta
        https://api.ynab.com/v1#/Plans/getPlans
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param()
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $response = Invoke-YnabRequest -Path '/plans'
        foreach ($plan in $response.plans) {
            $summary = ConvertFrom-YnabData -InputObject $plan
            if ($summary) {
                # plan_id LETS PLANS BIND TO -PlanId FROM THE PIPELINE (ADR-0004)
                Add-Member -InputObject $summary -NotePropertyName 'plan_id' -NotePropertyValue $summary.id -Force
                $summary
            }
        }
    }
}
