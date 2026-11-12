function Get-YnabAccount {
    <#
    .SYNOPSIS
        Gets the accounts in a YNAB plan.
    .DESCRIPTION
        Without -AccountId, returns every account in the plan from GET /plans/{plan_id}/accounts. With -AccountId,
        returns that one account from GET /plans/{plan_id}/accounts/{account_id}. Objects keep YNAB's property names;
        balance, cleared_balance and uncleared_balance, and the values of the debt_* loan maps, are converted from
        milliunits to decimal currency units. Deleted accounts are left out.

        The unit of the debt_interest_rates map is not documented by YNAB; it is converted like the other loan maps,
        so treat converted rates as unverified.

        Requires a session started with Connect-Ynab. Sends one request per plan.
    .PARAMETER PlanId
        Plan ID (a UUID), or last-used (the default), or default when default plan selection is enabled. Any other
        value is rejected before a request is sent. Binds from the plan_id property of piped plan objects.
    .PARAMETER AccountId
        ID of the one account to return.
    .INPUTS
        System.Management.Automation.PSCustomObject. Plan objects from Get-YnabPlanList, bound by plan_id.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-YnabAccount | Where-Object -Property closed -EQ $false
        Lists the open accounts in the last-used plan.
    .EXAMPLE
        PS C:\> Get-YnabAccount -AccountId '7e1d2c3b-4a5f-4e6d-8c7b-9a0f1e2d3c4b'
        Gets one account from the last-used plan.
    .EXAMPLE
        PS C:\> Get-YnabPlanList | Get-YnabAccount
        Lists the accounts in every plan.
    .NOTES
        Status: Beta
        https://api.ynab.com/v1#/Accounts/getAccounts
    #>
    [CmdletBinding(DefaultParameterSetName = '_list')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Plan ID (UUID), last-used or default')]
        [Alias('plan_id')]
        [ValidatePattern('^(last-used|default|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', ErrorMessage = 'Plan ID [{0}] must be a UUID such as 0b5e3c1a-7d2f-4e6b-9a8c-1f2e3d4c5b6a, last-used or default.')]
        [System.String] $PlanId = 'last-used',

        [Parameter(Mandatory, ParameterSetName = '_id', HelpMessage = 'ID of the account to return')]
        [ValidateNotNullOrEmpty()]
        [System.String] $AccountId
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
    }
    Process {
        $accountsPath = '/plans/{0}/accounts' -f [System.Uri]::EscapeDataString($PlanId)
        if ($PSCmdlet.ParameterSetName -eq '_id') {
            $response = Invoke-YnabRequest -Path ('{0}/{1}' -f $accountsPath, [System.Uri]::EscapeDataString($AccountId))
            ConvertFrom-YnabData -InputObject $response.account
        }
        else {
            $response = Invoke-YnabRequest -Path $accountsPath
            foreach ($account in $response.accounts) {
                ConvertFrom-YnabData -InputObject $account
            }
        }
    }
}
