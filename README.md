# PS.YNAB

A PowerShell module wrapping the [YNAB API](https://api.ynab.com). Its first consumer is a daily spending-anomaly alerter.

> **Status:** early development. Functions land one PR at a time, following the plan in [#1](https://github.com/jjohns-dev/PS.YNAB/issues/1).

## Requirements

- PowerShell 7.4+
- A YNAB personal access token or OAuth application, from [Developer Settings](https://app.ynab.com/settings/developer).

## Install

`PS.YNAB` is not published to the PowerShell Gallery. Install from a clone:

```powershell
git clone https://github.com/jjohns-dev/PS.YNAB.git
Import-Module ./PS.YNAB/PS.YNAB.psd1
```

## Functions

The exported functions are listed in `FunctionsToExport` in [PS.YNAB.psd1](PS.YNAB.psd1). Once the module is imported, list them with `Get-Command -Module PS.YNAB` and read each one's help with `Get-Help <name> -Full`.

## Connecting

Start each session with your personal access token. The module never stores the token; you supply it as a `SecureString` from wherever you keep it:

```powershell
# FROM A SECRETMANAGEMENT VAULT
Connect-Ynab -Token (Get-Secret -Name YnabToken)

# OR TYPED AT A PROMPT
Connect-Ynab -Token (Read-Host -Prompt 'YNAB token' -AsSecureString)
```

Never assign the token to a variable as a plain string (`$token = '...'`): PSReadLine saves that line to its history file. `Disconnect-Ynab` clears the token from the session.

Commands that take a `-PlanId` default to `last-used`. To work with a specific plan, set a default in your profile:

```powershell
$PSDefaultParameterValues['*-Ynab*:PlanId'] = '<plan-id>'
```

A misspelled key is ignored silently, so check it with `$PSDefaultParameterValues` if commands return data from the wrong plan.

## Development

The build runs from the shared harness in [`pwsh-module-ci`](https://github.com/jjohns-dev/pwsh-module-ci); see [CONTRIBUTING.md](CONTRIBUTING.md#running-the-build-locally).

## License

[MIT](LICENSE)
