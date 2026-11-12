BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Get-YnabTransaction' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'
        $script:accountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        $script:categoryId = 'c0000001-0000-4000-8000-000000000001'
        $script:transactionId = 'tttttttt-0000-4000-8000-000000000001'

        $script:listJson = '{
            "transactions": [
                { "id": "t-1", "date": "2026-11-10", "amount": -45000, "amount_formatted": "-$45.00", "amount_currency": -45.0, "memo": "Groceries", "approved": true,
                  "account_name": "Checking", "payee_name": "Grocer", "category_name": "Food", "deleted": false, "subtransactions": [] },
                { "id": "t-2", "date": "2026-11-11", "amount": -60000, "approved": false, "category_name": "Split", "deleted": false,
                  "subtransactions": [
                    { "id": "s-1", "transaction_id": "t-2", "amount": -40000, "amount_currency": -40.0, "deleted": false },
                    { "id": "s-2", "transaction_id": "t-2", "amount": -20000, "deleted": false },
                    { "id": "s-3", "transaction_id": "t-2", "amount": -5000, "deleted": true }
                  ] },
                { "id": "t-3", "date": "2026-11-12", "amount": -1000, "deleted": true, "subtransactions": [] }
            ],
            "server_knowledge": 900
        }'
        $script:hybridJson = '{
            "transactions": [
                { "id": "s-1", "type": "subtransaction", "parent_transaction_id": "t-2", "date": "2026-11-11", "amount": -40000, "amount_currency": -40.0, "category_name": "Food", "deleted": false },
                { "id": "t-1", "type": "transaction", "parent_transaction_id": null, "date": "2026-11-10", "amount": -45000, "category_name": "Food", "deleted": false }
            ],
            "server_knowledge": 900
        }'
        $script:singleJson = '{ "transaction": { "id": "tttttttt-0000-4000-8000-000000000001", "amount": -45000, "amount_currency": -45.0, "deleted": false, "subtransactions": [] }, "server_knowledge": 900 }'
    }
    BeforeEach {
        $listResponse = $script:listJson
        $hybridResponse = $script:hybridJson
        $singleResponse = $script:singleJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $listResponse | ConvertFrom-Json
        }.GetNewClosure()
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/categories/*/transactions' } -MockWith {
            $hybridResponse | ConvertFrom-Json
        }.GetNewClosure()
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/transactions/*' } -MockWith {
            $singleResponse | ConvertFrom-Json
        }.GetNewClosure()
    }
    Context -Name 'endpoints' -Fixture {
        It -Name 'lists the last-used plan''s transactions with no query by default' -Test {
            Get-YnabTransaction | Out-Null
            $filter = { $Path -eq '/plans/last-used/transactions' -and $Query.Count -eq 0 }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'uses the account endpoint with -AccountId' -Test {
            Get-YnabTransaction -AccountId $script:accountId | Out-Null
            $expectedPath = '/plans/last-used/accounts/{0}/transactions' -f $script:accountId
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'uses the category endpoint with -CategoryId' -Test {
            Get-YnabTransaction -CategoryId $script:categoryId | Out-Null
            $expectedPath = '/plans/last-used/categories/{0}/transactions' -f $script:categoryId
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'uses the single-transaction endpoint with -TransactionId, without a query' -Test {
            Get-YnabTransaction -TransactionId $script:transactionId | Out-Null
            $expectedPath = '/plans/last-used/transactions/{0}' -f $script:transactionId
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath -and -not $Query } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'filters' -Fixture {
        It -Name 'sends -SinceDate, -UntilDate and -Type as since_date, until_date and a lower-case type' -Test {
            Get-YnabTransaction -SinceDate '2026-11-01' -UntilDate '2026-11-30' -Type Unapproved | Out-Null
            $filter = { $Query['since_date'] -eq '2026-11-01' -and $Query['until_date'] -eq '2026-11-30' -and $Query['type'] -ceq 'unapproved' -and $Query.Count -eq 3 }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'applies filters to the <Set> endpoint too' -ForEach @(
            @{ Set = 'account'; Arguments = @{ AccountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'; Type = 'Uncategorized' } }
            @{ Set = 'category'; Arguments = @{ CategoryId = 'c0000001-0000-4000-8000-000000000001'; Type = 'Uncategorized' } }
        ) -Test {
            Get-YnabTransaction @Arguments | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query['type'] -ceq 'uncategorized' } -Times 1 -Exactly -Scope It
        }
        It -Name 'sends only the calendar date when a time of day is given' -Test {
            Get-YnabTransaction -SinceDate '2026-11-15T23:30:00' | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query['since_date'] -eq '2026-11-15' } -Times 1 -Exactly -Scope It
        }
        It -Name 'writes Gregorian dates under the th-TH culture' -Test {
            $originalCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('th-TH')
                Get-YnabTransaction -SinceDate '2026-11-15' -UntilDate ([System.DateTime]::new(2026, 11, 30)) | Out-Null
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $originalCulture
            }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query['since_date'] -eq '2026-11-15' -and $Query['until_date'] -eq '2026-11-30' } -Times 1 -Exactly -Scope It
        }
        It -Name 'accepts the same date for -SinceDate and -UntilDate' -Test {
            { Get-YnabTransaction -SinceDate '2026-11-15' -UntilDate '2026-11-15T08:00:00' } | Should -Not -Throw
        }
        It -Name 'rejects -SinceDate later than -UntilDate before sending a request' -Test {
            $err = $null
            try {
                Get-YnabTransaction -SinceDate '2026-12-01' -UntilDate '2026-11-01'
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabInvalidDateRange,*'
            $err.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $err.ToString() | Should -Be 'SinceDate [2026-12-01] is later than UntilDate [2026-11-01].'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'parameter sets' -Fixture {
        It -Name 'rejects <Description> at binding, before sending a request' -ForEach @(
            @{ Description = '-AccountId with -CategoryId'; Arguments = @{ AccountId = 'a'; CategoryId = 'c' } }
            @{ Description = '-TransactionId with -SinceDate'; Arguments = @{ TransactionId = 't'; SinceDate = '2026-11-01' } }
            @{ Description = '-TransactionId with -Type'; Arguments = @{ TransactionId = 't'; Type = 'Unapproved' } }
            @{ Description = '-TransactionId with -AccountId'; Arguments = @{ TransactionId = 't'; AccountId = 'a' } }
        ) -Test {
            $err = $null
            try {
                Get-YnabTransaction @Arguments
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'AmbiguousParameterSet*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects <Value> as -Type before sending a request' -ForEach @(
            @{ Value = 'Approved' }
            @{ Value = 'all' }
        ) -Test {
            { Get-YnabTransaction -Type $Value } | Should -Throw
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects a malformed plan ID before sending a request' -Test {
            $err = $null
            try {
                Get-YnabTransaction -PlanId 'Household'
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'output' -Fixture {
        It -Name 'returns one object per transaction, leaving out deleted ones' -Test {
            $result = @(Get-YnabTransaction)
            $result.id | Should -Be @('t-1', 't-2')
        }
        It -Name 'converts amounts in transactions and their subtransactions' -Test {
            $result = @(Get-YnabTransaction)
            $result[0].amount | Should -Be ([System.Decimal] -45)
            $result[0].amount_formatted | Should -Be '-$45.00'
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'amount_currency'
            $result[1].subtransactions.amount | Should -Be @([System.Decimal] -40, [System.Decimal] -20)
            $result[1].subtransactions[0].PSObject.Properties.Name | Should -Not -Contain 'amount_currency'
        }
        It -Name 'leaves deleted subtransactions out' -Test {
            $split = @(Get-YnabTransaction)[1]
            $split.subtransactions.id | Should -Be @('s-1', 's-2')
        }
        It -Name 'returns hybrid rows from the category endpoint with amounts converted' -Test {
            $result = @(Get-YnabTransaction -CategoryId $script:categoryId)
            $result.type | Should -Be @('subtransaction', 'transaction')
            $result[0].parent_transaction_id | Should -Be 't-2'
            $result[0].amount | Should -Be ([System.Decimal] -40)
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'amount_currency'
        }
        It -Name 'returns one transaction for -TransactionId with its amount converted' -Test {
            $result = @(Get-YnabTransaction -TransactionId $script:transactionId)
            $result | Should -HaveCount 1
            $result[0].amount | Should -Be ([System.Decimal] -45)
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'lists the transactions of each piped plan, one request each' -Test {
            @(
                [PSCustomObject] @{ id = $script:planOne; plan_id = $script:planOne }
                [PSCustomObject] @{ id = $script:planTwo; plan_id = $script:planTwo }
            ) | Get-YnabTransaction -Type Unapproved | Out-Null
            $firstPath = '/plans/{0}/transactions' -f $script:planOne
            $secondPath = '/plans/{0}/transactions' -f $script:planTwo
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $firstPath } -Times 1 -Exactly -Scope It
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $secondPath } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'lets the request error surface unchanged' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/transactions/*' } -MockWith {
                Write-Error -Message 'YNAB API error 404 resource_not_found (404.2): Resource not found' -ErrorId 'YnabApi.resource_not_found' -ErrorAction Stop
            }
            $err = $null
            try {
                Get-YnabTransaction -TransactionId $script:transactionId
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.resource_not_found*'
        }
    }
}
