#!/usr/bin/env pwsh
# scripts/bootstrap/patch-glab-skill.ps1
#
# PowerShell counterpart to patch-glab-skill.sh. Re-patches the CLI-managed
# `glab` skill after `glab skills install` (the install.conf.yaml shell step)
# overwrites it with upstream content.
#
# Upstream writes scratch files under the shared /tmp. This repo DENIES /tmp for
# agent tools (see agents/SHARED_AGENTS.md "Temporary / scratch files" and the
# opencode.json permission blocks), so every `/tmp/<file>` path in the skill is
# rewritten to the per-user temp dir `${XDG_RUNTIME_DIR:-$HOME/.cache}/<file>`
# (the exact fallback the rule prescribes; safe when $XDG_RUNTIME_DIR is unset).
# The literal shell expression is written into the markdown verbatim so the
# agent copy-pastes a working, /tmp-free command. Idempotent and byte-identical
# to the sed output of patch-glab-skill.sh.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$GlabSkillDir = Join-Path $ScriptDir '..\..\agents\skills\glab'

if (-not (Test-Path -LiteralPath $GlabSkillDir -PathType Container)) {
    Write-Host "patch-glab-skill.ps1: glab skill dir not found at $GlabSkillDir; nothing to patch."
    exit 0
}

$patched = 0
$files = @(Get-ChildItem -LiteralPath $GlabSkillDir -Filter '*.md' -File -Recurse)

foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    # Literal /tmp/ -> per-user temp dir. String.Replace is ordinal and the
    # single-quoted replacement keeps $ literal, so the shell expression lands in
    # the file verbatim (not expanded) — matching the sed program in the .sh.
    $replaced = $content.Replace('/tmp/', '${XDG_RUNTIME_DIR:-$HOME/.cache}/')
    if ($replaced -ne $content) {
        # UTF-8 without BOM, LF preserved — byte-identical to the sed output.
        [System.IO.File]::WriteAllText($file.FullName, $replaced, [System.Text.UTF8Encoding]::new($false))
        $patched++
        Write-Host "patch-glab-skill.ps1: patched $($file.FullName)"
    }
}

if ($patched -eq 0) {
    Write-Host 'patch-glab-skill.ps1: glab skill already free of /tmp scratch paths; no changes.'
}

exit 0
