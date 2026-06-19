#!/usr/bin/env pwsh
# scripts/bootstrap/adopt-agent-of-empires-config.ps1
#
# PowerShell wrapper for adopt-agent-of-empires-config.mjs. Keeps script parity
# with adopt-agent-of-empires-config.sh while the adopt logic runs through
# mise-managed Bun (matching the other bootstrap helpers, e.g.
# configure-codex-config.ps1).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

$ScriptDir = Split-Path -Parent $PSCommandPath
$MiseBin = if ($env:MISE_INSTALL_PATH) { $env:MISE_INSTALL_PATH } else { Join-Path $HOME '.local\bin\mise.exe' }

if (Test-CommandExists 'mise') {
    $MiseBin = 'mise'
} elseif (-not (Test-Path $MiseBin)) {
    Write-Error "adopt-agent-of-empires-config.ps1: mise not found. Install mise yourself and re-run. Expected mise on PATH or at '$MiseBin'."
    exit 1
}

& $MiseBin exec bun@latest -- bun (Join-Path $ScriptDir 'adopt-agent-of-empires-config.mjs') @args
exit $LASTEXITCODE
