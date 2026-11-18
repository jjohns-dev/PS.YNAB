[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Fake tokens built for test fixtures; no real secret is involved.')]
param()

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
    Context -Name 'session cache' -Fixture {
        It -Name 'clears the cache, with or without a session' -Test {
            foreach ($withSession in $true, $false) {
                if ($withSession) {
                    Connect-Ynab -Token $script:token
                }
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                    $script:YnabCache['/plans/11111111-1111-4111-8111-111111111111/accounts?'] = @{ PlanId = '11111111-1111-4111-8111-111111111111'; ServerKnowledge = 1; Data = $null }
                }
                Disconnect-Ynab
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Count } | Should -Be 0 -Because ('with session: {0}' -f $withSession)
            }
        }
    }
    Context -Name 'OAuth session' -Fixture {
        It -Name 'clears the OAuth record and disposes its refresh token and client secret' -Test {
            $secrets = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $script:YnabToken = ConvertTo-SecureString -String 'access-1' -AsPlainText -Force
                $script:YnabOAuth = @{
                    ClientId       = 'client-1'
                    ClientSecret   = ConvertTo-SecureString -String 'secret-1' -AsPlainText -Force
                    RefreshToken   = ConvertTo-SecureString -String 'refresh-1' -AsPlainText -Force
                    ExpiresAt      = (Get-Date).ToUniversalTime().AddHours(1)
                    OnTokenRefresh = $null
                }
                $script:YnabOAuth.ClientSecret, $script:YnabOAuth.RefreshToken
            }
            Disconnect-Ynab
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $null -eq $script:YnabOAuth -and $null -eq $script:YnabToken } | Should -BeTrue
            foreach ($secret in $secrets) {
                { $secret.Copy() } | Should -Throw -ExpectedMessage '*disposed*'
            }
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
