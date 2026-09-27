#Requires -Version 5.1
<#
.SYNOPSIS
    Link the CodexBarUsage skin into Rainmeter and load it.

.DESCRIPTION
    Creates a directory junction Documents\Rainmeter\Skins\CodexBarUsage -> this repo's
    extras\rainmeter\CodexBarUsage, so `git pull` updates the skin in place.
    The skin reads the desktop app's status pipe: turn on
    Settings > Advanced > "PowerToys status pipe" in CodexBar and restart the app.

.PARAMETER Uninstall
    Unload the skin and remove the junction (the repo files are left untouched).
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$SkinSource = Join-Path $PSScriptRoot 'CodexBarUsage'
$SkinsDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins'
$SkinLink = Join-Path $SkinsDir 'CodexBarUsage'
$Rainmeter = Join-Path $env:ProgramFiles 'Rainmeter\Rainmeter.exe'

if (-not (Test-Path $Rainmeter)) { throw "Rainmeter not found at $Rainmeter" }

if ($Uninstall) {
    & $Rainmeter '!DeactivateConfig' 'CodexBarUsage'
    if (Test-Path $SkinLink) { (Get-Item $SkinLink).Delete() }   # removes the junction only
    Write-Host 'CodexBarUsage skin uninstalled.'
    exit 0
}

if (Test-Path $SkinLink) {
    if ((Get-Item $SkinLink).LinkType -ne 'Junction') {
        throw "$SkinLink exists and is not a junction; move it away first."
    }
} else {
    New-Item -ItemType Junction -Path $SkinLink -Target $SkinSource | Out-Null
}

& $Rainmeter '!RefreshApp'
Start-Sleep -Seconds 2
& $Rainmeter '!ActivateConfig' 'CodexBarUsage' 'CodexBarUsage.ini'
Write-Host "CodexBarUsage skin installed ($SkinLink -> $SkinSource)."
