# ==============================================================================
# Filename: PS.YNAB.psm1
# Author:   Justin Johns
# ==============================================================================

# SET DIRECTORIES
$dirs = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'Public')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Private')
)

# SESSION TOKEN, SET BY Connect-Ynab AND CLEARED BY Disconnect-Ynab
$script:YnabToken = $null

# AMOUNT FIELDS IN MILLIUNITS, CONVERTED TO DECIMAL BY ConvertFrom-YnabData (ADR-0004).
# EVERY INT64 AMOUNT IN YNAB'S OPENAPI SPEC; ADD NEW ONES HERE WHEN YNAB INTRODUCES THEM
New-Variable -Name 'ynab_amount_fields' -Option Constant -Value @(
    'activity'
    'amount'
    'balance'
    'budgeted'
    'cleared_balance'
    'debt_original_balance'
    'goal_overall_funded'
    'goal_overall_left'
    'goal_target'
    'goal_under_funded'
    'income'
    'to_be_budgeted'
    'uncleared_balance'
)

# ACCOUNT LOAN FIELDS WHOSE VALUES ARE MAPS OF DATE TO MILLIUNITS; EVERY VALUE IS CONVERTED
New-Variable -Name 'ynab_amount_map_fields' -Option Constant -Value @(
    'debt_escrow_amounts'
    'debt_interest_rates'
    'debt_minimum_payments'
)

# DOT SOURCE ALL PS SCRIPTS
foreach ($file in (Get-ChildItem -Path $dirs -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
    . $file.FullName
}

# EXPORT MEMBERS
# FunctionsToExport in the manifest is the authoritative export list.
