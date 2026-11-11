# ==============================================================================
# Filename: PS.YNAB.psm1
# Author:   Justin Johns
# ==============================================================================

# SET DIRECTORIES
$dirs = @(
    (Join-Path -Path $PSScriptRoot -ChildPath 'Public')
    (Join-Path -Path $PSScriptRoot -ChildPath 'Private')
)

# DOT SOURCE ALL PS SCRIPTS
foreach ($file in (Get-ChildItem -Path $dirs -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
    . $file.FullName
}

# EXPORT MEMBERS
# FunctionsToExport in the manifest is the authoritative export list.
