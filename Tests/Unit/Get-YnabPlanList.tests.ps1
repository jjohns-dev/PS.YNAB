BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Get-YnabPlanList' -Fixture {
    BeforeAll {
        $script:plansJson = '{
            "plans": [
                { "id": "p-1", "name": "Household", "last_modified_on": "2026-11-10T12:00:00Z", "first_month": "2024-01-01", "last_month": "2026-12-01", "currency_format": { "iso_code": "USD", "decimal_digits": 2 } },
                { "id": "p-2", "name": "Side business", "last_modified_on": "2026-10-01T08:00:00Z", "first_month": "2025-03-01", "last_month": "2026-12-01", "currency_format": { "iso_code": "EUR", "decimal_digits": 2 } }
            ],
            "default_plan": null
        }'

        # STANDS IN FOR ANY PLAN-SCOPED COMMAND: BINDS -PlanId FROM THE PIPELINE AS THE DESIGN SPECIFIES
        function script:Get-PlanIdProbe {
            [CmdletBinding()]
            [OutputType([System.String])]
            Param(
                [Parameter(ValueFromPipelineByPropertyName)]
                [Alias('plan_id')]
                [System.String] $PlanId = 'last-used'
            )
            Process {
                $PlanId
            }
        }
    }
    BeforeEach {
        $responseJson = $script:plansJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $responseJson | ConvertFrom-Json
        }.GetNewClosure()
    }
    Context -Name 'normal usage' -Fixture {
        It -Name 'sends one GET /plans request' -Test {
            Get-YnabPlanList | Out-Null
            $filter = { $Path -eq '/plans' -and -not $Query -and -not $Body }
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter $filter -Times 1 -Exactly -Scope It
        }
        It -Name 'returns one object per plan with YNAB''s property names' -Test {
            $result = @(Get-YnabPlanList)
            $result | Should -HaveCount 2
            $result.name | Should -Be @('Household', 'Side business')
            $result[0].currency_format.iso_code | Should -Be 'USD'
        }
        It -Name 'adds plan_id equal to id on each plan' -Test {
            $result = @(Get-YnabPlanList)
            $result.plan_id | Should -Be @('p-1', 'p-2')
        }
        It -Name 'returns nothing when there are no plans' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
                '{ "plans": [], "default_plan": null }' | ConvertFrom-Json
            }
            @(Get-YnabPlanList) | Should -HaveCount 0
        }
    }
    Context -Name 'pipeline output' -Fixture {
        It -Name 'binds each plan to a command''s -PlanId through plan_id' -Test {
            Get-YnabPlanList | Get-PlanIdProbe | Should -Be @('p-1', 'p-2')
        }
        It -Name 'rejects an object that has only an id, such as an account, instead of using its id as the plan' -Test {
            $err = $null
            try {
                [PSCustomObject] @{ id = 'account-1'; name = 'Checking' } | Get-PlanIdProbe -ErrorAction Stop
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'InputObjectNotBound,*'
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'lets the request error surface unchanged' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
                Write-Error -Message 'Not connected to YNAB. Run Connect-Ynab first.' -ErrorId 'YnabNotConnected' -ErrorAction Stop
            }
            $err = $null
            try {
                Get-YnabPlanList
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabNotConnected*'
            $err.ToString() | Should -Be 'Not connected to YNAB. Run Connect-Ynab first.'
        }
    }
}
