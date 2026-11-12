BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'Get-YnabMonth' -Fixture {
    BeforeAll {
        $script:planOne = '11111111-1111-4111-8111-111111111111'
        $script:planTwo = '22222222-2222-4222-8222-222222222222'

        $script:listJson = '{
            "months": [
                { "month": "2026-10-01", "note": null, "income": 5000000, "income_formatted": "$5,000.00", "income_currency": 5000.0, "budgeted": 4800000, "budgeted_currency": 4800.0,
                  "activity": -4100000, "activity_currency": -4100.0, "to_be_budgeted": 200000, "to_be_budgeted_currency": 200.0, "age_of_money": 38, "deleted": false },
                { "month": "2026-11-01", "note": "Holidays", "income": 5200000, "budgeted": 5000000, "activity": -1250000, "to_be_budgeted": 0, "age_of_money": 41, "deleted": false },
                { "month": "2020-01-01", "income": 0, "budgeted": 0, "activity": 0, "to_be_budgeted": 0, "age_of_money": null, "deleted": true }
            ],
            "server_knowledge": 55
        }'
        $script:detailJson = '{
            "month": { "month": "2026-11-01", "note": "Holidays", "income": 5200000, "budgeted": 5000000, "activity": -1250000, "to_be_budgeted": 0, "age_of_money": 41, "deleted": false,
                "categories": [
                    { "id": "c-food", "category_group_name": "Everyday", "name": "Food", "budgeted": 400000, "budgeted_currency": 400.0, "activity": -125500, "balance": 274500, "deleted": false },
                    { "id": "c-fun", "category_group_name": "Everyday", "name": "Fun", "budgeted": 50000, "activity": -80000, "balance": -30000, "deleted": false },
                    { "id": "c-old", "category_group_name": "Everyday", "name": "Old", "budgeted": 0, "activity": 0, "balance": 0, "deleted": true }
                ] }
        }'
    }
    BeforeEach {
        $listResponse = $script:listJson
        $detailResponse = $script:detailJson
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -MockWith {
            $listResponse | ConvertFrom-Json
        }.GetNewClosure()
        Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/months/*' } -MockWith {
            $detailResponse | ConvertFrom-Json
        }.GetNewClosure()
    }
    Context -Name 'listing months' -Fixture {
        It -Name 'sends one request to the last-used plan''s months by default' -Test {
            Get-YnabMonth | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq '/plans/last-used/months' } -Times 1 -Exactly -Scope It
        }
        It -Name 'returns one summary per month, leaving out deleted months' -Test {
            $result = @(Get-YnabMonth)
            $result.month | Should -Be @('2026-10-01', '2026-11-01')
        }
        It -Name 'converts the month amounts and drops their *_currency copies' -Test {
            $october = @(Get-YnabMonth)[0]
            $october.income | Should -Be ([System.Decimal] 5000)
            $october.budgeted | Should -Be ([System.Decimal] 4800)
            $october.activity | Should -Be ([System.Decimal] -4100)
            $october.to_be_budgeted | Should -Be ([System.Decimal] 200)
            $october.income_formatted | Should -Be '$5,000.00'
            $october.PSObject.Properties.Name.Where({ $_ -like '*_currency' }) | Should -BeNullOrEmpty
            $october.age_of_money | Should -Be 38
        }
    }
    Context -Name 'getting one month' -Fixture {
        It -Name 'sends <Month> as <Segment>' -ForEach @(
            @{ Month = 'current'; Segment = 'current' }
            @{ Month = 'Current'; Segment = 'current' }
            @{ Month = '2026-11-15'; Segment = '2026-11-01' }
            @{ Month = '2026-11-01'; Segment = '2026-11-01' }
            @{ Month = '2026-02-28T23:30:00'; Segment = '2026-02-01' }
        ) -Test {
            Get-YnabMonth -Month $Month | Out-Null
            $expectedPath = '/plans/last-used/months/{0}' -f $Segment
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'sends <Month> as <Segment> under the <Culture> culture' -ForEach @(
            @{ Culture = 'en-GB'; Month = '11/12/2026'; Segment = '2026-11-01' }
            @{ Culture = 'en-GB'; Month = '2026-11-15'; Segment = '2026-11-01' }
            @{ Culture = 'th-TH'; Month = '2026-11-15'; Segment = '2026-11-01' }
            @{ Culture = 'th-TH'; Month = '11/12/2026'; Segment = '2026-11-01' }
        ) -Test {
            $originalCulture = [System.Globalization.CultureInfo]::CurrentCulture
            try {
                [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new($Culture)
                Get-YnabMonth -Month $Month | Out-Null
            }
            finally {
                [System.Globalization.CultureInfo]::CurrentCulture = $originalCulture
            }
            $expectedPath = '/plans/last-used/months/{0}' -f $Segment
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $expectedPath } -Times 1 -Exactly -Scope It
        }
        It -Name 'accepts a DateTime value and sends the first of its month' -Test {
            Get-YnabMonth -Month ([System.DateTime]::new(2026, 7, 19)) | Out-Null
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq '/plans/last-used/months/2026-07-01' } -Times 1 -Exactly -Scope It
        }
        It -Name 'returns the month with its categories converted and deleted ones left out' -Test {
            $result = @(Get-YnabMonth -Month current)
            $result | Should -HaveCount 1
            $result[0].income | Should -Be ([System.Decimal] 5200)
            $result[0].categories.name | Should -Be @('Food', 'Fun')
            $result[0].categories[0].budgeted | Should -Be ([System.Decimal] 400)
            $result[0].categories[1].balance | Should -Be ([System.Decimal] -30)
            $result[0].categories[0].PSObject.Properties.Name | Should -Not -Contain 'budgeted_currency'
        }
    }
    Context -Name 'parameter validation' -Fixture {
        It -Name 'rejects <Value> as a month before sending a request' -ForEach @(
            @{ Value = 'November' }
            @{ Value = 'last-month' }
            @{ Value = '2026-13-01' }
        ) -Test {
            $err = $null
            try {
                Get-YnabMonth -Month $Value
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            $err.ToString() | Should -BeLike ('*Month `[{0}`] must be current or a date*' -f $Value)
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
        It -Name 'rejects a malformed plan ID before sending a request' -Test {
            $err = $null
            try {
                Get-YnabMonth -PlanId 'Household'
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'ParameterArgumentValidationError*'
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -Times 0 -Exactly -Scope It
        }
    }
    Context -Name 'pipeline input' -Fixture {
        It -Name 'lists the months of each piped plan, one request each' -Test {
            @(
                [PSCustomObject] @{ id = $script:planOne; plan_id = $script:planOne }
                [PSCustomObject] @{ id = $script:planTwo; plan_id = $script:planTwo }
            ) | Get-YnabMonth | Out-Null
            $firstPath = '/plans/{0}/months' -f $script:planOne
            $secondPath = '/plans/{0}/months' -f $script:planTwo
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $firstPath } -Times 1 -Exactly -Scope It
            Should -Invoke -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -eq $secondPath } -Times 1 -Exactly -Scope It
        }
    }
    Context -Name 'error handling' -Fixture {
        It -Name 'lets the request error surface unchanged' -Test {
            Mock -CommandName Invoke-YnabRequest -ModuleName $env:BHProjectName -ParameterFilter { $Path -like '*/months/*' } -MockWith {
                Write-Error -Message 'YNAB API error 404 resource_not_found (404.2): Resource not found' -ErrorId 'YnabApi.resource_not_found' -ErrorAction Stop
            }
            $err = $null
            try {
                Get-YnabMonth -Month '1999-01-01'
            }
            catch {
                $err = $PSItem
            }
            $err.FullyQualifiedErrorId | Should -BeLike 'YnabApi.resource_not_found*'
        }
    }
}
