BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Get-YnabPayee' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'
        $script:payeeId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'

        $script:listJson = '{
            "payees": [
                { "id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", "name": "Grocer", "transfer_account_id": null, "deleted": false },
                { "id": "ffffffff-ffff-4fff-8fff-ffffffffffff", "name": "Transfer : Savings", "transfer_account_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "deleted": false },
                { "id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd", "name": "Merged payee", "transfer_account_id": null, "deleted": true }
            ],
            "server_knowledge": 12
        }'
        $script:singleJson = '{ "payee": { "id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee", "name": "Grocer", "transfer_account_id": null, "deleted": false } }'
    }
    BeforeEach {
        $listResponse = $script:listJson
        $singleResponse = $script:singleJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $listResponse | ConvertFrom-Json
        }.GetNewClosure()
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/payees/*' } -MockWith {
            $singleResponse | ConvertFrom-Json
        }.GetNewClosure()
    }
    Context -Name 'listing payees' -Fixture {
        It -Name 'sends one request to the last-used plan''s payees by default' -Test {
            Get-YnabPayee | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq '/plans/last-used/payees' } -Times 1 -Exactly -Scope It
        }
        It -Name 'returns one object per payee, leaving out deleted payees' -Test {
            $result = @(Get-YnabPayee)
            $result | Should -HaveCount 2
            $result.name | Should -Be @('Grocer', 'Transfer : Savings')
        }
        It -Name 'keeps YNAB''s property names' -Test {
            $transfer = @(Get-YnabPayee)[1]
            $transfer.transfer_account_id | Should -Be 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        }
    }
    Context -Name 'getting one payee' -Fixture {
        It -Name 'sends one request to the single-payee endpoint and returns the payee' -Test {
            $result = @(Get-YnabPayee -PayeeId $script:payeeId)
            $result | Should -HaveCount 1
            $result[0].name | Should -Be 'Grocer'
            $expectedPath = '/plans/last-used/payees/{0}' -f $script:payeeId
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects an empty payee ID before sending a request' -Test {
            { Get-YnabPayee -PayeeId '' } | Should -Throw
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects a malformed plan ID before sending a request' -Test {
            $err = $null
            try {
                Get-YnabPayee -PlanId 'Household'
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'lists the payees of each piped plan, one request each' -Test {
            @(
                [PSCustomObject] @{ id = $script:planOne; plan_id = $script:planOne }
                [PSCustomObject] @{ id = $script:planTwo; plan_id = $script:planTwo }
            ) | Get-YnabPayee | Out-Null
            $firstPath = '/plans/{0}/payees' -f $script:planOne
            $secondPath = '/plans/{0}/payees' -f $script:planTwo
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $firstPath } -Times 1 -Exactly -Scope It
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $secondPath } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'lets the request error surface unchanged' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/payees/*' } -MockWith {
                Write-Error -Message 'YNAB API error 404 resource_not_found (404.2): Resource not found' -ErrorId 'YnabApi.resource_not_found' -ErrorAction Stop
            }
            $err = $null
            try {
                Get-YnabPayee -PayeeId $script:payeeId
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.resource_not_found*'
        }
    }
}
