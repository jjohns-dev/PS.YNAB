BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Invoke-YnabCachedRequest' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'
        $script:accountsPath = '/plans/{0}/accounts' -f $script:planOne

        $script:fullJson = '{ "accounts": [ { "id": "a", "name": "Checking", "balance": 1000, "last_reconciled_at": "2026-11-10T12:00:00Z", "deleted": false }, { "id": "b", "name": "Savings", "balance": 5000, "deleted": false } ], "server_knowledge": 100 }'
        $script:deltaJson = '{ "accounts": [ { "id": "a", "name": "Checking", "balance": 1500, "last_reconciled_at": "2026-11-14T09:30:00Z", "deleted": false }, { "id": "b", "deleted": true }, { "id": "c", "name": "Card", "balance": -200, "deleted": false } ], "server_knowledge": 105 }'
        $script:mergedByHandJson = '{ "accounts": [ { "id": "a", "name": "Checking", "balance": 1500, "last_reconciled_at": "2026-11-14T09:30:00Z", "deleted": false }, { "id": "c", "name": "Card", "balance": -200, "deleted": false } ], "server_knowledge": 105 }'

        # CALLS THE PRIVATE FUNCTION; RETURNS ITS OUTPUT
        $script:invokeCached = {
            param ($Arguments)
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ A = $Arguments } -ScriptBlock {
                Invoke-YnabCachedRequest @A
            }
        }
        $script:cacheCount = {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Count }
        }
    }
    BeforeEach {
        InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Clear() }
        $fullResponse = $script:fullJson
        $deltaResponse = $script:deltaJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $fullResponse | ConvertFrom-Json
        }.GetNewClosure()
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query -and $Query.Contains('last_knowledge_of_server') } -MockWith {
            $deltaResponse | ConvertFrom-Json
        }.GetNewClosure()
    }
    AfterAll {
        InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Clear() }
    }
    Context -Name 'first and later calls' -Fixture {
        It -Name 'sends a full request first and stores the result' -Test {
            $result = & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath }
            $result.accounts.id | Should -Be @('a', 'b')
            & $script:cacheCount | Should -Be 1
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { -not $Query } -Times 1 -Exactly -Scope It
        }
        It -Name 'sends last_knowledge_of_server on the next call and merges the changes' -Test {
            & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } | Out-Null
            $result = & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath }
            $result.accounts.id | Should -Be @('a', 'c')
            $result.accounts[0].balance | Should -Be 1500
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query -and $Query['last_knowledge_of_server'] -eq 100 } -Times 1 -Exactly -Scope It
        }
        It -Name 'sends the newest server knowledge on each following call' -Test {
            1..3 | ForEach-Object -Process { & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } | Out-Null }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query -and $Query['last_knowledge_of_server'] -eq 105 } -Times 1 -Exactly -Scope It
        }
        It -Name 'keeps the caller''s query when adding the server knowledge' -Test {
            $transactionsPath = '/plans/{0}/transactions' -f $script:planOne
            1..2 | ForEach-Object -Process { & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $transactionsPath; Query = @{ type = 'unapproved' } } | Out-Null }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query['type'] -eq 'unapproved' -and $Query['last_knowledge_of_server'] -eq 100 } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'equivalence with a full download (AC-6)' -Fixture {
        It -Name 'returns the same output as an uncached call on the same final data' -Test {
            & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } | Out-Null
            $cachedResult = & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath }
            $fullResult = $script:mergedByHandJson | ConvertFrom-Json
            $toText = { param ($Value) InModuleScope -ModuleName $env:BHProjectName -Parameters @{ V = $Value } -ScriptBlock { @($V.accounts | ConvertFrom-YnabData) | ConvertTo-Json -Depth 20 -Compress } }
            (& $toText $cachedResult) | Should -BeExactly (& $toText $fullResult)
        }
    }
    Context -Name 'cache keys' -Fixture {
        It -Name 'keeps separate entries for <Case>' -ForEach @(
            @{ Case = 'different plans'; Second = @{ PlanId = '22222222-2222-4222-8222-222222222222'; Path = '/plans/22222222-2222-4222-8222-222222222222/accounts' } }
            @{ Case = 'different queries'; Second = @{ PlanId = '11111111-1111-4111-8111-111111111111'; Path = '/plans/11111111-1111-4111-8111-111111111111/accounts'; Query = @{ type = 'unapproved' } } }
            @{ Case = 'different paths'; Second = @{ PlanId = '11111111-1111-4111-8111-111111111111'; Path = '/plans/11111111-1111-4111-8111-111111111111/payees' } }
        ) -Test {
            & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } | Out-Null
            & $script:invokeCached -Arguments $Second | Out-Null
            & $script:cacheCount | Should -Be 2
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query -and $Query.Contains('last_knowledge_of_server') } -Times 0 -Exactly -Scope It
        }
        It -Name 'does not make last_knowledge_of_server part of the key' -Test {
            1..3 | ForEach-Object -Process { & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } | Out-Null }
            & $script:cacheCount | Should -Be 1
        }
    }
    Context -Name 'keyword plans' -Fixture {
        It -Name 'does not cache <PlanId>, sends a full request each time and says why' -ForEach @(
            @{ PlanId = 'last-used' }
            @{ PlanId = 'default' }
        ) -Test {
            $verbose = 1..2 | ForEach-Object -Process {
                InModuleScope -ModuleName $env:BHProjectName -Parameters @{ P = $PlanId } -ScriptBlock {
                    Invoke-YnabCachedRequest -PlanId $P -Path ('/plans/{0}/accounts' -f $P) -Verbose 4>&1
                }
            } | Where-Object -FilterScript { $_ -is [System.Management.Automation.VerboseRecord] }
            & $script:cacheCount | Should -Be 0
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { -not $Query } -Times 2 -Exactly -Scope It
            ($verbose.Message -like ('Not cached: -PlanId is `[{0}`]*' -f $PlanId)) | Should -HaveCount 2
        }
    }
    Context -Name 'isolation' -Fixture {
        It -Name 'is not changed when the caller changes the returned object' -Test {
            $first = & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath }
            $first.accounts[0].balance = 999999
            $first.accounts[0].name = 'Changed'
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $entry = $script:YnabCache.Values | Select-Object -First 1
                $entry.Data.accounts[0].balance | Should -Be 1000
                $entry.Data.accounts[0].name | Should -Be 'Checking'
            }
        }
        It -Name 'returns the same value types as the response, including UTC dates' -Test {
            $result = & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath }
            $result.accounts[0].balance | Should -BeOfType ([System.Int64])
            $result.accounts[0].last_reconciled_at | Should -BeOfType ([System.DateTime])
            $result.accounts[0].last_reconciled_at.Kind | Should -Be 'Utc'
            , $result.accounts | Should -BeOfType ([System.Object[]])
        }
    }
    Context -Name 'errors' -Fixture {
        It -Name 'leaves the entry unchanged when the delta request fails' -Test {
            & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } | Out-Null
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Query -and $Query.Contains('last_knowledge_of_server') } -MockWith {
                Write-Error -Message 'YNAB API error 500' -ErrorId 'YnabApi.Http500' -ErrorAction Stop
            }
            { & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } } | Should -Throw
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $entry = $script:YnabCache.Values | Select-Object -First 1
                $entry.ServerKnowledge | Should -Be 100
                $entry.Data.accounts.id | Should -Be @('a', 'b')
            }
        }
        It -Name 'drops the entry and raises the error when merging fails' -Test {
            & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath } | Out-Null
            Mock -CommandName Merge-YnabDelta -ModuleName $env:BHProjectName -MockWith {
                Write-Error -Message 'merge failed' -ErrorId 'MergeFailed' -ErrorAction Stop
            }
            $err = $null
            try {
                & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath }
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'MergeFailed*'
            & $script:cacheCount | Should -Be 0
        }
        It -Name 'does not cache a response without server knowledge' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
                '{ "accounts": [ { "id": "a" } ] }' | ConvertFrom-Json
            }
            $result = & $script:invokeCached -Arguments @{ PlanId = $script:planOne; Path = $script:accountsPath }
            $result.accounts.id | Should -Be @('a')
            & $script:cacheCount | Should -Be 0
        }
    }
}
