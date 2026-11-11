BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Get-YnabPlan' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'
        $script:planThree = '33333333-3333-4333-8333-333333333333'

        # SHAPED LIKE GET /plans/{plan_id} data: NESTED LISTS USE YNAB'S BASE SCHEMAS, MOSTLY WITHOUT *_currency
        $script:planJson = '{
            "plan": {
                "id": "11111111-1111-4111-8111-111111111111",
                "name": "Household",
                "currency_format": { "iso_code": "USD", "decimal_digits": 2 },
                "accounts": [
                    { "id": "a-1", "name": "Checking", "balance": 1234560, "balance_formatted": "$1,234.56", "balance_currency": 1234.56, "cleared_balance": 1000000, "uncleared_balance": 234560, "deleted": false },
                    { "id": "a-2", "name": "Old card", "balance": 0, "deleted": true }
                ],
                "payees": [ { "id": "py-1", "name": "Grocer", "deleted": false } ],
                "category_groups": [ { "id": "g-1", "name": "Everyday", "deleted": false } ],
                "categories": [ { "id": "c-1", "name": "Food", "budgeted": 400000, "activity": -125500, "balance": 274500, "goal_target": null, "deleted": false } ],
                "months": [ { "month": "2026-11-01", "income": 5000000, "budgeted": 4000000, "activity": -3200000, "to_be_budgeted": 0, "age_of_money": 41, "deleted": false, "categories": [ { "id": "c-1", "budgeted": 400000, "activity": -125500, "balance": 274500, "deleted": false } ] } ],
                "transactions": [
                    { "id": "t-1", "amount": -45000, "deleted": false },
                    { "id": "t-2", "amount": -1000, "deleted": true }
                ],
                "subtransactions": [ { "id": "s-1", "transaction_id": "t-1", "amount": -20000, "deleted": false } ],
                "scheduled_transactions": [ { "id": "st-1", "amount": -150000, "amount_formatted": "-$150.00", "amount_currency": -150.0, "deleted": false } ],
                "scheduled_subtransactions": [ { "id": "ss-1", "amount": -50000, "deleted": false } ]
            },
            "server_knowledge": 4321
        }'
    }
    BeforeEach {
        $responseJson = $script:planJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $responseJson | ConvertFrom-Json
        }.GetNewClosure()
    }
    Context -Name 'requests' -Fixture {
        It -Name 'sends one request for the last-used plan by default' -Test {
            Get-YnabPlan | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq '/plans/last-used' } -Times 1 -Exactly -Scope It
        }
        It -Name 'uses -PlanId when given' -Test {
            Get-YnabPlan -PlanId $script:planTwo | Out-Null
            $expectedPath = '/plans/{0}' -f $script:planTwo
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'uses a default set in $PSDefaultParameterValues' -Test {
            $PSDefaultParameterValues['Get-YnabPlan:PlanId'] = $script:planThree
            try {
                Get-YnabPlan | Out-Null
            }
            finally {
                $PSDefaultParameterValues.Remove('Get-YnabPlan:PlanId')
            }
            $expectedPath = '/plans/{0}' -f $script:planThree
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'accepts <Value>' -ForEach @(
            @{ Value = 'last-used' }
            @{ Value = 'default' }
            @{ Value = '11111111-1111-4111-8111-111111111111' }
            @{ Value = 'ABCDEF12-3456-4789-8ABC-DEF123456789' }
        ) -Test {
            { Get-YnabPlan -PlanId $Value } | Should -Not -Throw
        }
        It -Name 'rejects <Description> before sending a request' -ForEach @(
            @{ Description = 'an empty string'; Value = '' }
            @{ Description = 'a misspelled keyword'; Value = 'last_used' }
            @{ Description = 'a plan name'; Value = 'Household' }
            @{ Description = 'a UUID without dashes'; Value = '11111111111141118111111111111111' }
            @{ Description = 'a UUID in braces'; Value = '{11111111-1111-4111-8111-111111111111}' }
            @{ Description = 'a value that would change the path'; Value = '11111111-1111-4111-8111-111111111111/accounts' }
        ) -Test {
            $err = $null
            try {
                Get-YnabPlan -PlanId $Value
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'names the accepted forms in the error message' -Test {
            $err = $null
            try {
                Get-YnabPlan -PlanId 'Household'
            }
            catch {
                $err = $PSItem
            }
            $err.ToString() | Should -BeLike '*Plan ID `[Household`] must be a UUID*last-used or default*'
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'takes the plan ID from piped plan objects, one request each' -Test {
            $plans = @(
                [PSCustomObject] @{ id = $script:planOne; plan_id = $script:planOne; name = 'Household' }
                [PSCustomObject] @{ id = $script:planTwo; plan_id = $script:planTwo; name = 'Side business' }
            )
            $plans | Get-YnabPlan | Out-Null
            $firstPath = '/plans/{0}' -f $script:planOne
            $secondPath = '/plans/{0}' -f $script:planTwo
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $firstPath } -Times 1 -Exactly -Scope It
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $secondPath } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'output' -Fixture {
        It -Name 'returns one plan object with plan_id equal to id' -Test {
            $result = @(Get-YnabPlan)
            $result | Should -HaveCount 1
            $result[0].plan_id | Should -Be $script:planOne
            $result[0].name | Should -Be 'Household'
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'server_knowledge'
        }
        It -Name 'converts amounts in every nested list' -Test {
            $plan = Get-YnabPlan
            $plan.accounts[0].balance | Should -Be ([System.Decimal] 1234.56)
            $plan.accounts[0].cleared_balance | Should -Be ([System.Decimal] 1000)
            $plan.categories[0].activity | Should -Be ([System.Decimal] -125.5)
            $plan.months[0].income | Should -Be ([System.Decimal] 5000)
            $plan.months[0].categories[0].balance | Should -Be ([System.Decimal] 274.5)
            $plan.transactions[0].amount | Should -Be ([System.Decimal] -45)
            $plan.subtransactions[0].amount | Should -Be ([System.Decimal] -20)
            $plan.scheduled_transactions[0].amount | Should -Be ([System.Decimal] -150)
            $plan.scheduled_subtransactions[0].amount | Should -Be ([System.Decimal] -50)
        }
        It -Name 'keeps *_formatted, drops *_currency, and leaves non-amount numbers alone' -Test {
            $plan = Get-YnabPlan
            $plan.accounts[0].balance_formatted | Should -Be '$1,234.56'
            $plan.accounts[0].PSObject.Properties.Name | Should -Not -Contain 'balance_currency'
            $plan.scheduled_transactions[0].PSObject.Properties.Name | Should -Not -Contain 'amount_currency'
            $plan.months[0].age_of_money | Should -Be 41
            $plan.currency_format.decimal_digits | Should -Be 2
        }
        It -Name 'leaves deleted items out of nested lists' -Test {
            $plan = Get-YnabPlan
            $plan.accounts.id | Should -Be @('a-1')
            $plan.transactions.id | Should -Be @('t-1')
            , $plan.accounts | Should -BeOfType ([System.Array])
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'lets the request error surface unchanged' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
                Write-Error -Message 'YNAB API error 404 resource_not_found (404.2): Resource not found' -ErrorId 'YnabApi.resource_not_found' -ErrorAction Stop
            }
            $err = $null
            try {
                Get-YnabPlan -PlanId $script:planTwo
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.resource_not_found*'
        }
    }
}
