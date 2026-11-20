# ==============================================================================
# Filename: Try-YnabOauth.ps1
# Version:  0.1.0 | Updated: 2026-11-19
# Author:   Justin Johns
# ==============================================================================

#Requires -Modules @{ ModuleName = 'PS.YNAB'; ModuleVersion = '0.3.0' }

<# =============================================================================
.DESCRIPTION
    Connects to YNAB with a read-only OAuth authorization, runs a few read-only queries against the last-used
    plan, then disconnects. It resumes from a refresh token saved in your SecretManagement vault, or authorizes
    in the browser when there is none, and saves each new refresh token as YNAB issues it. The companion to
    Try-YnabToken.ps1.

    Needs the OAuth application's client ID and secret in your vault as YnabOAuthClientId and
    YnabOAuthClientSecret; the refresh token is saved as YnabRefreshToken.
.NOTES
    Version History: (see commit history)
    General Notes:
    What to expect:
    - First run: with no saved refresh token, it says it couldn't resume and opens the browser. After you approve, it prints "Saved a new refresh token...", runs the queries, then disconnects.
    - Later runs: it resumes with no browser and prints "Saved..." again. Resuming uses up the saved refresh token, and YNAB issues a replacement.
    - Vault password: if your SecretStore is locked, Get-Secret and Set-Secret may ask for its password.


    What's going on:
    - Two tokens: each connect gets a short-lived access token (2 hours) that the queries use, and a refresh token that gets new tokens without a browser.
    - Single use: YNAB invalidates each refresh token once it's been used. So the module hands every new one to $save before doing anything else. If a save is ever lost, the next run just falls back to the browser.
    - Automatic refresh: you never call it. The module refreshes before a request when the access token has less than a minute left, or once after a 401. A short run like this one won't see that; a long session or a scheduled job would.
    - Disconnecting doesn't revoke anything: the saved refresh token keeps working. To shut access off completely, remove the app under Authorized Applications in YNAB's Developer Settings.
    - One process at a time: don't run this in two windows at once. A refresh in one window invalidates the other's tokens.
============================================================================= #>

# 1. THE APP'S CREDENTIALS, FROM YOUR VAULT. THE CLIENT ID ISN'T SECRET; THE CLIENT SECRET IS
$app = @{
    ClientId     = Get-Secret -Name YnabOAuthClientId -AsPlainText
    ClientSecret = Get-Secret -Name YnabOAuthClientSecret
}

# 2. WHERE NEW REFRESH TOKENS GO. YNAB ISSUES A NEW ONE ON EVERY REFRESH AND REVOKES THE OLD ONE AT ONCE,
#    SO THE MODULE CALLS THIS BEFORE IT SENDS ANYTHING ELSE, EACH TIME A NEW ONE ARRIVES. THE MODULE DISCARDS
#    ITS OUTPUT, SO THE MESSAGE GOES TO THE INFORMATION STREAM
$save = {
    param ($Refresh)
    Set-Secret -Name YnabRefreshToken -Secret $Refresh.RefreshToken
    $informationParams = @{
        MessageData       = 'Saved a new refresh token; this access token expires at {0:u}.' -f $Refresh.AccessTokenExpiresAt
        InformationAction = 'Continue'
    }
    Write-Information @informationParams
}

# 3. CONNECT: RESUME FROM THE SAVED REFRESH TOKEN WITHOUT A BROWSER, OR AUTHORIZE IN THE BROWSER IF THERE IS
#    NONE OR IT NO LONGER WORKS. EITHER WAY YOU GET A 2-HOUR ACCESS TOKEN AND A NEW REFRESH TOKEN
$connected = $false
try {
    $savedToken = Get-Secret -Name YnabRefreshToken -ErrorAction Stop
    Connect-Ynab @app -RefreshToken $savedToken -OnTokenRefresh $save -ErrorAction Stop
    $connected = $true
    Write-Output 'Resumed from the saved refresh token (no browser needed).'
}
catch {
    Write-Output ('Could not resume ({0}); authorizing in the browser.' -f $PSItem.FullyQualifiedErrorId)
}
if (-not $connected) {
    Connect-Ynab @app -OnTokenRefresh $save -ErrorAction Stop
    Write-Output 'Authorized in the browser.'
}

# 4. QUERIES: THE SAME COMMANDS AS WITH A PERSONAL TOKEN. THEY USE YOUR LAST-USED PLAN; IF THE ACCESS TOKEN IS
#    ABOUT TO EXPIRE, THE MODULE REFRESHES IT FIRST AND CALLS $save AGAIN
Get-YnabPlanList | Select-Object -Property name, last_modified_on | Format-Table

Get-YnabAccount | Where-Object -FilterScript { -not $PSItem.closed } |
Select-Object -Property name, type, balance | Format-Table

Get-YnabMonth -Month current | Select-Object -Property month, income, budgeted, activity, to_be_budgeted | Format-List

Get-YnabTransaction -SinceDate (Get-Date).AddDays(-7) |
Select-Object -Property date, payee_name, category_name, amount | Format-Table

# 5. DISCONNECT: CLEARS THE TOKENS AND CACHE FROM MEMORY. THE SAVED REFRESH TOKEN STAYS VALID FOR THE NEXT RUN
Disconnect-Ynab
Write-Output 'Disconnected.'
