BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Disconnect-Ynab' -Fixture {
    BeforeAll {
        $script:token = ConvertTo-SecureString -String 'sentinel-token-7f3a9c' -AsPlainText -Force
        Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
            [PSCustomObject] @{ data = [PSCustomObject] @{ user = [PSCustomObject] @{ id = 'u-1' } } }
        }
    }
    BeforeEach {
        Disconnect-Ynab
    }
    Context -Name 'normal usage' -Fixture {
        It -Name 'ends the session so later requests fail with YnabNotConnected' -Test {
            Connect-Ynab -Token $script:token
            Disconnect-Ynab
            $err = $null
            try {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Invoke-YnabRequest -Path '/plans' }
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabNotConnected,*'
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -Times 1 -Exactly -Scope It
        }
        It -Name 'writes nothing to the output' -Test {
            Connect-Ynab -Token $script:token
            Disconnect-Ynab | Should -BeNullOrEmpty
        }
    }
    Context -Name 'no session' -Fixture {
        It -Name 'should not throw when no session exists' -Test {
            { Disconnect-Ynab } | Should -Not -Throw
        }
        It -Name 'should not throw when run twice' -Test {
            Connect-Ynab -Token $script:token
            { Disconnect-Ynab; Disconnect-Ynab } | Should -Not -Throw
        }
    }
}
