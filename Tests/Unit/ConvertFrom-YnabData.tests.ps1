BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'ConvertFrom-YnabData' -Fixture {
    Context -Name 'amount conversion' -Fixture {
        It -Name 'converts every listed amount field from milliunits to decimal' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $fields = foreach ($field in $ynab_amount_fields) {
                    '"{0}": 12340' -f $field
                }
                $record = ('{{ {0} }}' -f ($fields -join ', ')) | ConvertFrom-Json
                $result = ConvertFrom-YnabData -InputObject $record
                foreach ($field in $ynab_amount_fields) {
                    $result.$field | Should -BeOfType ([System.Decimal]) -Because $field
                    $result.$field | Should -Be ([System.Decimal] 12.34) -Because $field
                }
            }
        }
        It -Name 'converts negative and zero amounts' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $result = '{ "amount": -4500, "balance": 0 }' | ConvertFrom-Json | ConvertFrom-YnabData
                $result.amount | Should -Be ([System.Decimal] -4.5)
                $result.balance | Should -Be ([System.Decimal] 0)
            }
        }
        It -Name 'leaves a null amount as null' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $result = '{ "goal_target": null, "debt_original_balance": null }' | ConvertFrom-Json | ConvertFrom-YnabData
                $result.goal_target | Should -BeNullOrEmpty
                $result.debt_original_balance | Should -BeNullOrEmpty
            }
        }
        It -Name 'leaves whole-number fields that are not amounts unchanged' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $json = '{ "server_knowledge": 12340, "age_of_money": 45, "goal_percentage_complete": 80, "goal_day": 15, "currency_format": { "decimal_digits": 2 } }'
                $result = $json | ConvertFrom-Json | ConvertFrom-YnabData
                $result.server_knowledge | Should -Be 12340
                $result.age_of_money | Should -Be 45
                $result.goal_percentage_complete | Should -Be 80
                $result.goal_day | Should -Be 15
                $result.currency_format.decimal_digits | Should -Be 2
                $result.server_knowledge | Should -Not -BeOfType ([System.Decimal])
            }
        }
        It -Name 'converts every value of the account loan maps' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $json = '{ "debt_minimum_payments": { "2026-01-01": 250000, "2026-06-01": 275000 }, "debt_escrow_amounts": { "2026-01-01": 12000 }, "debt_interest_rates": { "2026-01-01": 5250 } }'
                $result = $json | ConvertFrom-Json | ConvertFrom-YnabData
                $result.debt_minimum_payments.'2026-01-01' | Should -Be ([System.Decimal] 250)
                $result.debt_minimum_payments.'2026-06-01' | Should -Be ([System.Decimal] 275)
                $result.debt_escrow_amounts.'2026-01-01' | Should -Be ([System.Decimal] 12)
                $result.debt_interest_rates.'2026-01-01' | Should -Be ([System.Decimal] 5.25)
            }
        }
        It -Name 'leaves a null loan map as null' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $result = '{ "debt_interest_rates": null, "balance": 1000 }' | ConvertFrom-Json | ConvertFrom-YnabData
                $result.debt_interest_rates | Should -BeNullOrEmpty
                $result.balance | Should -Be ([System.Decimal] 1)
            }
        }
    }
    Context -Name 'companion properties' -Fixture {
        It -Name 'removes <amount>_currency and keeps <amount>_formatted' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $json = '{ "balance": 12340, "balance_formatted": "$12.34", "balance_currency": 12.34, "goal_target_currency": null }'
                $result = $json | ConvertFrom-Json | ConvertFrom-YnabData
                $result.PSObject.Properties.Name | Should -Not -Contain 'balance_currency'
                $result.PSObject.Properties.Name | Should -Not -Contain 'goal_target_currency'
                $result.balance_formatted | Should -Be '$12.34'
            }
        }
        It -Name 'keeps a *_currency property that does not belong to an amount field' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $result = '{ "home_currency": "USD" }' | ConvertFrom-Json | ConvertFrom-YnabData
                $result.home_currency | Should -Be 'USD'
            }
        }
    }
    Context -Name 'nested data' -Fixture {
        It -Name 'converts amounts inside nested lists and objects' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $json = '{
                    "plan": {
                        "months": [ { "month": "2026-11-01", "income": 500000, "categories": [ { "name": "Food", "budgeted": 40000, "balance_currency": 1.0 } ] } ],
                        "transactions": [ { "id": "t-1", "amount": -4500, "subtransactions": [ { "id": "s-1", "amount": -2000 } ] } ]
                    }
                }'
                $result = $json | ConvertFrom-Json | ConvertFrom-YnabData
                $result.plan.months[0].income | Should -Be ([System.Decimal] 500)
                $result.plan.months[0].categories[0].budgeted | Should -Be ([System.Decimal] 40)
                $result.plan.months[0].categories[0].PSObject.Properties.Name | Should -Not -Contain 'balance_currency'
                $result.plan.transactions[0].amount | Should -Be ([System.Decimal] -4.5)
                $result.plan.transactions[0].subtransactions[0].amount | Should -Be ([System.Decimal] -2)
            }
        }
        It -Name 'passes non-object values in lists through unchanged' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $result = '{ "tags": [ "a", "b" ] }' | ConvertFrom-Json | ConvertFrom-YnabData
                $result.tags | Should -Be @('a', 'b')
            }
        }
    }
    Context -Name 'deleted items' -Fixture {
        It -Name 'drops deleted items from the pipeline' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $items = '[ { "id": "a", "deleted": false }, { "id": "b", "deleted": true }, { "id": "c" } ]' | ConvertFrom-Json
                $result = @($items | ConvertFrom-YnabData)
                $result.id | Should -Be @('a', 'c')
            }
        }
        It -Name 'drops deleted items from nested lists at any depth' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $json = '{ "transactions": [ { "id": "t-1", "deleted": false, "subtransactions": [ { "id": "s-1", "deleted": true }, { "id": "s-2", "deleted": false } ] }, { "id": "t-2", "deleted": true } ] }'
                $result = $json | ConvertFrom-Json | ConvertFrom-YnabData
                $result.transactions.id | Should -Be @('t-1')
                $result.transactions[0].subtransactions.id | Should -Be @('s-2')
            }
        }
        It -Name 'keeps a nested list as an array when <Case>' -ForEach @(
            @{ Case = 'one item is left'; Json = '{ "items": [ { "id": "a" }, { "id": "b", "deleted": true } ] }'; Count = 1 }
            @{ Case = 'no item is left'; Json = '{ "items": [ { "id": "b", "deleted": true } ] }'; Count = 0 }
            @{ Case = 'the list was empty'; Json = '{ "items": [] }'; Count = 0 }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                $result = $Json | ConvertFrom-Json | ConvertFrom-YnabData
                , $result.items | Should -BeOfType ([System.Array])
                $result.items.Count | Should -Be $Count
            }
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'emits one object per input and nothing for null' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $items = '[ { "id": "a", "amount": 1000 }, { "id": "b", "amount": 2000 } ]' | ConvertFrom-Json
                $result = @($items | ConvertFrom-YnabData)
                $result | Should -HaveCount 2
                $result[1].amount | Should -Be ([System.Decimal] 2)
                @(ConvertFrom-YnabData -InputObject $null) | Should -HaveCount 0
            }
        }
    }
}
