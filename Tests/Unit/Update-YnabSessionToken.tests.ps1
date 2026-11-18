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

Describe -Name 'Update-YnabSessionToken' -Fixture {
    BeforeAll {
        $script:secretSentinel = 'client-secret-sentinel-31f7'
        $script:refreshSentinel = 'refresh-sentinel-c08e'

        # PUTS AN OAUTH SESSION IN MODULE STATE WITH THE GIVEN CALLBACK
        $script:newSession = {
            param ($Callback)
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ Callback = $Callback; S = $script:secretSentinel; R = $script:refreshSentinel } -ScriptBlock {
                $script:YnabToken = ConvertTo-SecureString -String 'access-1' -AsPlainText -Force
                $script:YnabOAuth = @{
                    ClientId       = 'client-1'
                    ClientSecret   = ConvertTo-SecureString -String $S -AsPlainText -Force
                    RefreshToken   = ConvertTo-SecureString -String $R -AsPlainText -Force
                    ExpiresAt      = (Get-Date).ToUniversalTime().AddSeconds(3600)
                    OnTokenRefresh = $Callback
                }
            }
        }
        $script:plain = { param ($Secure) ConvertFrom-SecureString -SecureString $Secure -AsPlainText }
        $script:sessionState = {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { @{ Token = $script:YnabToken; OAuth = $script:YnabOAuth; CacheCount = $script:YnabCache.Count } }
        }
    }
    BeforeEach {
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $TokenGrant } -MockWith {
            [PSCustomObject] @{ access_token = 'access-2'; token_type = 'bearer'; expires_in = 7200; refresh_token = 'refresh-2' }
        }
    }
    AfterEach {
        InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabOAuth = $null; $script:YnabToken = $null; $script:YnabCache.Clear() }
    }
    Context -Name 'refreshing' -Fixture {
        It -Name 'raises YnabOAuthNoSession without an OAuth session' -Test {
            $err = $null
            try {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken }
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthNoSession,*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'sends a refresh_token grant with the client credentials' -Test {
            & $script:newSession -Callback $null
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken }
            $filter = { $TokenGrant['grant_type'] -eq 'refresh_token' -and $TokenGrant['client_id'] -eq 'client-1' -and $TokenGrant['client_secret'] -eq 'client-secret-sentinel-31f7' -and $TokenGrant['refresh_token'] -eq 'refresh-sentinel-c08e' }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'replaces both tokens and the expiry, and disposes the old tokens' -Test {
            & $script:newSession -Callback $null
            $before = & $script:sessionState
            $oldAccess = $before.Token
            $oldRefresh = $before.OAuth.RefreshToken
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken }
            $after = & $script:sessionState
            & $script:plain $after.Token | Should -Be 'access-2'
            & $script:plain $after.OAuth.RefreshToken | Should -Be 'refresh-2'
            $secondsLeft = ($after.OAuth.ExpiresAt - (Get-Date).ToUniversalTime()).TotalSeconds
            $secondsLeft | Should -BeGreaterThan 7190
            $secondsLeft | Should -BeLessOrEqual 7200
            $after.OAuth.ExpiresAt.Kind | Should -Be 'Utc'
            # A METHOD, NOT A PROPERTY: POWERSHELL SWALLOWS EXCEPTIONS FROM PROPERTY GETTERS AND WRAPS THOSE FROM METHODS
            { $oldAccess.Copy() } | Should -Throw -ExpectedMessage '*disposed*'
            { $oldRefresh.Copy() } | Should -Throw -ExpectedMessage '*disposed*'
        }
        It -Name 'sends a different grant with -Grant, adding the client credentials' -Test {
            & $script:newSession -Callback $null
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                Update-YnabSessionToken -Grant @{ grant_type = 'authorization_code'; code = 'code-1'; code_verifier = 'verifier-1'; redirect_uri = 'http://localhost:8765/callback' }
            }
            $filter = { $TokenGrant['grant_type'] -eq 'authorization_code' -and $TokenGrant['code'] -eq 'code-1' -and $TokenGrant['code_verifier'] -eq 'verifier-1' -and $TokenGrant['client_secret'] -eq 'client-secret-sentinel-31f7' -and -not $TokenGrant.Contains('refresh_token') }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'handing the token to the caller' -Fixture {
        It -Name 'calls -OnTokenRefresh once with a separate copy of the new refresh token and the expiry' -Test {
            $received = [System.Collections.Generic.List[System.Object]]::new()
            & $script:newSession -Callback { param ($Token) $received.Add($Token) }.GetNewClosure()
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken }
            $received | Should -HaveCount 1
            $after = & $script:sessionState
            & $script:plain $received[0].RefreshToken | Should -Be 'refresh-2'
            $received[0].AccessTokenExpiresAt | Should -Be $after.OAuth.ExpiresAt
            [System.Object]::ReferenceEquals($received[0].RefreshToken, $after.OAuth.RefreshToken) | Should -BeFalse
            $received[0].RefreshToken.Dispose()
            & $script:plain $after.OAuth.RefreshToken | Should -Be 'refresh-2'
        }
        It -Name 'calls -OnTokenRefresh before the next request is sent' -Test {
            $events = [System.Collections.Generic.List[System.String]]::new()
            & $script:newSession -Callback { $events.Add('callback') }.GetNewClosure()
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabOAuth.ExpiresAt = (Get-Date).ToUniversalTime().AddSeconds(10) }
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path } -MockWith { $events.Add('request') }.GetNewClosure()
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken; Invoke-YnabRequest -Path '/user' } | Out-Null
            $events | Should -Be @('callback', 'request')
        }
        It -Name 'keeps the session and writes a non-terminating error when -OnTokenRefresh throws' -Test {
            & $script:newSession -Callback { Write-Error -Message 'vault is locked' -ErrorAction Stop }
            $callbackErrors = $null
            {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken -ErrorVariable +cbErrors -ErrorAction SilentlyContinue; $script:lastCallbackErrors = $cbErrors }
            } | Should -Not -Throw
            $callbackErrors = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:lastCallbackErrors }
            # -ErrorVariable ALSO HOLDS THE CALLBACK'S OWN THROW; PICK THE MODULE'S RECORD
            $moduleErrors = @($callbackErrors).Where({ $_.FullyQualifiedErrorId -like 'YnabOAuthTokenRefreshCallbackFailed*' })
            $moduleErrors | Should -HaveCount 1
            $moduleErrors[0].ToString() | Should -BeLike '*may not have been saved*vault is locked*'
            & $script:plain (& $script:sessionState).Token | Should -Be 'access-2'
        }
        It -Name 'becomes a terminating error when the caller sets ErrorAction Stop' -Test {
            & $script:newSession -Callback { Write-Error -Message 'vault is locked' -ErrorAction Stop }
            {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken -ErrorAction Stop }
            } | Should -Throw -ErrorId 'YnabOAuthTokenRefreshCallbackFailed*'
        }
    }
    Context -Name 'failure' -Fixture {
        BeforeEach {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $TokenGrant } -MockWith {
                Write-Error -Message 'YNAB OAuth error 400 invalid_grant: The provided authorization grant is invalid' -ErrorId 'YnabOAuth.invalid_grant' -Category AuthenticationError -ErrorAction Stop
            }
        }
        It -Name 'ends the session, clears the cache and raises YnabOAuthRefreshFailed' -Test {
            & $script:newSession -Callback $null
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache['x'] = @{ PlanId = 'p' } }
            $err = $null
            try {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken }
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthRefreshFailed,*'
            $err.CategoryInfo.Category | Should -Be 'AuthenticationError'
            $err.ToString() | Should -BeLike '*refresh token is no longer valid*invalid_grant*authorize again with Connect-Ynab*'
            $state = & $script:sessionState
            $state.Token | Should -BeNullOrEmpty
            $state.OAuth | Should -BeNullOrEmpty
            $state.CacheCount | Should -Be 0
        }
    }
    Context -Name 'token protection' -Fixture {
        It -Name 'never writes the client secret or refresh token to any stream, on <Outcome>' -ForEach @(
            @{ Outcome = 'success'; Fail = $false }
            @{ Outcome = 'failure'; Fail = $true }
        ) -Test {
            if ($Fail) {
                Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $TokenGrant } -MockWith {
                    Write-Error -Message 'YNAB OAuth error 400 invalid_grant: x' -ErrorId 'YnabOAuth.invalid_grant' -ErrorAction Stop
                }
            }
            & $script:newSession -Callback $null
            $log = [System.Collections.Generic.List[System.Object]]::new()
            $err = $null
            try {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Update-YnabSessionToken -Verbose -Debug *>&1 } | ForEach-Object -Process { $log.Add($PSItem) }
            }
            catch {
                $err = $PSItem
            }
            $log.Count | Should -BeGreaterThan 0
            $everything = ($log | Out-String) + ($err | Format-List -Property * -Force | Out-String)
            $everything | Should -Not -BeLike ('*{0}*' -f $script:secretSentinel)
            $everything | Should -Not -BeLike ('*{0}*' -f $script:refreshSentinel)
            $everything | Should -Not -BeLike '*refresh-2*'
            $everything | Should -Not -BeLike '*access-2*'
        }
    }
}
