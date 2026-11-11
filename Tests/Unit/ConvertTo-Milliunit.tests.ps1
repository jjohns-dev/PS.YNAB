BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'ConvertTo-Milliunit' -Fixture {
    Context -Name 'normal usage' -Fixture {
        It -Name 'returns <Expected> milliunits for <Amount>' -ForEach @(
            @{ Amount = '12.34'; Expected = 12340 }
            @{ Amount = '-12.34'; Expected = -12340 }
            @{ Amount = '0'; Expected = 0 }
            @{ Amount = '0.001'; Expected = 1 }
            @{ Amount = '1000000'; Expected = 1000000000 }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                ConvertTo-Milliunit -Amount ([System.Decimal] $Amount) | Should -Be $Expected
            }
        }
        It -Name 'returns a System.Int64' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                ConvertTo-Milliunit -Amount 1.5 | Should -BeOfType ([System.Int64])
            }
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'accepts multiple values from the pipeline' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $results = [System.Decimal] 1, [System.Decimal] -2.5 | ConvertTo-Milliunit
                $results | Should -HaveCount 2
                $results[1] | Should -Be -2500
            }
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'rejects an amount with more than three decimal places' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $err = $null
                try {
                    ConvertTo-Milliunit -Amount ([System.Decimal] '1.2345') -ErrorAction Stop
                }
                catch {
                    $err = $PSItem
                }
                $err | Should -Not -BeNullOrEmpty
                $err.FullyQualifiedErrorId | Should -BeLike 'YnabAmountPrecision,*'
                $err.CategoryInfo.Category | Should -Be 'InvalidArgument'
                $err.ToString() | Should -BeLike '*1.2345*more than three decimal places*'
            }
        }
    }
    Context -Name 'round trip' -Fixture {
        It -Name 'returns <Amount> unchanged after converting to milliunits and back' -ForEach @(
            @{ Amount = '12.34' }
            @{ Amount = '-0.001' }
            @{ Amount = '987654.321' }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                $original = [System.Decimal] $Amount
                $original | ConvertTo-Milliunit | ConvertFrom-Milliunit | Should -Be $original
            }
        }
    }
}
