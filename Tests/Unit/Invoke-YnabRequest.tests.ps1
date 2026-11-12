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

Describe -Name 'Invoke-YnabRequest' -Fixture {
    BeforeAll {
        $script:sentinel = 'sentinel-token-7f3a9c'
        $script:token = ConvertTo-SecureString -String $script:sentinel -AsPlainText -Force

        # RAISES AN ERROR SHAPED LIKE THE ONE Invoke-RestMethod RAISES FOR AN HTTP ERROR STATUS
        $script:newHttpError = {
            param ($Status, $Body)
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode] $Status)
            $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $response)
            $record = [System.Management.Automation.ErrorRecord]::new($exception, 'WebCmdletWebResponseException', 'InvalidOperation', $null)
            if ($Body) {
                $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body)
            }
            $record
        }

        # INVOKES THE PRIVATE FUNCTION AND RETURNS ITS ERROR RECORD, OR NOTHING IF IT SUCCEEDED
        $script:getRequestError = {
            param ($Arguments)
            try {
                InModuleScope -ModuleName $env:BHProjectName -Parameters @{ A = $Arguments } -ScriptBlock {
                    Invoke-YnabRequest @A
                } | Out-Null
            }
            catch {
                $PSItem
            }
        }

        Mock -CommandName Start-Sleep -ModuleName $env:BHProjectName
    }
    Context -Name 'normal usage' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                [PSCustomObject] @{ data = [PSCustomObject] @{ user = [PSCustomObject] @{ id = 'u-1' } } }
            }
        }
        It -Name 'returns the data object of the response' -Test {
            $result = InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token } -ScriptBlock {
                Invoke-YnabRequest -Path '/user' -Token $T
            }
            $result.user.id | Should -Be 'u-1'
        }
        It -Name 'sends to the fixed base URI with GET by default' -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token } -ScriptBlock {
                Invoke-YnabRequest -Path '/plans/last-used/accounts' -Token $T
            } | Out-Null
            $filter = { $Uri -eq 'https://api.ynab.com/v1/plans/last-used/accounts' -and $Method -eq 'Get' }
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'authenticates with -Authentication Bearer and -Token, never a header' -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token } -ScriptBlock {
                Invoke-YnabRequest -Path '/user' -Token $T
            } | Out-Null
            $filter = {
                $Authentication -eq 'Bearer' -and
                $null -eq $Headers -and
                (ConvertFrom-SecureString -SecureString $Token -AsPlainText) -eq 'sentinel-token-7f3a9c'
            }
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'uses the session token when no token is passed' -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token } -ScriptBlock {
                $script:YnabToken = $T
                try {
                    Invoke-YnabRequest -Path '/user'
                }
                finally {
                    $script:YnabToken = $null
                }
            } | Out-Null
            $filter = { (ConvertFrom-SecureString -SecureString $Token -AsPlainText) -eq 'sentinel-token-7f3a9c' }
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'sends a body as compressed JSON with an application/json content type' -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token } -ScriptBlock {
                $body = @{ transaction = @{ memo = 'coffee'; amount = -4500 } }
                Invoke-YnabRequest -Method Post -Path '/plans/last-used/transactions' -Body $body -Token $T
            } | Out-Null
            $filter = {
                $ContentType -eq 'application/json' -and
                $Method -eq 'Post' -and
                ($Body | ConvertFrom-Json).transaction.memo -eq 'coffee'
            }
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'query string' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                [PSCustomObject] @{ data = [PSCustomObject] @{ ok = $true } }
            }
        }
        It -Name 'appends <Case>' -ForEach @(
            @{ Case = 'entries in sorted key order'; Query = @{ until_date = '2026-11-30'; since_date = '2026-11-01'; type = 'unapproved' }; Expected = 'https://api.ynab.com/v1/plans/last-used/transactions?since_date=2026-11-01&type=unapproved&until_date=2026-11-30' }
            @{ Case = 'URI-escaped keys and values'; Query = @{ 'a b' = 'x&y=z/?' }; Expected = 'https://api.ynab.com/v1/plans/last-used/transactions?a%20b=x%26y%3Dz%2F%3F' }
            @{ Case = 'only entries whose value is not null'; Query = @{ since_date = '2026-11-01'; type = $null }; Expected = 'https://api.ynab.com/v1/plans/last-used/transactions?since_date=2026-11-01' }
            @{ Case = 'no question mark when every value is null'; Query = @{ type = $null }; Expected = 'https://api.ynab.com/v1/plans/last-used/transactions' }
            @{ Case = 'no question mark for an empty query'; Query = @{}; Expected = 'https://api.ynab.com/v1/plans/last-used/transactions' }
            @{ Case = 'nothing when no query is given'; Query = 'unbound'; Expected = 'https://api.ynab.com/v1/plans/last-used/transactions' }
        ) -Test {
            InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token; Q = $Query } -ScriptBlock {
                $requestParams = @{ Path = '/plans/last-used/transactions'; Token = $T }
                if ($Q -isnot [System.String]) {
                    $requestParams['Query'] = $Q
                }
                Invoke-YnabRequest @requestParams
            } | Out-Null
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -ParameterFilter { $Uri -eq $Expected } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects a path that does not begin with /' -Test {
            {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Invoke-YnabRequest -Path 'user' }
            } | Should -Throw
        }
        It -Name 'rejects an unsupported method' -Test {
            {
                InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { Invoke-YnabRequest -Method Head -Path '/user' }
            } | Should -Throw
        }
    }
    Context -Name 'no session' -Fixture {
        BeforeAll {
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName
        }
        It -Name 'raises YnabNotConnected and makes no HTTP call' -Test {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock { $script:YnabToken = $null }
            $err = & $script:getRequestError -Arguments @{ Path = '/user' }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabNotConnected,*'
            $err.CategoryInfo.Category | Should -Be 'ConnectionError'
            $err.ToString() | Should -BeLike '*Connect-Ynab*'
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'raises status <Status> with YNAB error <Name> and category <Category>' -ForEach @(
            @{ Status = 400; Id = '400'; Name = 'bad_request'; Category = 'InvalidOperation' }
            @{ Status = 403; Id = '403.1'; Name = 'subscription_lapsed'; Category = 'PermissionDenied' }
            @{ Status = 404; Id = '404.2'; Name = 'resource_not_found'; Category = 'ObjectNotFound' }
            @{ Status = 500; Id = '500'; Name = 'internal_server_error'; Category = 'InvalidOperation' }
        ) -Test {
            $body = '{{"error":{{"id":"{0}","name":"{1}","detail":"Something went wrong"}}}}' -f $Id, $Name
            $record = & $script:newHttpError -Status $Status -Body $body
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            $err = & $script:getRequestError -Arguments @{ Path = '/plans/p-1'; Token = $script:token }
            $err.ToString() | Should -Be ('YNAB API error {0} {1} ({2}): Something went wrong' -f $Status, $Name, $Id)
            $err.FullyQualifiedErrorId | Should -BeLike ('YnabApi.{0},*' -f $Name)
            $err.CategoryInfo.Category | Should -Be $Category
            $err.TargetObject | Should -Be 'Get /plans/p-1'
            $err.Exception | Should -BeOfType ([Microsoft.PowerShell.Commands.HttpResponseException])
            [System.Int32] $err.Exception.Response.StatusCode | Should -Be $Status
        }
        It -Name 'adds a reconnect hint to a 401' -Test {
            $record = & $script:newHttpError -Status 401 -Body '{"error":{"id":"401","name":"unauthorized","detail":"Unauthorized"}}'
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            $err = & $script:getRequestError -Arguments @{ Path = '/user'; Token = $script:token }
            $err.ToString() | Should -Be 'YNAB API error 401 unauthorized (401): Unauthorized. The token may be invalid or revoked. Run Connect-Ynab again.'
            $err.CategoryInfo.Category | Should -Be 'AuthenticationError'
        }
        It -Name 'raises the HTTP status when the body is not YNAB''s error shape' -Test {
            $record = & $script:newHttpError -Status 502 -Body '<html>Bad Gateway</html>'
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            $err = & $script:getRequestError -Arguments @{ Path = '/user'; Token = $script:token }
            $err.ToString() | Should -Be 'YNAB API returned HTTP 502'
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.Http502,*'
        }
        It -Name 'raises the HTTP status when there is no body' -Test {
            $record = & $script:newHttpError -Status 503 -Body $null
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            $err = & $script:getRequestError -Arguments @{ Path = '/user'; Token = $script:token }
            $err.ToString() | Should -Be 'YNAB API returned HTTP 503'
        }
        It -Name 'lets a failure with no HTTP response pass through unchanged' -Test {
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                Write-Error -Message 'No such host is known.' -ErrorId 'DnsFailure' -ErrorAction Stop
            }
            $err = & $script:getRequestError -Arguments @{ Path = '/user'; Token = $script:token }
            $err.ToString() | Should -Be 'No such host is known.'
            $err.FullyQualifiedErrorId | Should -BeLike 'DnsFailure*'
            Should -Invoke -CommandName Start-Sleep -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'rate limiting' -Fixture {
        It -Name 'retries a 429 three times after 15, 30 and 60 seconds, then raises it' -Test {
            $record = & $script:newHttpError -Status 429 -Body '{"error":{"id":"429","name":"too_many_requests","detail":"Too many requests"}}'
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            $err = & $script:getRequestError -Arguments @{ Path = '/user'; Token = $script:token }
            $err.CategoryInfo.Category | Should -Be 'LimitsExceeded'
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.too_many_requests,*'
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -Times 4 -Exactly -Scope It
            foreach ($seconds in 15, 30, 60) {
                $filter = [System.Management.Automation.ScriptBlock]::Create(('$Seconds -eq {0}' -f $seconds))
                Should -Invoke -CommandName Start-Sleep -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
            }
        }
        It -Name 'returns the data when a retry succeeds' -Test {
            $record = & $script:newHttpError -Status 429 -Body '{"error":{"id":"429","name":"too_many_requests","detail":"Too many requests"}}'
            $state = @{ Calls = 0 }
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                $state.Calls++
                if ($state.Calls -eq 1) {
                    Write-Error -ErrorRecord $record -ErrorAction Stop
                }
                [PSCustomObject] @{ data = [PSCustomObject] @{ ok = $true } }
            }.GetNewClosure()
            $result = InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token } -ScriptBlock {
                Invoke-YnabRequest -Path '/user' -Token $T
            }
            $result.ok | Should -BeTrue
            Should -Invoke -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -Times 2 -Exactly -Scope It
            Should -Invoke -CommandName Start-Sleep -ModuleName $env:BHProjectName -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'token protection' -Fixture {
        It -Name 'never writes the token to the error record, verbose or debug output for status <Status>' -ForEach @(
            @{ Status = 401 }
            @{ Status = 429 }
            @{ Status = 502 }
        ) -Test {
            $record = & $script:newHttpError -Status $Status -Body '{"error":{"id":"x","name":"x","detail":"x"}}'
            Mock -CommandName Invoke-RestMethod -ModuleName $env:BHProjectName -MockWith {
                Write-Error -ErrorRecord $record -ErrorAction Stop
            }.GetNewClosure()
            $log = [System.Collections.Generic.List[System.Object]]::new()
            $err = $null
            try {
                InModuleScope -ModuleName $env:BHProjectName -Parameters @{ T = $script:token } -ScriptBlock {
                    Invoke-YnabRequest -Path '/user' -Token $T -Verbose -Debug 4>&1 5>&1
                } | ForEach-Object -Process { $log.Add($PSItem) }
            }
            catch {
                $err = $PSItem
            }
            $err | Should -Not -BeNullOrEmpty
            $log.Count | Should -BeGreaterThan 0
            ($err | Out-String) | Should -Not -BeLike ('*{0}*' -f $script:sentinel)
            ($err | Format-List -Property * -Force | Out-String) | Should -Not -BeLike ('*{0}*' -f $script:sentinel)
            ($log | Out-String) | Should -Not -BeLike ('*{0}*' -f $script:sentinel)
        }
    }
}
