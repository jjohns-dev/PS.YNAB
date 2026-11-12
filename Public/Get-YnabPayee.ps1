function Get-YnabPayee {
    <#
    .SYNOPSIS
        Gets the payees in a YNAB plan.
    .DESCRIPTION
        Without -PayeeId, returns every payee in the plan from GET /plans/{plan_id}/payees. With -PayeeId, returns that
        one payee from GET /plans/{plan_id}/payees/{payee_id}. Objects keep YNAB's property names (id, name,
        transfer_account_id). A payee with a transfer_account_id is the transfer payee for that account. Deleted
        payees are left out.

        Requires a session started with Connect-Ynab. Sends one request per plan.
    .PARAMETER PlanId
        Plan ID (a UUID), or last-used (the default), or default when default plan selection is enabled. Any other
        value is rejected before a request is sent. Binds from the plan_id property of piped plan objects.
    .PARAMETER PayeeId
        ID of the one payee to return.
    .INPUTS
        System.Management.Automation.PSCustomObject. Plan objects from Get-YnabPlanList, bound by plan_id.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-YnabPayee | Where-Object -FilterScript { -not $_.transfer_account_id }
        Lists the payees in the last-used plan, leaving out account transfer payees.
    .EXAMPLE
        PS C:\> Get-YnabPayee -PayeeId '9f8e7d6c-5b4a-4392-8170-6f5e4d3c2b1a'
        Gets one payee from the last-used plan.
    .NOTES
        Status: Beta
        https://api.ynab.com/v1#/Payees/getPayees
    #>
    [CmdletBinding(DefaultParameterSetName = '_list')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Plan ID (UUID), last-used or default')]
        [Alias('plan_id')]
        [ValidatePattern('^(last-used|default|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', ErrorMessage = 'Plan ID [{0}] must be a UUID such as 0b5e3c1a-7d2f-4e6b-9a8c-1f2e3d4c5b6a, last-used or default.')]
        [System.String] $PlanId = 'last-used',

        [Parameter(Mandatory, ParameterSetName = '_id', HelpMessage = 'ID of the payee to return')]
        [ValidateNotNullOrEmpty()]
        [System.String] $PayeeId
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $payeesPath = '/plans/{0}/payees' -f [System.Uri]::EscapeDataString($PlanId)
        if ($PSCmdlet.ParameterSetName -eq '_id') {
            $response = Invoke-YnabRequest -Path ('{0}/{1}' -f $payeesPath, [System.Uri]::EscapeDataString($PayeeId))
            ConvertFrom-YnabData -InputObject $response.payee
        }
        else {
            $response = Invoke-YnabRequest -Path $payeesPath
            foreach ($payee in $response.payees) {
                ConvertFrom-YnabData -InputObject $payee
            }
        }
    }
}
