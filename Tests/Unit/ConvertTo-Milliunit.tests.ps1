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
            @{ Amount = 12.34d; Expected = 12340 }
            @{ Amount = -12.34d; Expected = -12340 }
            @{ Amount = 0d; Expected = 0 }
            @{ Amount = 0.001d; Expected = 1 }
            @{ Amount = 1000000d; Expected = 1000000000 }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                ConvertTo-Milliunit -Amount $Amount | Should -Be $Expected
            }
        }
        It -Name 'returns a System.Int64' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                ConvertTo-Milliunit -Amount 1.5d | Should -BeOfType ([System.Int64])
            }
        }
    }
    Context -Name 'input types (#18: the same result on every PowerShell version)' -Fixture {
        It -Name 'returns 12340 for 12.34 as a <TypeName>' -ForEach @(
            @{ TypeName = 'decimal'; Amount = 12.34d }
            @{ TypeName = 'double'; Amount = 12.34 }
            @{ TypeName = 'single'; Amount = [System.Single] 12.34 }
            @{ TypeName = 'string'; Amount = '12.34' }
            @{ TypeName = 'string with spaces'; Amount = ' 12.34 ' }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                ConvertTo-Milliunit -Amount $Amount | Should -Be 12340
            }
        }
        It -Name 'returns <Expected> for <Amount> as a <TypeName>' -ForEach @(
            @{ TypeName = 'double'; Amount = -0.001; Expected = -1 }
            @{ TypeName = 'double'; Amount = 987654.321; Expected = 987654321 }
            @{ TypeName = 'double sum with binary noise'; Amount = 0.1 + 0.2; Expected = 300 }
            @{ TypeName = 'Int32'; Amount = 3; Expected = 3000 }
            @{ TypeName = 'Int64'; Amount = [System.Int64] -42; Expected = -42000 }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                ConvertTo-Milliunit -Amount $Amount | Should -Be $Expected
            }
        }
        It -Name 'parses strings with the invariant culture whatever the current culture' -Test {
            $originalCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('de-DE')
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                    ConvertTo-Milliunit -Amount '12.34' | Should -Be 12340
                }
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $originalCulture
            }
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'accepts mixed types from the pipeline' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $results = 1d, -2.5, '0.75', 4 | ConvertTo-Milliunit
                $results | Should -Be @(1000, -2500, 750, 4000)
            }
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'rejects <Amount> as having more than three decimal places' -ForEach @(
            @{ Amount = 1.2345d }
            @{ Amount = 1.2345 }
            @{ Amount = '1.2345' }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                $err = $null
                try {
                    ConvertTo-Milliunit -Amount $Amount -ErrorAction Stop
                }
                catch {
                    $err = $PSItem
                }
                $err.FullyQualifiedErrorId | Should -BeLike 'YnabAmountPrecision,*'
                $err.CategoryInfo.Category | Should -Be 'InvalidArgument'
                $err.ToString() | Should -BeLike 'Amount `[1.2345`] has more than three decimal places*'
            }
        }
        It -Name 'rejects <Amount> as not a number' -ForEach @(
            @{ Amount = '12,34' }
            @{ Amount = 'abc' }
            @{ Amount = '' }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                $err = $null
                try {
                    ConvertTo-Milliunit -Amount $Amount -ErrorAction Stop
                }
                catch {
                    $err = $PSItem
                }
                $err.FullyQualifiedErrorId | Should -BeLike 'YnabAmountNotNumber,*'
            }
        }
        It -Name 'rejects a value of another type' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $err = $null
                try {
                    ConvertTo-Milliunit -Amount ([System.DateTime]::new(2026, 11, 15)) -ErrorAction Stop
                }
                catch {
                    $err = $PSItem
                }
                $err.FullyQualifiedErrorId | Should -BeLike 'YnabAmountType,*'
                $err.CategoryInfo.Category | Should -Be 'InvalidType'
            }
        }
        It -Name 'rejects null' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                { ConvertTo-Milliunit -Amount $null -ErrorAction Stop } | Should -Throw
            }
        }
    }
    Context -Name 'round trip' -Fixture {
        It -Name 'returns <Amount> unchanged after converting to milliunits and back' -ForEach @(
            @{ Amount = 12.34d }
            @{ Amount = -0.001d }
            @{ Amount = 987654.321d }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                $Amount | ConvertTo-Milliunit | ConvertFrom-Milliunit | Should -Be $Amount
            }
        }
    }
}
