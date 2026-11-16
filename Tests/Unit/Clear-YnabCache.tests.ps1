BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Clear-YnabCache' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'
        $script:getKeys = {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { @($script:YnabCache.Keys | Sort-Object) }
        }
    }
    BeforeEach {
        InModuleScope -ModuleName $env:BHProjectName -Parameters @{ One = $script:planOne; Two = $script:planTwo } -ScriptBlock {
            $script:YnabCache.Clear()
            $script:YnabCache[('/plans/{0}/accounts?' -f $One)] = @{ PlanId = $One; ServerKnowledge = 1; Data = $null }
            $script:YnabCache[('/plans/{0}/payees?' -f $One)] = @{ PlanId = $One; ServerKnowledge = 1; Data = $null }
            $script:YnabCache[('/plans/{0}/accounts?' -f $Two)] = @{ PlanId = $Two; ServerKnowledge = 1; Data = $null }
        }
    }
    AfterAll {
        InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Clear() }
    }
    It -Name 'clears every cached result and writes nothing to the output' -Test {
        Clear-YnabCache | Should -BeNullOrEmpty
        @(& $script:getKeys) | Should -HaveCount 0
    }
    It -Name 'clears only one plan''s results with -PlanId' -Test {
        Clear-YnabCache -PlanId $script:planOne
        & $script:getKeys | Should -Be @(('/plans/{0}/accounts?' -f $script:planTwo))
    }
    It -Name 'matches the plan ID regardless of letter case' -Test {
        Clear-YnabCache -PlanId $script:planTwo.ToUpperInvariant()
        @(& $script:getKeys) | Should -HaveCount 2
    }
    It -Name 'does nothing for a plan with no cached results' -Test {
        { Clear-YnabCache -PlanId '33333333-3333-4333-8333-333333333333' } | Should -Not -Throw
        @(& $script:getKeys) | Should -HaveCount 3
    }
    It -Name 'rejects <Value> as -PlanId' -ForEach @(
        @{ Value = 'last-used' }
        @{ Value = 'default' }
        @{ Value = 'Household' }
    ) -Test {
        $err = $null
        try {
            Clear-YnabCache -PlanId $Value
        }
        catch {
            $err = $PSItem
        }
        $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
        $err.ToString() | Should -BeLike '*never cached*'
        @(& $script:getKeys) | Should -HaveCount 3
    }
}
