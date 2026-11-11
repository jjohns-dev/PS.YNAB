# Foundation: tasks

Implements [design.md](design.md). Work in order; each task leaves the module importable and the existing tests passing. Check a box only after its verification has run and passed.

## 1. Milliunit helpers

- [x] **1.1** Add `Private/ConvertFrom-Milliunit.ps1` and `Tests/Unit/ConvertFrom-Milliunit.tests.ps1`. The tests cover positive, negative and zero values, pipeline input, and `System.Decimal` output (AC-19, AC-22).
  - Verify: `Invoke-Pester -Path Tests/Unit/ConvertFrom-Milliunit.tests.ps1` passes.
- [x] **1.2** Add `Private/ConvertTo-Milliunit.ps1` and `Tests/Unit/ConvertTo-Milliunit.tests.ps1`. The tests cover whole and fractional amounts, negatives, pipeline input, `System.Int64` output, the `YnabAmountPrecision` error for `1.2345`, and round trips through both helpers (AC-20, AC-21, AC-22, AC-23).
  - Verify: `Invoke-Pester -Path Tests/Unit/ConvertTo-Milliunit.tests.ps1` passes.

## 2. Request layer

- [x] **2.1** Initialize `$script:YnabToken = $null` in `PS.YNAB.psm1`.
  - Verify: `Invoke-Pester -Path Tests/Unit/Module.tests.ps1` still passes.
- [x] **2.2** Add `Private/Invoke-YnabRequest.ps1` and `Tests/Unit/Invoke-YnabRequest.tests.ps1`. The tests cover:
  - the fixed base URI, plus the `-Path` validation pattern (AC-8)
  - `-Authentication Bearer` and `-Token`, with no `Headers` parameter passed (AC-9)
  - `YnabNotConnected` with zero `Invoke-RestMethod` calls (AC-10)
  - `.data` emitted on success (AC-11)
  - a JSON body with `application/json` (AC-12)
  - the YNAB error message, ID and category for 400, 403, 404 and 500 (AC-13)
  - the 401 reconnect hint (AC-14)
  - the 429 schedule: retries of 15, 30 and 60 seconds and 4 calls before the final error, plus a 429 that succeeds on a retry (AC-15)
  - a non-YNAB error body (AC-16)
  - a non-HTTP failure passing through unchanged
  - no sentinel token in error records, verbose or debug output (AC-17)
  - Verify: `Invoke-Pester -Path Tests/Unit/Invoke-YnabRequest.tests.ps1` passes.

## 3. Session commands

These go in one change because the module test requires the exports to match `Public/` exactly, and the harness requires `Public/` to be non-empty.

- [x] **3.1** Add `Public/Connect-Ynab.ps1` and `Public/Disconnect-Ynab.ps1`, delete `Public/README.md`, and set `FunctionsToExport = @('Connect-Ynab', 'Disconnect-Ynab')` in `PS.YNAB.psd1` (AC-24).
  - Verify: `Invoke-Pester -Path Tests/Unit/Module.tests.ps1` passes, including "exports exactly the functions backed by a Public/ file".
- [x] **3.2** Add `Tests/Unit/Connect-Ynab.tests.ps1`. The tests cover:
  - one `GET /user`, then later requests carry the token, with no success output (AC-1)
  - a failed check raises the error, and later requests still carry the previous token (AC-2)
  - a plain string is refused at binding (AC-3)
  - a successful reconnect replaces the token (AC-4)
  - no sentinel token in any stream (AC-5)
  - the caller's `SecureString` stays usable after `Disconnect-Ynab`
  - Verify: `Invoke-Pester -Path Tests/Unit/Connect-Ynab.tests.ps1` passes.
- [x] **3.3** Add `Tests/Unit/Disconnect-Ynab.tests.ps1`. The tests cover: after disconnecting, requests fail with `YnabNotConnected` (AC-6), and disconnecting with no session doesn't error (AC-7).
  - Verify: `Invoke-Pester -Path Tests/Unit/Disconnect-Ynab.tests.ps1` passes.

## 4. Documentation

- [x] **4.1** Update `README.md`:
  - replace the "scaffold only" status line
  - replace the "Functions" section with a pointer to `FunctionsToExport` in `PS.YNAB.psd1` and to `Get-Command -Module PS.YNAB`, so the export list lives only in the manifest
  - add a "Connecting" section: get the token from a vault or with `Read-Host -AsSecureString`, never assign it as a plain string, and set `$PSDefaultParameterValues['*-Ynab*:PlanId']`
  - Verify: read the rendered Markdown; it lists no function names outside the "Connecting" examples, and every command shown exists in the module.

## 5. Checks before the PR

- [x] **5.1** Confirm `Invoke-YnabRequest` is the only caller of `Invoke-RestMethod` (AC-18).
  - Verify: searching `Public/` and `Private/` for `Invoke-RestMethod` finds it only in `Private/Invoke-YnabRequest.ps1`.
- [x] **5.2** Run the full local build, the same tasks CI runs (AC-25, AC-26).
  - Verify: `./Build/build.ps1 -ResolveDependency -TaskList Init`, then `./Build/build.ps1 -TaskList CombineFunctionsAndStage, Analyze, Test`, both succeed with no analyzer findings; then `./Build/build.ps1 -TaskList Cleanup`.
- [x] **5.3** Walk the PowerShell skill's pre-commit checklist over every new and changed `.ps1` file.
  - Verify: each checklist item is confirmed or fixed.
- [x] **5.4** Run a live check with a deliberately invalid token: `Connect-Ynab -Token <bad> -Verbose -Debug`.
  - Verify: a 401 error with the reconnect hint, and the token text appears nowhere in the console output (design risk 1).
  - Result: found the token in `Invoke-RestMethod`'s debug output; fixed with `-Debug:$false` and re-verified live. See design risk 1 for the unit-test gap.
- [x] **5.5** Check by hand that the prompt is masked: run `Connect-Ynab` with no arguments in an interactive shell.
  - Verify: typed characters are masked, which resolves the unverified claim in the design. **You run this**, because it needs an interactive console.
  - Result: PowerShell prompted `Token:` and showed the input as `*` characters.
- [x] **5.6** Run a live smoke test with your real token: `Connect-Ynab -Token (Get-Secret YnabToken)`, then `Disconnect-Ynab`.
  - Verify: connecting succeeds with no output; disconnecting succeeds. **You run this**, so I never read your secret.
  - Result: both commands completed with no output.

## 6. Ship

- [ ] **6.1** Commit with a `refs #4` body, push `4-foundation`, and open a PR that closes #4.
  - Verify: all checks pass, including the required `validate / validate (ubuntu-latest)`.
- [ ] **6.2** After merge, tick step 1 in issue #1's plan.
  - Verify: issue #1 shows step 1 checked with links to #4 and the PR.
