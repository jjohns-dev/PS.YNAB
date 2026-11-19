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

Describe -Name 'Connect-Ynab' -Fixture {
    BeforeAll {
        $script:sentinel = 'sentinel-token-7f3a9c'
        $script:tokenA = ConvertTo-SecureString -String $script:sentinel -AsPlainText -Force
        $script:tokenB = ConvertTo-SecureString -String 'second-token-b81d' -AsPlainText -Force

        # A 401 SHAPED LIKE THE ONE Invoke-RestMethod RAISES FOR A REJECTED TOKEN
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Unauthorized)
        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $response)
        $script:unauthorized = [System.Management.Automation.ErrorRecord]::new($exception, 'WebCmdletWebResponseException', 'InvalidOperation', $null)
        $script:unauthorized.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"error":{"id":"401","name":"unauthorized","detail":"Unauthorized"}}')

        # SENDS A FOLLOW-UP REQUEST THROUGH THE SESSION, AS A FUTURE PUBLIC FUNCTION WOULD
        $script:sendFollowUp = {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                Invoke-YnabRequest -Path '/plans'
            } | Out-Null
        }
        $script:filterFollowUpWith = {
            param ($Plain)
            [System.Management.Automation.ScriptBlock]::Create(
                ('$Uri -like ''*/plans'' -and (ConvertFrom-SecureString -SecureString $Token -AsPlainText) -eq ''{0}''' -f $Plain)
            )
        }
    }
    BeforeEach {
        Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
            [PSCustomObject] @{ data = [PSCustomObject] @{ user = [PSCustomObject] @{ id = 'u-1' } } }
        }
        Disconnect-Ynab
    }
    AfterAll {
        Disconnect-Ynab
    }
    Context -Name 'normal usage' -Fixture {
        It -Name 'validates the token with one GET /user and writes nothing to the output' -Test {
            $output = Connect-Ynab -Token $script:tokenA
            $output | Should -BeNullOrEmpty
            $filter = { $Uri -eq 'https://api.ynab.com/v1/user' -and $Method -eq 'Get' }
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'sends the token on later requests' -Test {
            Connect-Ynab -Token $script:tokenA
            & $script:sendFollowUp
            $filter = & $script:filterFollowUpWith -Plain $script:sentinel
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'replaces the session when a new token is accepted' -Test {
            Connect-Ynab -Token $script:tokenA
            Connect-Ynab -Token $script:tokenB
            & $script:sendFollowUp
            $filter = & $script:filterFollowUpWith -Plain 'second-token-b81d'
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'leaves the caller''s SecureString usable after Disconnect-Ynab' -Test {
            Connect-Ynab -Token $script:tokenA
            Disconnect-Ynab
            ConvertFrom-SecureString -SecureString $script:tokenA -AsPlainText | Should -Be $script:sentinel
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects a plain string token' -Test {
            { Connect-Ynab -Token 'plain-text-token' } | Should -Throw -ExpectedMessage '*SecureString*'
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'session cache' -Fixture {
        BeforeEach {
            $record = $script:unauthorized
            $rejectB = { (ConvertFrom-SecureString -SecureString $Token -AsPlainText) -eq 'second-token-b81d' }
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $rejectB -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $script:YnabCache['/plans/11111111-1111-4111-8111-111111111111/accounts?'] = @{ PlanId = '11111111-1111-4111-8111-111111111111'; ServerKnowledge = 1; Data = $null }
            }
        }
        AfterAll {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Clear() }
        }
        It -Name 'clears the cache when a token is accepted' -Test {
            Connect-Ynab -Token $script:tokenA
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Count } | Should -Be 0
        }
        It -Name 'leaves the cache alone when the token is rejected' -Test {
            { Connect-Ynab -Token $script:tokenB } | Should -Throw
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabCache.Count } | Should -Be 1
        }
    }
    Context -Name 'replacing an OAuth session' -Fixture {
        BeforeEach {
            $record = $script:unauthorized
            $rejectB = { (ConvertFrom-SecureString -SecureString $Token -AsPlainText) -eq 'second-token-b81d' }
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $rejectB -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $script:YnabToken = ConvertTo-SecureString -String 'oauth-access-1' -AsPlainText -Force
                $script:YnabOAuth = @{
                    ClientId       = 'client-1'
                    ClientSecret   = ConvertTo-SecureString -String 'secret-1' -AsPlainText -Force
                    RefreshToken   = ConvertTo-SecureString -String 'refresh-1' -AsPlainText -Force
                    ExpiresAt      = (Get-Date).ToUniversalTime().AddHours(1)
                    OnTokenRefresh = $null
                }
            }
        }
        AfterAll {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabOAuth = $null }
        }
        It -Name 'replaces an OAuth session with the personal token' -Test {
            Connect-Ynab -Token $script:tokenA
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $null -eq $script:YnabOAuth } | Should -BeTrue
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter { $Uri -like '*oauth/token' } -Times 0 -Exactly -Scope It
        }
        It -Name 'keeps the OAuth session when the personal token is rejected' -Test {
            { Connect-Ynab -Token $script:tokenB } | Should -Throw
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabOAuth.ClientId } | Should -Be 'client-1'
        }
    }
    Context -Name 'error handling' -Fixture {
        BeforeEach {
            $record = $script:unauthorized
            $rejectB = { (ConvertFrom-SecureString -SecureString $Token -AsPlainText) -eq 'second-token-b81d' }
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $rejectB -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
        }
        It -Name 'raises the validation error with the reconnect hint' -Test {
            $err = $null
            try {
                Connect-Ynab -Token $script:tokenB
            }
            catch {
                $err = $PSItem
            }
            $err.ToString() | Should -BeLike '*401 unauthorized*Run Connect-Ynab again.'
            $err.CategoryInfo.Category | Should -Be 'AuthenticationError'
        }
        It -Name 'keeps the existing session when the new token is rejected' -Test {
            Connect-Ynab -Token $script:tokenA
            { Connect-Ynab -Token $script:tokenB } | Should -Throw
            & $script:sendFollowUp
            $filter = & $script:filterFollowUpWith -Plain $script:sentinel
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'stays disconnected when the first token is rejected' -Test {
            { Connect-Ynab -Token $script:tokenB } | Should -Throw
            $err = $null
            try {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Invoke-YnabRequest -Path '/plans' }
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabNotConnected,*'
        }
    }
    Context -Name 'token protection' -Fixture {
        It -Name 'never writes the token to any stream when the token is <Outcome>' -ForEach @(
            @{ Outcome = 'accepted'; Reject = $false }
            @{ Outcome = 'rejected'; Reject = $true }
        ) -Test {
            if ($Reject) {
                $record = $script:unauthorized
                Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                    Write-Error -ErrorRecord $record -ErrorAction Stop
                }.GetNewClosure()
            }
            $log = [System.Collections.Generic.List[System.Object]]::new()
            $err = $null
            try {
                Connect-Ynab -Token $script:tokenA -Verbose -Debug *>&1 | ForEach-Object -Process { $log.Add($PSItem) }
            }
            catch {
                $err = $PSItem
            }
            $log.Count | Should -BeGreaterThan 0
            ($log | Out-String) | Should -Not -BeLike ('*{0}*' -f $script:sentinel)
            ($err | Format-List -Property * -Force | Out-String) | Should -Not -BeLike ('*{0}*' -f $script:sentinel)
        }
    }
}

