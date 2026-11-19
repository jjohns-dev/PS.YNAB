[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Fake codes built for test fixtures; no real secret is involved.')]
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

Describe -Name 'Receive-YnabAuthorizationCode' -Fixture {
    BeforeAll {
        $script:codeSentinel = 'auth-code-sentinel-5d2e'
        $script:state = 'state-abc'
        $script:authorizeUri = 'https://app.ynab.com/oauth/authorize?client_id=c'

        # A PORT FREE AT RUN TIME, SO THE TESTS NEVER DEPEND ON A FIXED ONE
        $script:freePort = {
            $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $probe.Start()
            try {
                $probe.LocalEndpoint.Port
            }
            finally {
                $probe.Stop()
            }
        }
        $script:canListen = {
            param ($Port)
            $probe = [System.Net.HttpListener]::new()
            $probe.Prefixes.Add(('http://localhost:{0}/' -f $Port))
            try {
                $probe.Start()
                $true
            }
            catch {
                $false
            }
            finally {
                $probe.Close()
            }
        }

        # CALLS THE FUNCTION, RETURNING THE CODE IN PLAIN TEXT, THE ERROR, AND EVERY OTHER STREAM
        $script:receive = {
            param ($Arguments)
            $result = @{ Code = $null; Error = $null; Streams = @() }
            try {
                $result.Streams = @(InModuleScope -ModuleName $env:BHProjectName -Parameters @{ A = $Arguments } -ScriptBlock {
                        param ($A)
                        Receive-YnabAuthorizationCode @A -Verbose -Debug
                    } *>&1)
            }
            catch {
                $result.Error = $PSItem
            }
            $codes = @($result.Streams | Where-Object { $PSItem -is [System.Security.SecureString] })
            if ($codes) {
                $result.Code = ConvertFrom-SecureString -SecureString $codes[0] -AsPlainText
            }
            $result.Streams = @($result.Streams | Where-Object { $PSItem -isnot [System.Security.SecureString] })
            $result
        }
        $script:leaks = {
            param ($Result)
            $texts = @($Result.Streams | ForEach-Object { [System.String] $PSItem })
            if ($Result.Error) {
                $texts += $Result.Error.ToString()
                $texts += [System.String] $Result.Error.Exception.Message
            }
            @($texts | Where-Object { $PSItem -like ('*{0}*' -f $script:codeSentinel) }).Count -gt 0
        }
    }
    BeforeEach {
        $script:port = & $script:freePort
        $script:redirect = 'http://localhost:{0}/callback' -f $script:port
        $script:loopbackArgs = @{
            AuthorizeUri   = $script:authorizeUri
            RedirectUri    = $script:redirect
            State          = $script:state
            TimeoutSeconds = 10
        }

        # THE "BROWSER": A THREAD JOB REQUESTING EACH URL IN $script:browserUrls ONCE THE LISTENER IS UP
        $script:browserUrls = @()
        $script:browserJob = $null
        Mock -CommandName Start-Process -ModuleName $env:BHProjectName -MockWith {
            $urls = $script:browserUrls
            $script:browserJob = Start-ThreadJob -ScriptBlock {
                $using:urls | ForEach-Object -Process {
                    try {
                        [System.Int32] (Invoke-WebRequest -Uri $PSItem -SkipHttpErrorCheck -TimeoutSec 5).StatusCode
                    }
                    catch {
                        -1
                    }
                }
            }
        }
    }
    AfterEach {
        if ($script:browserJob) {
            $null = $script:browserJob | Wait-Job -Timeout 10
            $script:browserJob | Remove-Job -Force
        }
    }
    Context -Name 'loopback redirect' -Fixture {
        It -Name 'returns the code as a SecureString and answers the browser 200' -Test {
            $script:browserUrls = @('{0}?code={1}&state={2}' -f $script:redirect, $script:codeSentinel, $script:state)
            $result = & $script:receive -Arguments $script:loopbackArgs
            $result.Error | Should -BeNullOrEmpty
            $result.Code | Should -BeExactly $script:codeSentinel
            @($script:browserJob | Wait-Job | Receive-Job) | Should -Be @(200)
        }
        It -Name 'starts listening before it opens the browser, once' -Test {
            $script:browserUrls = @('{0}?code={1}&state={2}' -f $script:redirect, $script:codeSentinel, $script:state)
            $null = & $script:receive -Arguments $script:loopbackArgs
            $filter = { $FilePath -eq $script:authorizeUri }
            Should -Invoke -CommandName Start-Process -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'writes the authorize URL to the information stream' -Test {
            $script:browserUrls = @('{0}?code={1}&state={2}' -f $script:redirect, $script:codeSentinel, $script:state)
            $result = & $script:receive -Arguments $script:loopbackArgs
            $info = @($result.Streams | Where-Object { $PSItem -is [System.Management.Automation.InformationRecord] })
            ($info.MessageData -join ' ') | Should -BeLike ('*{0}*' -f $script:authorizeUri)
        }
        It -Name 'ignores a request on another path with 404 and keeps waiting' -Test {
            $script:browserUrls = @(
                'http://localhost:{0}/favicon.ico' -f $script:port
                '{0}?code={1}&state={2}' -f $script:redirect, $script:codeSentinel, $script:state
            )
            $result = & $script:receive -Arguments $script:loopbackArgs
            $result.Code | Should -BeExactly $script:codeSentinel
            @($script:browserJob | Wait-Job | Receive-Job) | Should -Be @(404, 200)
        }
        It -Name 'never writes the code to another stream' -Test {
            $script:browserUrls = @('{0}?code={1}&state={2}' -f $script:redirect, $script:codeSentinel, $script:state)
            $result = & $script:receive -Arguments $script:loopbackArgs
            $result.Streams | Should -Not -BeNullOrEmpty
            & $script:leaks $result | Should -BeFalse
        }
        It -Name 'stops the listener after receiving the code' -Test {
            $script:browserUrls = @('{0}?code={1}&state={2}' -f $script:redirect, $script:codeSentinel, $script:state)
            $null = & $script:receive -Arguments $script:loopbackArgs
            & $script:canListen $script:port | Should -BeTrue
        }
        It -Name 'accepts a 127.0.0.1 redirect URI' -Test {
            $redirect = 'http://127.0.0.1:{0}/callback' -f $script:port
            $script:loopbackArgs['RedirectUri'] = $redirect
            $script:browserUrls = @('{0}?code={1}&state={2}' -f $redirect, $script:codeSentinel, $script:state)
            $result = & $script:receive -Arguments $script:loopbackArgs
            $result.Code | Should -BeExactly $script:codeSentinel
        }
    }
    Context -Name 'rejected redirects' -Fixture {
        It -Name 'raises YnabOAuthAuthorizationFailed for <Case>, answers 400 and stops the listener' -ForEach @(
            @{ Case = 'an error'; Query = 'error=access_denied&error_description=denied&state=state-abc'; Expected = '*access_denied*' }
            @{ Case = 'a different state'; Query = 'code=auth-code-sentinel-5d2e&state=forged'; Expected = '*state*' }
            @{ Case = 'a missing state'; Query = 'code=auth-code-sentinel-5d2e'; Expected = '*state*' }
            @{ Case = 'no code'; Query = 'state=state-abc'; Expected = '*no authorization code*' }
        ) -Test {
            $script:browserUrls = @('{0}?{1}' -f $script:redirect, $Query)
            $result = & $script:receive -Arguments $script:loopbackArgs
            $result.Code | Should -BeNullOrEmpty
            $result.Error.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthAuthorizationFailed,*'
            $result.Error.ToString() | Should -BeLike $Expected
            & $script:leaks $result | Should -BeFalse
            @($script:browserJob | Wait-Job | Receive-Job) | Should -Be @(400)
            & $script:canListen $script:port | Should -BeTrue
        }
    }
    Context -Name 'listener failures' -Fixture {
        It -Name 'raises YnabOAuthTimeout when no redirect arrives, and stops the listener' -Test {
            $script:loopbackArgs['TimeoutSeconds'] = 1
            $result = & $script:receive -Arguments $script:loopbackArgs
            $result.Error.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthTimeout,*'
            & $script:canListen $script:port | Should -BeTrue
        }
        It -Name 'raises YnabOAuthListenerFailed naming the URI and -RedirectUri before opening the browser' -Test {
            $occupier = [System.Net.HttpListener]::new()
            $occupier.Prefixes.Add(('http://localhost:{0}/' -f $script:port))
            $occupier.Start()
            try {
                $result = & $script:receive -Arguments $script:loopbackArgs
            }
            finally {
                $occupier.Close()
            }
            $result.Error.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthListenerFailed,*'
            $result.Error.ToString() | Should -BeLike ('*{0}*-RedirectUri*' -f $script:redirect)
            Should -Invoke -CommandName Start-Process -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects the redirect URI <Uri> before listening or opening the browser' -ForEach @(
            @{ Uri = 'http://example.com:8765/callback' }
            @{ Uri = 'https://localhost:8765/callback' }
            @{ Uri = 'urn:ietf:wg:oauth:2.0:oob' }
            @{ Uri = 'not a uri' }
        ) -Test {
            $script:loopbackArgs['RedirectUri'] = $Uri
            $result = & $script:receive -Arguments $script:loopbackArgs
            $result.Error.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthRedirectNotLoopback,*'
            Should -Invoke -CommandName Start-Process -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'out of band' -Fixture {
        BeforeEach {
            $script:oobArgs = @{ AuthorizeUri = $script:authorizeUri; OutOfBand = $true }
        }
        It -Name 'opens the browser and returns the code typed at a secure prompt' -Test {
            Mock -CommandName Read-Host -ModuleName $env:BHProjectName -MockWith {
                ConvertTo-SecureString -String 'auth-code-sentinel-5d2e' -AsPlainText -Force
            }
            $result = & $script:receive -Arguments $script:oobArgs
            $result.Code | Should -BeExactly $script:codeSentinel
            & $script:leaks $result | Should -BeFalse
            Should -Invoke -CommandName Start-Process -ModuleName $env:BHProjectName -Times 1 -Exactly -Scope It
            Should -Invoke -CommandName Read-Host -ModuleName $env:BHProjectName -ParameterFilter { $AsSecureString } -Times 1 -Exactly -Scope It
        }
        It -Name 'raises YnabOAuthAuthorizationFailed when nothing is entered' -Test {
            Mock -CommandName Read-Host -ModuleName $env:BHProjectName -MockWith { [System.Security.SecureString]::new() }
            $result = & $script:receive -Arguments $script:oobArgs
            $result.Error.FullyQualifiedErrorId | Should -BeLike 'YnabOAuthAuthorizationFailed,*'
        }
    }
    Context -Name 'no browser' -Fixture {
        It -Name 'warns and keeps waiting when the browser cannot be opened' -Test {
            Mock -CommandName Start-Process -ModuleName $env:BHProjectName -MockWith {
                Write-Error -Message 'no browser' -ErrorAction Stop
            }
            Mock -CommandName Read-Host -ModuleName $env:BHProjectName -MockWith {
                ConvertTo-SecureString -String 'auth-code-sentinel-5d2e' -AsPlainText -Force
            }
            $result = & $script:receive -Arguments @{ AuthorizeUri = $script:authorizeUri; OutOfBand = $true }
            $result.Code | Should -BeExactly $script:codeSentinel
            @($result.Streams | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 1
        }
    }
}
