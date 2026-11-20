# ==============================================================================
# Filename: Try-YnabToken.ps1
# Version:  0.1.0 | Updated: 2026-11-20
# Author:   Justin Johns
# ==============================================================================

#Requires -Modules @{ ModuleName = 'PS.YNAB'; ModuleVersion = '0.3.0' }

<# =============================================================================
.DESCRIPTION
    Connects to YNAB with a personal access token, runs a few read-only queries against one plan, then
    disconnects. The companion to Try-YnabOauth.ps1, for interactive use.
.NOTES
    Version History: (see commit history)
    General Notes:
    What to expect:
    - The token comes from your SecretManagement vault as YnabToken; change the name in step 1 if yours differs.
      If your SecretStore is locked, Get-Secret asks for its password.
    - Connecting sends one request (GET /user) to check the token. Each query after that is one request, against
      the API's limit of 200 requests per hour per token.

    What's going on:
    - One token, no refresh: a personal access token never expires and has full read and write access. Nothing
      is handed back to save, so there is no -OnTokenRefresh here.
    - Plan ID and the cache: commands default to your last-used plan. Passing a real plan ID, as step 2 does,
      lets list results be cached for the session; repeat calls then download only changes. Transactions are
      never cached.
    - Disconnecting clears the token and cache from memory only. The token itself keeps working until you revoke
      it under Developer Settings in YNAB.
============================================================================= #>

# 1. CONNECT WITH THE PERSONAL ACCESS TOKEN FROM YOUR VAULT. IT STAYS A SECURESTRING THE WHOLE WAY
Connect-Ynab -Token (Get-Secret -Name YnabToken) -ErrorAction Stop
Write-Output 'Connected with a personal access token.'

# 2. PICK A PLAN: THE MOST RECENTLY MODIFIED ONE. ITS ID IS PASSED BELOW SO LIST RESULTS ARE CACHED
$plan = Get-YnabPlanList | Sort-Object -Property last_modified_on -Descending | Select-Object -First 1
$planId = $plan.id
Write-Output ('Using plan: {0}' -f $plan.name)

# 3. QUERIES
Get-YnabAccount -PlanId $planId | Where-Object -FilterScript { -not $PSItem.closed } |
    Select-Object -Property name, type, balance | Format-Table

Get-YnabMonth -PlanId $planId -Month current |
    Select-Object -Property month, income, budgeted, activity, to_be_budgeted | Format-List

# OVERSPENT CATEGORIES THIS MONTH: VISIBLE, USER-CREATED CATEGORIES WITH A NEGATIVE BALANCE
Get-YnabCategory -PlanId $planId |
    Where-Object -FilterScript { -not $PSItem.hidden -and -not $PSItem.internal -and $PSItem.balance -lt 0 } |
    Select-Object -Property category_group_name, name, balance | Format-Table

# TRANSACTIONS WAITING FOR APPROVAL
Get-YnabTransaction -PlanId $planId -Type Unapproved |
    Select-Object -Property date, account_name, payee_name, amount | Format-Table

# 4. DISCONNECT: CLEARS THE TOKEN AND CACHE FROM MEMORY; THE TOKEN ITSELF STAYS VALID
Disconnect-Ynab
Write-Output 'Disconnected.'
