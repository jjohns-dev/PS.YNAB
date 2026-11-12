BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Get-YnabAccount' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'
        $script:accountId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'

        $script:listJson = '{
            "accounts": [
                { "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "Checking", "type": "checking", "on_budget": true, "closed": false,
                  "balance": 1234560, "balance_formatted": "$1,234.56", "balance_currency": 1234.56,
                  "cleared_balance": 1000000, "cleared_balance_currency": 1000.0, "uncleared_balance": 234560, "uncleared_balance_currency": 234.56,
                  "debt_interest_rates": null, "debt_minimum_payments": null, "debt_escrow_amounts": null, "deleted": false },
                { "id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "name": "Mortgage", "type": "mortgage", "on_budget": false, "closed": false,
                  "balance": -250000000, "cleared_balance": -250000000, "uncleared_balance": 0,
                  "debt_interest_rates": { "2026-01-01": 6125 }, "debt_minimum_payments": { "2026-01-01": 1850000 }, "debt_escrow_amounts": { "2026-01-01": 425000 }, "deleted": false },
                { "id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc", "name": "Closed card", "balance": 0, "deleted": true }
            ],
            "server_knowledge": 77
        }'
        $script:singleJson = '{ "account": { "id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "name": "Checking", "balance": 1234560, "balance_currency": 1234.56, "deleted": false } }'
    }
    BeforeEach {
        $listResponse = $script:listJson
        $singleResponse = $script:singleJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $listResponse | ConvertFrom-Json
        }.GetNewClosure()
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/accounts/*' } -MockWith {
            $singleResponse | ConvertFrom-Json
        }.GetNewClosure()
    }
    Context -Name 'listing accounts' -Fixture {
        It -Name 'sends one request to the last-used plan''s accounts by default' -Test {
            Get-YnabAccount | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq '/plans/last-used/accounts' } -Times 1 -Exactly -Scope It
        }
        It -Name 'returns one object per account, leaving out deleted accounts' -Test {
            $result = @(Get-YnabAccount)
            $result | Should -HaveCount 2
            $result.name | Should -Be @('Checking', 'Mortgage')
        }
        It -Name 'converts balances and drops their *_currency copies' -Test {
            $checking = @(Get-YnabAccount)[0]
            $checking.balance | Should -Be ([System.Decimal] 1234.56)
            $checking.cleared_balance | Should -Be ([System.Decimal] 1000)
            $checking.uncleared_balance | Should -Be ([System.Decimal] 234.56)
            $checking.balance_formatted | Should -Be '$1,234.56'
            $checking.PSObject.Properties.Name | Should -Not -Contain 'balance_currency'
            $checking.PSObject.Properties.Name | Should -Not -Contain 'cleared_balance_currency'
        }
        It -Name 'converts the values of the loan maps' -Test {
            $mortgage = @(Get-YnabAccount)[1]
            $mortgage.balance | Should -Be ([System.Decimal] -250000)
            $mortgage.debt_minimum_payments.'2026-01-01' | Should -Be ([System.Decimal] 1850)
            $mortgage.debt_escrow_amounts.'2026-01-01' | Should -Be ([System.Decimal] 425)
            $mortgage.debt_interest_rates.'2026-01-01' | Should -Be ([System.Decimal] 6.125)
        }
    }
    Context -Name 'getting one account' -Fixture {
        It -Name 'sends one request to the single-account endpoint' -Test {
            Get-YnabAccount -AccountId $script:accountId | Out-Null
            $expectedPath = '/plans/last-used/accounts/{0}' -f $script:accountId
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'returns the account with its balance converted' -Test {
            $result = @(Get-YnabAccount -AccountId $script:accountId)
            $result | Should -HaveCount 1
            $result[0].balance | Should -Be ([System.Decimal] 1234.56)
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'balance_currency'
        }
        It -Name 'escapes the account ID in the path' -Test {
            Get-YnabAccount -AccountId 'x/y' | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq '/plans/last-used/accounts/x%2Fy' } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects an empty account ID before sending a request' -Test {
            { Get-YnabAccount -AccountId '' } | Should -Throw
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects a malformed plan ID before sending a request' -Test {
            $err = $null
            try {
                Get-YnabAccount -PlanId 'Household'
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'lists the accounts of each piped plan, one request each' -Test {
            @(
                [PSCustomObject] @{ id = $script:planOne; plan_id = $script:planOne }
                [PSCustomObject] @{ id = $script:planTwo; plan_id = $script:planTwo }
            ) | Get-YnabAccount | Out-Null
            $firstPath = '/plans/{0}/accounts' -f $script:planOne
            $secondPath = '/plans/{0}/accounts' -f $script:planTwo
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $firstPath } -Times 1 -Exactly -Scope It
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $secondPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'rejects a piped account object instead of using its id as the plan' -Test {
            $err = $null
            try {
                [PSCustomObject] @{ id = $script:accountId; name = 'Checking' } | Get-YnabAccount -ErrorAction Stop
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'InputObjectNotBound,*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'lets the request error surface unchanged' -Test {
            # SAME FILTER AS THE SINGLE-ACCOUNT MOCK IN BeforeEach, WHICH WOULD OTHERWISE TAKE PRIORITY
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/accounts/*' } -MockWith {
                Write-Error -Message 'YNAB API error 404 resource_not_found (404.2): Resource not found' -ErrorId 'YnabApi.resource_not_found' -ErrorAction Stop
            }
            $err = $null
            try {
                Get-YnabAccount -AccountId $script:accountId
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.resource_not_found*'
        }
    }
}
