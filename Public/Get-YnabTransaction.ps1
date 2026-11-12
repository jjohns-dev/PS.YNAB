function Get-YnabTransaction {
    <#
    .SYNOPSIS
        Gets transactions from a YNAB plan.
    .DESCRIPTION
        Returns the plan's transactions from GET /plans/{plan_id}/transactions, or one account's or one category's
        transactions with -AccountId or -CategoryId, filtered by -SinceDate, -UntilDate and -Type. With
        -TransactionId, returns that one transaction from GET /plans/{plan_id}/transactions/{transaction_id}.

        Without -SinceDate, YNAB returns transactions from one year ago onward. Both dates are inclusive and are sent
        as calendar dates (yyyy-MM-dd); any time of day is ignored.

        Objects keep YNAB's property names, and amounts, including those of split transactions in subtransactions,
        are converted from milliunits to decimal currency units. Deleted transactions are left out.

        With -CategoryId, YNAB returns "hybrid" transactions: each part of a split transaction is its own row, with a
        type of transaction or subtransaction and a parent_transaction_id, instead of a subtransactions list.

        Requires a session started with Connect-Ynab. Sends one request per plan.
    .PARAMETER PlanId
        Plan ID (a UUID), or last-used (the default), or default when default plan selection is enabled. Any other
        value is rejected before a request is sent. Binds from the plan_id property of piped plan objects.
    .PARAMETER AccountId
        Return only this account's transactions.
    .PARAMETER CategoryId
        Return only this category's transactions, as hybrid transactions.
    .PARAMETER TransactionId
        ID of the one transaction to return.
    .PARAMETER SinceDate
        Return only transactions on or after this date.
    .PARAMETER UntilDate
        Return only transactions on or before this date.
    .PARAMETER Type
        Return only Uncategorized or only Unapproved transactions.
    .INPUTS
        System.Management.Automation.PSCustomObject. Plan objects from Get-YnabPlanList, bound by plan_id.
    .OUTPUTS
        System.Management.Automation.PSCustomObject.
    .EXAMPLE
        PS C:\> Get-YnabTransaction -SinceDate (Get-Date).AddDays(-7)
        Lists the last week's transactions in the last-used plan.
    .EXAMPLE
        PS C:\> Get-YnabTransaction -Type Unapproved
        Lists the transactions waiting for approval.
    .EXAMPLE
        PS C:\> Get-YnabTransaction -AccountId '7e1d2c3b-4a5f-4e6d-8c7b-9a0f1e2d3c4b' -SinceDate 2026-11-01 -UntilDate 2026-11-30
        Lists one account's transactions for November 2026.
    .NOTES
        Status: Beta
        https://api.ynab.com/v1#/Transactions/getTransactions
    #>
    [CmdletBinding(DefaultParameterSetName = '_plan')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    Param(
        [Parameter(ValueFromPipelineByPropertyName, HelpMessage = 'Plan ID (UUID), last-used or default')]
        [Alias('plan_id')]
        [ValidatePattern('^(last-used|default|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$', ErrorMessage = 'Plan ID [{0}] must be a UUID such as 0b5e3c1a-7d2f-4e6b-9a8c-1f2e3d4c5b6a, last-used or default.')]
        [System.String] $PlanId = 'last-used',

        [Parameter(Mandatory, ParameterSetName = '_account', HelpMessage = 'Return only this account''s transactions')]
        [ValidateNotNullOrEmpty()]
        [System.String] $AccountId,

        [Parameter(Mandatory, ParameterSetName = '_category', HelpMessage = 'Return only this category''s transactions')]
        [ValidateNotNullOrEmpty()]
        [System.String] $CategoryId,

        [Parameter(Mandatory, ParameterSetName = '_id', HelpMessage = 'ID of the transaction to return')]
        [ValidateNotNullOrEmpty()]
        [System.String] $TransactionId,

        [Parameter(ParameterSetName = '_plan', HelpMessage = 'Return only transactions on or after this date')]
        [Parameter(ParameterSetName = '_account', HelpMessage = 'Return only transactions on or after this date')]
        [Parameter(ParameterSetName = '_category', HelpMessage = 'Return only transactions on or after this date')]
        [System.DateTime] $SinceDate,

        [Parameter(ParameterSetName = '_plan', HelpMessage = 'Return only transactions on or before this date')]
        [Parameter(ParameterSetName = '_account', HelpMessage = 'Return only transactions on or before this date')]
        [Parameter(ParameterSetName = '_category', HelpMessage = 'Return only transactions on or before this date')]
        [System.DateTime] $UntilDate,

        [Parameter(ParameterSetName = '_plan', HelpMessage = 'Uncategorized or Unapproved')]
        [Parameter(ParameterSetName = '_account', HelpMessage = 'Uncategorized or Unapproved')]
        [Parameter(ParameterSetName = '_category', HelpMessage = 'Uncategorized or Unapproved')]
        [ValidateSet('Uncategorized', 'Unapproved')]
        [System.String] $Type
    )
    Begin {
        Write-Verbose -Message ('Starting {0}' -f $MyInvocation.MyCommand)
        $invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture
    }
    Process {
        if ($PSBoundParameters.ContainsKey('SinceDate') -and $PSBoundParameters.ContainsKey('UntilDate') -and $SinceDate.Date -gt $UntilDate.Date) {
            $errorParams = @{
                Message      = 'SinceDate [{0}] is later than UntilDate [{1}].' -f $SinceDate.ToString('yyyy-MM-dd', $invariantCulture), $UntilDate.ToString('yyyy-MM-dd', $invariantCulture)
                ErrorId      = 'YnabInvalidDateRange'
                Category     = 'InvalidArgument'
                TargetObject = $SinceDate
            }
            Write-Error @errorParams -ErrorAction Stop
        }

        $planPath = '/plans/{0}' -f [System.Uri]::EscapeDataString($PlanId)
        if ($PSCmdlet.ParameterSetName -eq '_id') {
            $response = Invoke-YnabRequest -Path ('{0}/transactions/{1}' -f $planPath, [System.Uri]::EscapeDataString($TransactionId))
            ConvertFrom-YnabData -InputObject $response.transaction
            return
        }

        $transactionsPath = switch ($PSCmdlet.ParameterSetName) {
            '_account' { '{0}/accounts/{1}/transactions' -f $planPath, [System.Uri]::EscapeDataString($AccountId) }
            '_category' { '{0}/categories/{1}/transactions' -f $planPath, [System.Uri]::EscapeDataString($CategoryId) }
            default { '{0}/transactions' -f $planPath }
        }

        # DATES ARE FORMATTED WITH THE INVARIANT CULTURE: th-TH WOULD OTHERWISE WRITE A BUDDHIST-CALENDAR YEAR
        $query = @{}
        if ($PSBoundParameters.ContainsKey('SinceDate')) {
            $query['since_date'] = $SinceDate.ToString('yyyy-MM-dd', $invariantCulture)
        }
        if ($PSBoundParameters.ContainsKey('UntilDate')) {
            $query['until_date'] = $UntilDate.ToString('yyyy-MM-dd', $invariantCulture)
        }
        if ($PSBoundParameters.ContainsKey('Type')) {
            $query['type'] = $Type.ToLowerInvariant()
        }

        $response = Invoke-YnabRequest -Path $transactionsPath -Query $query
        foreach ($transaction in $response.transactions) {
            ConvertFrom-YnabData -InputObject $transaction
        }
    }
}
