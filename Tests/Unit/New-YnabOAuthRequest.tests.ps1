BeforeDiscovery {
    if (-not $env:BHProjectName) {
        $env:BHProjectName = 'PS.YNAB'
        $env:BHPSModuleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..', '..', 'PS.YNAB.psd1'
    }
    if (-not (Get-Module -Name $env:BHProjectName)) {
        Import-Module -Name $env:BHPSModuleManifest -ErrorAction Stop -Force
    }
}

Describe -Name 'New-YnabOAuthRequest' -Fixture {
    BeforeAll {
        $script:newRequest = {
            InModuleScope -ModuleName $env:BHProjectName -ScriptBlock {
                New-YnabOAuthRequest -ClientId 'client id/1' -RedirectUri 'http://localhost:8765/callback'
            }
        }
        $script:request = & $script:newRequest

        # PARSES THE AUTHORIZE URL'S QUERY INTO A HASHTABLE OF UNESCAPED VALUES
        $script:queryOf = {
            param ($Uri)
            $values = @{}
            foreach ($pair in ([System.Uri] $Uri).Query.TrimStart('?').Split('&')) {
                $key, $value = $pair.Split('=', 2)
                $values[[System.Uri]::UnescapeDataString($key)] = [System.Uri]::UnescapeDataString($value)
            }
            $values
        }
    }
    Context -Name 'PKCE' -Fixture {
        It -Name 'creates a 43-character base64url code verifier' -Test {
            $script:request.CodeVerifier | Should -MatchExactly '^[A-Za-z0-9_-]{43}$'
        }
        It -Name 'creates the S256 challenge of the verifier' -Test {
            # INDEPENDENT SHA-256: Get-FileHash OVER A STREAM, HEX TO BYTES, THEN BASE64URL
            $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::ASCII.GetBytes($script:request.CodeVerifier))
            try {
                $hex = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
            }
            finally {
                $stream.Dispose()
            }
            $bytes = [System.Convert]::FromHexString($hex)
            $expected = [System.Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            $script:request.CodeChallenge | Should -BeExactly $expected
        }
        It -Name 'creates a new verifier and state each time' -Test {
            $second = & $script:newRequest
            $second.CodeVerifier | Should -Not -Be $script:request.CodeVerifier
            $second.State | Should -Not -Be $script:request.State
        }
        It -Name 'creates a 22-character base64url state' -Test {
            $script:request.State | Should -MatchExactly '^[A-Za-z0-9_-]{22}$'
        }
    }
    Context -Name 'authorize URL' -Fixture {
        It -Name 'points at YNAB''s authorize page' -Test {
            $script:request.AuthorizeUri | Should -BeLike 'https://app.ynab.com/oauth/authorize?*'
        }
        It -Name 'carries <Name>' -ForEach @(
            @{ Name = 'response_type=code'; Key = 'response_type'; Expected = 'code' }
            @{ Name = 'scope=read-only'; Key = 'scope'; Expected = 'read-only' }
            @{ Name = 'code_challenge_method=S256'; Key = 'code_challenge_method'; Expected = 'S256' }
            @{ Name = 'the client ID'; Key = 'client_id'; Expected = 'client id/1' }
            @{ Name = 'the redirect URI'; Key = 'redirect_uri'; Expected = 'http://localhost:8765/callback' }
        ) -Test {
            (& $script:queryOf $script:request.AuthorizeUri)[$Key] | Should -BeExactly $Expected
        }
        It -Name 'carries the state and the challenge' -Test {
            $query = & $script:queryOf $script:request.AuthorizeUri
            $query['state'] | Should -BeExactly $script:request.State
            $query['code_challenge'] | Should -BeExactly $script:request.CodeChallenge
        }
        It -Name 'escapes the redirect URI' -Test {
            $script:request.AuthorizeUri | Should -BeLike '*redirect_uri=http%3A%2F%2Flocalhost%3A8765%2Fcallback*'
        }
        It -Name 'never carries the verifier' -Test {
            $script:request.AuthorizeUri | Should -Not -BeLike ('*{0}*' -f $script:request.CodeVerifier)
        }
    }
}
