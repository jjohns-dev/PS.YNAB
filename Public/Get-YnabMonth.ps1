function Get-YnabMonth {
    <#
    .SYNOPSIS
        Gets the months of a YNAB plan, or one month with its categories.
    .DESCRIPTION
        Without -Month, returns a summary of every plan month from GET /plans/{plan_id}/months: income, budgeted,
        activity, to_be_budgeted and age_of_money. With -Month, returns that month's detail from
        GET /plans/{plan_id}/months/{month}, including each category's budgeted, activity and balance for the month.

        Objects keep YNAB's property names, and amounts are converted from milliunits to decimal currency units.
        Deleted months and categories are left out.

        Requires a session started with Connect-Ynab. Sends one request per plan.
    .PARAMETER PlanId
        Plan ID (a UUID), or last-used (the default), or default when default plan selection is enabled. Any other
        value is rejected before a request is sent. Binds from the plan_id property of piped plan objects.
    .PARAMETER Month
        The month to return: current for the current calendar month in UTC, or any date in the month. A date is sent
        as the first of its month, so 2026-11-15 returns November 2026. Use the ISO form yyyy-MM-dd. Strings are parsed
        with the invariant culture whatever the machine's regional settings, so 11/12/2026 always means November 12.
    .INPUTS
        System.Management.Automation.PSCustomObject. Plan objects from Get-YnabPlanList, bound by plan_id.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-YnabMonth | Select-Object -Property month, income, activity -Last 3
        Shows income and activity for the three latest months in the last-used plan.
    .EXAMPLE
        PS C:\> (Get-YnabMonth -Month current).categories | Where-Object -Property balance -LT 0
        Lists the categories that are overspent this month.
    .EXAMPLE
        PS C:\> Get-YnabMonth -Month 2026-10-01
        Gets October 2026 with its categories.
    .NOTES
        Status: Beta
        https://api.ynab.com/v1#/Months/getPlanMonth
    #>
    [CmdletBinding(DefaultParameterSetName = '_list')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Plan ID (UUID), last-used or default')]
        [Alias('plan_id')]
        [ValidatePattern('^(last-used|default|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', ErrorMessage = 'Plan ID [{0}] must be a UUID such as 0b5e3c1a-7d2f-4e6b-9a8c-1f2e3d4c5b6a, last-used or default.')]
        [System.String] $PlanId = 'last-used',

        [Parameter(Mandatory, ParameterSetName = '_month', HelpMessage = 'current, or any date in the month (yyyy-MM-dd)')]
        [ValidateScript({
                $parsedMonth = [System.DateTime]::MinValue
                $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
                if ($_ -eq 'current' -or [System.DateTime]::TryParse($_, $invariantCulture, [System.Globalization.DateTimeStyles]::None, [ref] $parsedMonth)) {
                    $true
                }
                else {
                    Write-Error -Message ('Month [{0}] must be current or a date such as 2026-11-01.' -f $_) -ErrorAction Stop
                }
            })]
        [System.String] $Month
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $monthsPath = '/plans/{0}/months' -f [System.Uri]::EscapeDataString($PlanId)
        if ($PSCmdlet.ParameterSetName -eq '_month') {
            # YNAB TAKES current OR THE FIRST DAY OF THE MONTH. PARSE AND FORMAT WITH THE INVARIANT CULTURE: THE -as
            # OPERATOR USES THE CURRENT CULTURE, SO en-GB READS 11/12 AS 11 DECEMBER AND th-TH READS 2026 AS A BUDDHIST YEAR
            if ($Month -eq 'current') {
                $monthSegment = 'current'
            }
            else {
                $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
                $monthDate = [System.DateTime]::Parse($Month, $invariantCulture)
                $monthSegment = '{0}-01' -f $monthDate.ToString('yyyy-MM', $invariantCulture)
            }
            $response = Invoke-YnabRequest -Path ('{0}/{1}' -f $monthsPath, $monthSegment)
            ConvertFrom-YnabData -InputObject $response.month
        }
        else {
            $response = Invoke-YnabRequest -Path $monthsPath
            foreach ($planMonth in $response.months) {
                ConvertFrom-YnabData -InputObject $planMonth
            }
        }
    }
}
