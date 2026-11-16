BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'ConvertTo-YnabQueryString' -Fixture {
    It -Name 'returns <Case>' -ForEach @(
        @{ Case = 'pairs in sorted key order'; Query = @{ until_date = '2026-11-30'; since_date = '2026-11-01'; type = 'unapproved' }; Expected = 'since_date=2026-11-01&type=unapproved&until_date=2026-11-30' }
        @{ Case = 'URI-escaped keys and values'; Query = @{ 'a b' = 'x&y=z/?' }; Expected = 'a%20b=x%26y%3Dz%2F%3F' }
        @{ Case = 'only entries whose value is not null'; Query = @{ since_date = '2026-11-01'; type = $null }; Expected = 'since_date=2026-11-01' }
        @{ Case = 'numbers as text'; Query = @{ last_knowledge_of_server = 4321 }; Expected = 'last_knowledge_of_server=4321' }
        @{ Case = 'an empty string when every value is null'; Query = @{ type = $null }; Expected = '' }
        @{ Case = 'an empty string for an empty query'; Query = @{}; Expected = '' }
    ) -Test {
        InModuleScope -ModuleName $env:BHProjectName -Parameters @{ Q = $Query } -ScriptBlock {
            ConvertTo-YnabQueryString -Query $Q
        } | Should -BeExactly $Expected
    }
    It -Name 'returns an empty string for a null query' -Test {
        InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
            ConvertTo-YnabQueryString -Query $null
        } | Should -BeExactly ''
    }
}
