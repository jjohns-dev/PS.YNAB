BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'ConvertFrom-Milliunit' -Fixture {
    Context -Name 'normal usage' -Fixture {
        It -Name 'returns <Expected> for <Milliunit> milliunits' -ForEach @(
            @{ Milliunit = 12340; Expected = 12.34 }
            @{ Milliunit = -12340; Expected = -12.34 }
            @{ Milliunit = 0; Expected = 0 }
            @{ Milliunit = 1; Expected = 0.001 }
            @{ Milliunit = -999; Expected = -0.999 }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                ConvertFrom-Milliunit -Milliunit $Milliunit | Should -Be ([System.Decimal] $Expected)
            }
        }
        It -Name 'returns a System.Decimal' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                ConvertFrom-Milliunit -Milliunit 1500 | Should -BeOfType ([System.Decimal])
            }
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'accepts multiple values from the pipeline' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $results = 1000, -2500 | ConvertFrom-Milliunit
                $results | Should -HaveCount 2
                $results[1] | Should -Be ([System.Decimal] -2.5)
            }
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'rejects <Description> instead of rounding it' -ForEach @(
            @{ Description = 'a fractional value passed by name'; Piped = $false; Value = 12.34 }
            @{ Description = 'a fractional value from the pipeline'; Piped = $true; Value = 12.34 }
            @{ Description = 'a value just above a whole number'; Piped = $false; Value = '1000.001' }
            @{ Description = 'a negative fractional value'; Piped = $false; Value = -0.5 }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters $_ -ScriptBlock {
                $err = $null
                try {
                    if ($Piped) {
                        $Value | ConvertFrom-Milliunit -ErrorAction Stop
                    }
                    else {
                        ConvertFrom-Milliunit -Milliunit $Value -ErrorAction Stop
                    }
                }
                catch {
                    $err = $PSItem
                }
                $err | Should -Not -BeNullOrEmpty
                $err.FullyQualifiedErrorId | Should -BeLike 'YnabMilliunitNotWhole,*'
                $err.CategoryInfo.Category | Should -Be 'InvalidArgument'
                $err.ToString() | Should -BeLike '*not a whole number of milliunits'
            }
        }
    }
}
