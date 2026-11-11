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
