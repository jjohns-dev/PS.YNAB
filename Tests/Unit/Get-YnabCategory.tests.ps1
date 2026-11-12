BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Get-YnabCategory' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'
        $script:categoryId = 'c0000001-0000-4000-8000-000000000001'

        $script:listJson = '{
            "category_groups": [
                { "id": "g-internal", "name": "Internal Master Category", "hidden": false, "internal": true, "deleted": false,
                  "categories": [ { "id": "c-rta", "category_group_id": "g-internal", "category_group_name": "Internal Master Category", "name": "Inflow: Ready to Assign", "hidden": false, "internal": true, "budgeted": 0, "activity": 5000000, "balance": 0, "deleted": false } ] },
                { "id": "g-everyday", "name": "Everyday", "hidden": false, "internal": false, "deleted": false,
                  "categories": [
                    { "id": "c0000001-0000-4000-8000-000000000001", "category_group_id": "g-everyday", "category_group_name": "Everyday", "name": "Food", "hidden": false, "internal": false,
                      "budgeted": 400000, "budgeted_formatted": "$400.00", "budgeted_currency": 400.0, "activity": -125500, "activity_currency": -125.5, "balance": 274500, "balance_currency": 274.5,
                      "goal_type": "NEED", "goal_target": 400000, "goal_target_currency": 400.0, "goal_under_funded": 0, "goal_overall_funded": 400000, "goal_overall_left": 0, "goal_percentage_complete": 100, "deleted": false },
                    { "id": "c-old", "category_group_id": "g-everyday", "category_group_name": "Everyday", "name": "Old category", "hidden": true, "internal": false, "budgeted": 0, "activity": 0, "balance": 0, "deleted": true },
                    { "id": "c-gifts", "category_group_id": "g-everyday", "category_group_name": "Everyday", "name": "Gifts", "hidden": true, "internal": false, "budgeted": 25000, "activity": 0, "balance": 25000, "goal_target": null, "deleted": false }
                  ] },
                { "id": "g-gone", "name": "Removed group", "hidden": false, "internal": false, "deleted": true,
                  "categories": [ { "id": "c-orphan", "category_group_id": "g-gone", "category_group_name": "Removed group", "name": "Orphan", "budgeted": 1000, "activity": 0, "balance": 1000, "deleted": false } ] }
            ],
            "server_knowledge": 99
        }'
        $script:singleJson = '{ "category": { "id": "c0000001-0000-4000-8000-000000000001", "category_group_id": "g-everyday", "category_group_name": "Everyday", "name": "Food", "budgeted": 400000, "budgeted_currency": 400.0, "activity": -125500, "balance": 274500, "deleted": false } }'
    }
    BeforeEach {
        $listResponse = $script:listJson
        $singleResponse = $script:singleJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $listResponse | ConvertFrom-Json
        }.GetNewClosure()
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/categories/*' } -MockWith {
            $singleResponse | ConvertFrom-Json
        }.GetNewClosure()
    }
    Context -Name 'listing categories' -Fixture {
        It -Name 'sends one request to the last-used plan''s categories by default' -Test {
            Get-YnabCategory | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq '/plans/last-used/categories' } -Times 1 -Exactly -Scope It
        }
        It -Name 'returns one object per category instead of nested groups' -Test {
            $result = @(Get-YnabCategory)
            $result.name | Should -Be @('Inflow: Ready to Assign', 'Food', 'Gifts')
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'categories'
        }
        It -Name 'keeps each category''s group ID and name' -Test {
            $food = @(Get-YnabCategory)[1]
            $food.category_group_id | Should -Be 'g-everyday'
            $food.category_group_name | Should -Be 'Everyday'
        }
        It -Name 'includes hidden and internal categories' -Test {
            $result = @(Get-YnabCategory)
            ($result | Where-Object -Property internal -EQ $true).name | Should -Be 'Inflow: Ready to Assign'
            ($result | Where-Object -Property hidden -EQ $true).name | Should -Be 'Gifts'
        }
        It -Name 'leaves out deleted categories and every category of a deleted group' -Test {
            $result = @(Get-YnabCategory)
            $result.id | Should -Not -Contain 'c-old'
            $result.id | Should -Not -Contain 'c-orphan'
        }
        It -Name 'converts budgeted, activity, balance and goal amounts' -Test {
            $food = @(Get-YnabCategory)[1]
            $food.budgeted | Should -Be ([System.Decimal] 400)
            $food.activity | Should -Be ([System.Decimal] -125.5)
            $food.balance | Should -Be ([System.Decimal] 274.5)
            $food.goal_target | Should -Be ([System.Decimal] 400)
            $food.goal_overall_funded | Should -Be ([System.Decimal] 400)
            $food.goal_under_funded | Should -Be ([System.Decimal] 0)
            $food.goal_percentage_complete | Should -Be 100
        }
        It -Name 'keeps *_formatted and drops *_currency' -Test {
            $food = @(Get-YnabCategory)[1]
            $food.budgeted_formatted | Should -Be '$400.00'
            $food.PSObject.Properties.Name.Where({ $_ -like '*_currency' }) | Should -BeNullOrEmpty
        }
    }
    Context -Name 'getting one category' -Fixture {
        It -Name 'sends one request to the single-category endpoint' -Test {
            Get-YnabCategory -CategoryId $script:categoryId | Out-Null
            $expectedPath = '/plans/last-used/categories/{0}' -f $script:categoryId
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'returns the category with its amounts converted' -Test {
            $result = @(Get-YnabCategory -CategoryId $script:categoryId)
            $result | Should -HaveCount 1
            $result[0].budgeted | Should -Be ([System.Decimal] 400)
            $result[0].PSObject.Properties.Name | Should -Not -Contain 'budgeted_currency'
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects an empty category ID before sending a request' -Test {
            { Get-YnabCategory -CategoryId '' } | Should -Throw
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects a malformed plan ID before sending a request' -Test {
            $err = $null
            try {
                Get-YnabCategory -PlanId 'not-a-plan'
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'lists the categories of each piped plan, one request each' -Test {
            @(
                [PSCustomObject] @{ id = $script:planOne; plan_id = $script:planOne }
                [PSCustomObject] @{ id = $script:planTwo; plan_id = $script:planTwo }
            ) | Get-YnabCategory | Out-Null
            $firstPath = '/plans/{0}/categories' -f $script:planOne
            $secondPath = '/plans/{0}/categories' -f $script:planTwo
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $firstPath } -Times 1 -Exactly -Scope It
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $secondPath } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'lets the request error surface unchanged' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/categories/*' } -MockWith {
                Write-Error -Message 'YNAB API error 404 resource_not_found (404.2): Resource not found' -ErrorId 'YnabApi.resource_not_found' -ErrorAction Stop
            }
            $err = $null
            try {
                Get-YnabCategory -CategoryId $script:categoryId
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.resource_not_found*'
        }
    }
}
