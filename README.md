# PS.YNAB

A PowerShell module wrapping the [YNAB API](https://api.ynab.com). Its first consumer is a daily spending-anomaly alerter.

> **Status:** scaffold only. No functions are exported yet; they land one PR at a time, tracked in [the issues](https://github.com/jjohns-dev/PS.YNAB/issues).

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

None yet.

## Development

The build runs from the shared harness in [`pwsh-module-ci`](https://github.com/jjohns-dev/pwsh-module-ci); see [CONTRIBUTING.md](CONTRIBUTING.md#running-the-build-locally).

## License

[MIT](LICENSE)
