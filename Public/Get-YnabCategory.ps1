function Get-YnabCategory {
    <#
    .SYNOPSIS
        Gets the categories in a YNAB plan.
    .DESCRIPTION
        Without -CategoryId, returns every category in the plan from GET /plans/{plan_id}/categories, as one object
        per category rather than nested inside category groups; each category carries its category_group_id and
        category_group_name. With -CategoryId, returns that one category from
        GET /plans/{plan_id}/categories/{category_id}.

        Objects keep YNAB's property names. budgeted, activity, balance and the goal amounts are for the current
        plan month in UTC, per YNAB's API docs; for another month, use Get-YnabMonth -Month. Amounts are converted
        from milliunits to decimal currency units. Hidden categories and internal ones such
        as "Inflow: Ready to Assign" are included; filter on the hidden and internal properties. Deleted categories,
        and the categories of deleted groups, are left out.

        Requires a session started with Connect-Ynab. Sends one request per plan.
    .PARAMETER PlanId
        Plan ID (a UUID), or last-used (the default), or default when default plan selection is enabled. Any other
        value is rejected before a request is sent. Binds from the plan_id property of piped plan objects.
    .PARAMETER CategoryId
        ID of the one category to return.
    .INPUTS
        System.Management.Automation.PSCustomObject. Plan objects from Get-YnabPlanList, bound by plan_id.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-YnabCategory | Where-Object -FilterScript { -not $_.hidden -and -not $_.internal }
        Lists the visible, user-created categories in the last-used plan.
    .EXAMPLE
        PS C:\> Get-YnabCategory | Group-Object -Property category_group_name
        Groups the categories by their category group.
    .EXAMPLE
        PS C:\> Get-YnabCategory -CategoryId '5c4b3a2f-1e0d-4c9b-8a7f-6e5d4c3b2a1f'
        Gets one category from the last-used plan.
    .NOTES
        Status: Beta
        https://api.ynab.com/v1#/Categories/getCategories
    #>
    [CmdletBinding(DefaultParameterSetName = '_list')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Plan ID (UUID), last-used or default')]
        [Alias('plan_id')]
        [ValidatePattern('^(last-used|default|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', ErrorMessage = 'Plan ID [{0}] must be a UUID such as 0b5e3c1a-7d2f-4e6b-9a8c-1f2e3d4c5b6a, last-used or default.')]
        [System.String] $PlanId = 'last-used',

        [Parameter(Mandatory, ParameterSetName = '_id', HelpMessage = 'ID of the category to return')]
        [ValidateNotNullOrEmpty()]
        [System.String] $CategoryId
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $categoriesPath = '/plans/{0}/categories' -f [System.Uri]::EscapeDataString($PlanId)
        if ($PSCmdlet.ParameterSetName -eq '_id') {
            $response = Invoke-YnabRequest -Path ('{0}/{1}' -f $categoriesPath, [System.Uri]::EscapeDataString($CategoryId))
            ConvertFrom-YnabData -InputObject $response.category
        }
        else {
            $response = Invoke-YnabRequest -Path $categoriesPath
            foreach ($group in $response.category_groups) {
                # A DELETED GROUP COMES BACK EMPTY; A KEPT GROUP HAS ITS CATEGORIES CONVERTED AND FILTERED
                $keptGroup = ConvertFrom-YnabData -InputObject $group
                if ($keptGroup) {
                    foreach ($category in $keptGroup.categories) {
                        $category
                    }
                }
            }
        }
    }
}
