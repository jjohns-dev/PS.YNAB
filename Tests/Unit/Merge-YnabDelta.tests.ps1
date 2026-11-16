BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Merge-YnabDelta' -Fixture {
    BeforeAll {
        # MERGES TWO JSON DOCUMENTS AND RETURNS THE CACHED OBJECT AFTERWARDS
        $script:mergeJson = {
            param ($CachedJson, $DeltaJson)
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ C = $CachedJson; D = $DeltaJson } -ScriptBlock {
                $cachedObject = $C | ConvertFrom-Json
                Merge-YnabDelta -Cached $cachedObject -Delta ($D | ConvertFrom-Json)
                $cachedObject
            }
        }
    }
    Context -Name 'keyed lists' -Fixture {
        It -Name 'replaces a changed item, keeps the others, and keeps their order' -Test {
            $result = & $script:mergeJson -CachedJson '{ "accounts": [ { "id": "a", "name": "A" }, { "id": "b", "name": "B" }, { "id": "c", "name": "C" } ] }' -DeltaJson '{ "accounts": [ { "id": "b", "name": "B2" } ] }'
            $result.accounts.id | Should -Be @('a', 'b', 'c')
            $result.accounts.name | Should -Be @('A', 'B2', 'C')
        }
        It -Name 'appends an item with a new key' -Test {
            $result = & $script:mergeJson -CachedJson '{ "payees": [ { "id": "a" } ] }' -DeltaJson '{ "payees": [ { "id": "z", "name": "New" } ] }'
            $result.payees.id | Should -Be @('a', 'z')
        }
        It -Name 'removes an item the delta marks deleted' -Test {
            $result = & $script:mergeJson -CachedJson '{ "payees": [ { "id": "a" }, { "id": "b" } ] }' -DeltaJson '{ "payees": [ { "id": "a", "deleted": true } ] }'
            $result.payees.id | Should -Be @('b')
        }
        It -Name 'does not add a deleted item it never had' -Test {
            $result = & $script:mergeJson -CachedJson '{ "payees": [ { "id": "a" } ] }' -DeltaJson '{ "payees": [ { "id": "x", "deleted": true } ] }'
            $result.payees.id | Should -Be @('a')
        }
        It -Name 'keeps the list an array when one item or none is left' -Test {
            $one = & $script:mergeJson -CachedJson '{ "payees": [ { "id": "a" }, { "id": "b" } ] }' -DeltaJson '{ "payees": [ { "id": "a", "deleted": true } ] }'
            , $one.payees | Should -BeOfType ([System.Array])
            $none = & $script:mergeJson -CachedJson '{ "payees": [ { "id": "a" } ] }' -DeltaJson '{ "payees": [ { "id": "a", "deleted": true } ] }'
            , $none.payees | Should -BeOfType ([System.Array])
            $none.payees.Count | Should -Be 0
        }
        It -Name 'leaves the list unchanged for an empty delta list' -Test {
            $result = & $script:mergeJson -CachedJson '{ "payees": [ { "id": "a" } ] }' -DeltaJson '{ "payees": [] }'
            $result.payees.id | Should -Be @('a')
        }
        It -Name 'keys month objects by month' -Test {
            $result = & $script:mergeJson -CachedJson '{ "months": [ { "month": "2026-10-01", "income": 1 }, { "month": "2026-11-01", "income": 2 } ] }' -DeltaJson '{ "months": [ { "month": "2026-11-01", "income": 5 }, { "month": "2026-12-01", "income": 9 } ] }'
            $result.months.month | Should -Be @('2026-10-01', '2026-11-01', '2026-12-01')
            $result.months.income | Should -Be @(1, 5, 9)
        }
    }
    Context -Name 'recursion' -Fixture {
        It -Name 'keeps unchanged categories when a group arrives with only its changed categories' -Test {
            $cached = '{ "category_groups": [ { "id": "g", "name": "Everyday", "categories": [ { "id": "c1", "budgeted": 1 }, { "id": "c2", "budgeted": 2 } ] } ] }'
            $delta = '{ "category_groups": [ { "id": "g", "name": "Everyday", "categories": [ { "id": "c2", "budgeted": 7 } ] } ] }'
            $result = & $script:mergeJson -CachedJson $cached -DeltaJson $delta
            $result.category_groups[0].categories.id | Should -Be @('c1', 'c2')
            $result.category_groups[0].categories.budgeted | Should -Be @(1, 7)
        }
        It -Name 'removes a deleted subtransaction inside a changed transaction' -Test {
            $cached = '{ "transactions": [ { "id": "t", "amount": -3, "subtransactions": [ { "id": "s1", "amount": -1 }, { "id": "s2", "amount": -2 } ] } ] }'
            $delta = '{ "transactions": [ { "id": "t", "amount": -1, "subtransactions": [ { "id": "s2", "deleted": true } ] } ] }'
            $result = & $script:mergeJson -CachedJson $cached -DeltaJson $delta
            $result.transactions[0].amount | Should -Be -1
            $result.transactions[0].subtransactions.id | Should -Be @('s1')
        }
        It -Name 'merges the nested lists of an object, such as a full plan' -Test {
            $cached = '{ "plan": { "id": "p", "name": "Old", "accounts": [ { "id": "a" } ], "transactions": [ { "id": "t1" } ] } }'
            $delta = '{ "plan": { "id": "p", "name": "New", "accounts": [], "transactions": [ { "id": "t2" } ] } }'
            $result = & $script:mergeJson -CachedJson $cached -DeltaJson $delta
            $result.plan.name | Should -Be 'New'
            $result.plan.accounts.id | Should -Be @('a')
            $result.plan.transactions.id | Should -Be @('t1', 't2')
        }
    }
    Context -Name 'other properties' -Fixture {
        It -Name 'replaces scalar values and adds new properties' -Test {
            $result = & $script:mergeJson -CachedJson '{ "server_knowledge": 1, "name": "A" }' -DeltaJson '{ "server_knowledge": 5, "note": "x" }'
            $result.server_knowledge | Should -Be 5
            $result.name | Should -Be 'A'
            $result.note | Should -Be 'x'
        }
        It -Name 'replaces a list whose items have no key' -Test {
            $result = & $script:mergeJson -CachedJson '{ "tags": [ "a", "b" ], "rows": [ { "v": 1 } ] }' -DeltaJson '{ "tags": [ "c" ], "rows": [ { "v": 2 } ] }'
            $result.tags | Should -Be @('c')
            $result.rows.v | Should -Be @(2)
        }
        It -Name 'replaces a value with null' -Test {
            $result = & $script:mergeJson -CachedJson '{ "note": "x" }' -DeltaJson '{ "note": null }'
            $result.note | Should -BeNullOrEmpty
        }
    }
}
