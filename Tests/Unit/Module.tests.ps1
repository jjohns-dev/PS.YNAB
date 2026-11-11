#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Scaffold checks for the manifest, loader and exports. Expected to be replaced
# by the shared common tests when pwsh-module-ci#53 centralizes them.

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ManifestPath = Join-Path -Path $script:ProjectRoot -ChildPath 'PS.YNAB.psd1'
    $script:LoaderPath = Join-Path -Path $script:ProjectRoot -ChildPath 'PS.YNAB.psm1'
    # The harness's ImportStagingModule task may have already loaded the staged
    # copy. Remove it so the 'imports without throwing' assertion tests a real
    # import from disk rather than a no-op re-import.
    Get-Module -Name 'PS.YNAB' | Remove-Module -Force
}

Describe -Name 'PS.YNAB module scaffold' -Fixture {
    Context -Name 'Manifest' -Fixture {
        It -Name 'exists on disk' -Test {
            Test-Path -LiteralPath $script:ManifestPath -PathType Leaf |
                Should -BeTrue
        }

        It -Name 'passes Test-ModuleManifest' -Test {
            { Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop } |
                Should -Not -Throw
        }

        It -Name 'declares a minimum PowerShell version of 7.4 or higher' -Test {
            $manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
            $manifest.PowerShellVersion |
                Should -BeGreaterOrEqual ([System.Version]'7.4')
        }

        It -Name 'names the .psm1 loader as RootModule' -Test {
            $manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
            $manifest.RootModule | Should -Be 'PS.YNAB.psm1'
        }
    }

    Context -Name 'Loader' -Fixture {
        It -Name 'exists on disk' -Test {
            Test-Path -LiteralPath $script:LoaderPath -PathType Leaf |
                Should -BeTrue
        }

        It -Name 'imports without throwing' -Test {
            { Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop } |
                Should -Not -Throw
        }
    }

    Context -Name 'Exports' -Fixture {
        It -Name 'exports exactly the functions backed by a Public/ file' -Test {
            $manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
            $exported = @($manifest.ExportedFunctions.Keys | Sort-Object)
            $publicFiles = @(Get-ChildItem -Path (Join-Path $script:ProjectRoot 'Public') -Filter '*.ps1' |
                    ForEach-Object BaseName | Sort-Object)
            # Joined so an empty module compares cleanly: piping an empty array
            # to Should sends nothing, which would pass vacuously.
            ($exported -join ',') | Should -BeExactly ($publicFiles -join ',')
        }
    }
}