Describe -Name 'Connect-Ynab with OAuth' -Fixture {
    BeforeAll {
        $script:clientId = 'client-id-1'
        $script:secretSentinel = 'client-secret-sentinel-9a41'
        $script:codeSentinel = 'auth-code-sentinel-0be6'
        $script:refreshSentinel = 'refresh-sentinel-77d3'
        $script:clientSecret = ConvertTo-SecureString -String $script:secretSentinel -AsPlainText -Force
        $script:savedRefresh = ConvertTo-SecureString -String $script:refreshSentinel -AsPlainText -Force
        $script:app = @{ ClientId = $script:clientId; ClientSecret = $script:clientSecret }
        $script:realReceive = InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { ${function:Receive-YnabAuthorizationCode} }
        $script:plain = { param ($Secure) ConvertFrom-SecureString -SecureString $Secure -AsPlainText }
        $script:session = {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                @{ Token = $script:YnabToken; OAuth = $script:YnabOAuth; CacheCount = $script:YnabCache.Count }
            }
        }
    }
    BeforeEach {
        $script:seenAuthorizeUri = $null
        $script:seenGrant = $null
        Mock -CommandName Receive-YnabAuthorizationCode -ModuleName $env:BHProjectName -MockWith {
            $script:seenAuthorizeUri = $AuthorizeUri
            ConvertTo-SecureString -String 'auth-code-sentinel-0be6' -AsPlainText -Force
        }
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $TokenGrant } -MockWith {
            $script:seenGrant = @{} + $TokenGrant
            [PSCustomObject] @{ access_token = 'access-new'; token_type = 'bearer'; expires_in = 7200; refresh_token = 'refresh-new' }
        }
        Disconnect-Ynab
    }
    AfterAll {
        Disconnect-Ynab
    }
    Context -Name 'parameter sets' -Fixture {
        It -Name 'binds <Case> to <Set>' -ForEach @(
            @{ Case = '-Token'; Set = '_token'; Extra = @{ Token = [System.Security.SecureString]::new() }; WithApp = $false }
            @{ Case = 'client credentials'; Set = '_authorize'; Extra = @{}; WithApp = $true }
            @{ Case = '-RedirectUri'; Set = '_authorize'; Extra = @{ RedirectUri = 'http://127.0.0.1:9000/cb' }; WithApp = $true }
            @{ Case = '-OutOfBand'; Set = '_authorizeOutOfBand'; Extra = @{ OutOfBand = $true }; WithApp = $true }
            @{ Case = '-RefreshToken'; Set = '_resume'; Extra = @{ RefreshToken = [System.Security.SecureString]::new() }; WithApp = $true }
        ) -Test {
            $arguments = @{} + $Extra
            if ($WithApp) {
                $arguments += $script:app
            }
            $command = Get-Command -Name Connect-Ynab
            $names = @($arguments.Keys)
            $matched = @($command.ParameterSets | Where-Object {
                    $setNames = $PSItem.Parameters.Name
                    $mandatory = @($PSItem.Parameters | Where-Object IsMandatory | ForEach-Object Name)
                    @($names | Where-Object { $PSItem -notin $setNames }).Count -eq 0 -and
                    @($mandatory | Where-Object { $PSItem -notin $names }).Count -eq 0
                })
            $matched.Name | Should -Be $Set
        }
        It -Name 'rejects <Case>' -ForEach @(
            @{ Case = '-OutOfBand with -RedirectUri'; Extra = @{ OutOfBand = $true; RedirectUri = 'http://localhost:1/cb' } }
            @{ Case = '-RefreshToken with -OutOfBand'; Extra = @{ OutOfBand = $true; RefreshToken = [System.Security.SecureString]::new() } }
            @{ Case = '-Token with client credentials'; Extra = @{ Token = [System.Security.SecureString]::new() } }
        ) -Test {
            $arguments = $script:app + $Extra
            { Connect-Ynab @arguments } | Should -Throw -ErrorId 'AmbiguousParameterSet,Connect-Ynab'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects a plain string client secret' -Test {
            { Connect-Ynab -ClientId 'c' -ClientSecret 'plain-secret' } | Should -Throw -ExpectedMessage '*SecureString*'
        }
    }
    Context -Name 'authorizing in the browser' -Fixture {
        It -Name 'waits on the default redirect URI with the state it sent, for 300 seconds' -Test {
            Connect-Ynab @script:app -OnTokenRefresh {}
            # A SCRIPT VARIABLE, NOT A CLOSURE: A CLOSURE FILTER CANNOT SEE THE BOUND PARAMETERS
            $script:sentState = ([System.Uri] $script:seenAuthorizeUri).Query -replace '^.*[?&]state=([^&]+).*$', '$1'
            $filter = { $RedirectUri -eq 'http://localhost:8765/callback' -and $State -eq $script:sentState -and $TimeoutSeconds -eq 300 }
            Should -Invoke -CommandName Receive-YnabAuthorizationCode -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
            $script:seenAuthorizeUri | Should -BeLike '*redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback*'
        }
        It -Name 'passes -RedirectUri and -TimeoutSeconds through' -Test {
            Connect-Ynab @script:app -RedirectUri 'http://127.0.0.1:9000/cb' -TimeoutSeconds 30 -OnTokenRefresh {}
            $filter = { $RedirectUri -eq 'http://127.0.0.1:9000/cb' -and $TimeoutSeconds -eq 30 }
            Should -Invoke -CommandName Receive-YnabAuthorizationCode -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
            $script:seenGrant['redirect_uri'] | Should -BeExactly 'http://127.0.0.1:9000/cb'
        }
        It -Name 'exchanges the code with the client credentials, redirect URI and the verifier of the challenge sent' -Test {
            Connect-Ynab @script:app -OnTokenRefresh {}
            $script:seenGrant['grant_type'] | Should -BeExactly 'authorization_code'
            $script:seenGrant['code'] | Should -BeExactly $script:codeSentinel
            $script:seenGrant['client_id'] | Should -BeExactly $script:clientId
            $script:seenGrant['client_secret'] | Should -BeExactly $script:secretSentinel
            $script:seenGrant['redirect_uri'] | Should -BeExactly 'http://localhost:8765/callback'
            $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($script:seenGrant['code_verifier']))
            $challenge = [System.Convert]::ToBase64String($hash).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            $script:seenAuthorizeUri | Should -BeLike ('*code_challenge={0}&*' -f $challenge)
        }
        It -Name 'uses the out-of-band redirect URI and prompt with -OutOfBand' -Test {
            Connect-Ynab @script:app -OutOfBand -OnTokenRefresh {}
            Should -Invoke -CommandName Receive-YnabAuthorizationCode -ModuleName $env:BHProjectName -ParameterFilter { $OutOfBand } -Times 1 -Exactly -Scope It
            $script:seenAuthorizeUri | Should -BeLike '*redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob*'
            $script:seenGrant['redirect_uri'] | Should -BeExactly 'urn:ietf:wg:oauth:2.0:oob'
        }
        It -Name 'reads the out-of-band code from a secure prompt' -Test {
            # RUN THE REAL FUNCTION, CAPTURED BEFORE MOCKING, SO ITS Read-Host AND Start-Process HIT THE MOCKS BELOW
            Mock -CommandName Receive-YnabAuthorizationCode -ModuleName $env:BHProjectName -MockWith {
                & $script:realReceive -AuthorizeUri $AuthorizeUri -OutOfBand
            }
            Mock -CommandName Start-Process -ModuleName $env:BHProjectName
            Mock -CommandName Read-Host -ModuleName $env:BHProjectName -MockWith {
                ConvertTo-SecureString -String 'typed-code-31' -AsPlainText -Force
            }
            Connect-Ynab @script:app -OutOfBand -OnTokenRefresh {} 6> $null
            Should -Invoke -CommandName Read-Host -ModuleName $env:BHProjectName -ParameterFilter { $AsSecureString } -Times 1 -Exactly -Scope It
            $script:seenGrant['code'] | Should -BeExactly 'typed-code-31'
        }
    }
    Context -Name 'resuming' -Fixture {
        It -Name 'redeems the refresh token at once, without a browser' -Test {
            Connect-Ynab @script:app -RefreshToken $script:savedRefresh -OnTokenRefresh {}
            Should -Invoke -CommandName Receive-YnabAuthorizationCode -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
            $script:seenGrant['grant_type'] | Should -BeExactly 'refresh_token'
            $script:seenGrant['refresh_token'] | Should -BeExactly $script:refreshSentinel
            $script:seenGrant['client_secret'] | Should -BeExactly $script:secretSentinel
        }
        It -Name 'leaves the caller''s SecureStrings usable after Disconnect-Ynab' -Test {
            Connect-Ynab @script:app -RefreshToken $script:savedRefresh -OnTokenRefresh {}
            Disconnect-Ynab
            & $script:plain $script:savedRefresh | Should -BeExactly $script:refreshSentinel
            & $script:plain $script:clientSecret | Should -BeExactly $script:secretSentinel
        }
        It -Name 'raises YnabOAuthRefreshFailed saying to authorize again, and leaves no session, when the token is rejected' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $TokenGrant } -MockWith {
                Write-Error -Message 'YNAB OAuth error 400 invalid_grant: revoked' -ErrorId 'YnabOAuth.invalid_grant' -ErrorAction Stop
            }
            $err = $null
            try {
                Connect-Ynab @script:app -RefreshToken $script:savedRefresh -OnTokenRefresh {}
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthRefreshFailed,*'
            $err.ToString() | Should -BeLike '*no longer valid*authorize again*'
            $state = & $script:session
            $state.Token | Should -BeNullOrEmpty
            $state.OAuth | Should -BeNullOrEmpty
        }
    }
    Context -Name 'the session' -Fixture {
        It -Name 'holds the access token, refresh token and expiry from the <Set> response' -ForEach @(
            @{ Set = 'authorize'; Extra = @{} }
            @{ Set = 'resume'; Extra = @{ RefreshToken = (ConvertTo-SecureString -String 'r' -AsPlainText -Force) } }
        ) -Test {
            Connect-Ynab @script:app @Extra -OnTokenRefresh {}
            $state = & $script:session
            & $script:plain $state.Token | Should -BeExactly 'access-new'
            & $script:plain $state.OAuth.RefreshToken | Should -BeExactly 'refresh-new'
            $state.OAuth.ClientId | Should -BeExactly $script:clientId
            $state.OAuth.ExpiresAt | Should -BeGreaterThan (Get-Date).ToUniversalTime().AddSeconds(7100)
        }
        It -Name 'hands the first refresh token to -OnTokenRefresh when <Set>' -ForEach @(
            @{ Set = 'authorizing'; Extra = @{} }
            @{ Set = 'resuming'; Extra = @{ RefreshToken = (ConvertTo-SecureString -String 'r' -AsPlainText -Force) } }
        ) -Test {
            $received = [System.Collections.Generic.List[System.Object]]::new()
            Connect-Ynab @script:app @Extra -OnTokenRefresh { param ($Refresh) $received.Add($Refresh) }.GetNewClosure()
            $received.Count | Should -Be 1
            & $script:plain $received[0].RefreshToken | Should -BeExactly 'refresh-new'
        }
        It -Name 'warns that tokens are not saved without -OnTokenRefresh' -Test {
            Connect-Ynab @script:app -WarningVariable warnings -WarningAction SilentlyContinue
            @($warnings).Count | Should -Be 1
            [System.String] $warnings[0] | Should -BeLike '*-OnTokenRefresh*'
        }
        It -Name 'does not warn with -OnTokenRefresh' -Test {
            Connect-Ynab @script:app -OnTokenRefresh {} -WarningVariable warnings -WarningAction SilentlyContinue
            @($warnings).Count | Should -Be 0
        }
        It -Name 'replaces a personal-token session and clears the cache' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $script:YnabToken = ConvertTo-SecureString -String 'personal-1' -AsPlainText -Force
                $script:YnabCache['/plans/x/accounts?'] = @{ ServerKnowledge = 1 }
            }
            Connect-Ynab @script:app -OnTokenRefresh {}
            $state = & $script:session
            & $script:plain $state.Token | Should -BeExactly 'access-new'
            $state.CacheCount | Should -Be 0
        }
        It -Name 'keeps the existing session when authorization fails before the token request' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                $script:YnabToken = ConvertTo-SecureString -String 'personal-1' -AsPlainText -Force
                $script:YnabCache['/plans/x/accounts?'] = @{ ServerKnowledge = 1 }
            }
            Mock -CommandName Receive-YnabAuthorizationCode -ModuleName $env:BHProjectName -MockWith {
                Write-Error -Message 'No authorization arrived' -ErrorId 'YnabOAuthTimeout' -ErrorAction Stop
            }
            $err = $null
            try {
                Connect-Ynab @script:app -OnTokenRefresh {}
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthTimeout*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
            $state = & $script:session
            & $script:plain $state.Token | Should -BeExactly 'personal-1'
            $state.CacheCount | Should -Be 1
        }
    }
    Context -Name 'secret protection' -Fixture {
        It -Name 'never writes the client secret, code or tokens to any stream when <Case>' -ForEach @(
            @{ Case = 'authorizing'; Extra = @{}; Fail = $false }
            @{ Case = 'resuming'; Extra = @{ RefreshToken = 'saved' }; Fail = $false }
            @{ Case = 'the exchange fails'; Extra = @{}; Fail = $true }
            @{ Case = 'the resume fails'; Extra = @{ RefreshToken = 'saved' }; Fail = $true }
        ) -Test {
            $arguments = $script:app + @{ OnTokenRefresh = { param ($Refresh) Write-Verbose -Message ('saved; expires {0:o}' -f $Refresh.AccessTokenExpiresAt) } }
            if ($Extra.ContainsKey('RefreshToken')) {
                $arguments['RefreshToken'] = $script:savedRefresh
            }
            if ($Fail) {
                Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $TokenGrant } -MockWith {
                    Write-Error -Message 'YNAB OAuth error 400 invalid_grant: rejected' -ErrorId 'YnabOAuth.invalid_grant' -ErrorAction Stop
                }
            }
            $log = [System.Collections.Generic.List[System.Object]]::new()
            $err = $null
            try {
                Connect-Ynab @arguments -Verbose -Debug *>&1 | ForEach-Object -Process { $log.Add($PSItem) }
            }
            catch {
                $err = $PSItem
            }
            $log.Count | Should -BeGreaterThan 0
            $text = ($log | Out-String) + ($err | Format-List -Property * -Force | Out-String)
            foreach ($sentinel in $script:secretSentinel, $script:codeSentinel, $script:refreshSentinel, 'access-new', 'refresh-new') {
                $text | Should -Not -BeLike ('*{0}*' -f $sentinel)
            }
        }
    }
}
