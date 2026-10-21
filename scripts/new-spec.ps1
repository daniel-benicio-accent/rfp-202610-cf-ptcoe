<#
.SYNOPSIS
    Scaffold a new specification folder from the templates in specs/_templates.

.DESCRIPTION
    Allocates the next sequential spec number, creates specs/NNNN-slug/ and
    fills spec.md, plan.md and tasks.md with the title and today's date.

.EXAMPLE
    ./scripts/new-spec.ps1 -Title "Customer onboarding demo flow"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Title
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Split-Path -Parent $PSScriptRoot
$specsDir  = Join-Path $repoRoot 'specs'
$templates = Join-Path $specsDir '_templates'

if (-not (Test-Path $templates)) {
    throw "Templates not found at $templates"
}

# Next sequential id, never reusing a number.
$used = @()
foreach ($dir in (Get-ChildItem -Path $specsDir -Directory)) {
    if ($dir.Name -match '^(\d{4})-') { $used += [int]$Matches[1] }
}
$next = if ($used.Count -gt 0) { [int](($used | Measure-Object -Maximum).Maximum) + 1 } else { 1 }
$id = '{0:d4}' -f $next

$slug = $Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '^-+|-+$', ''
if ([string]::IsNullOrWhiteSpace($slug)) {
    throw 'Title must contain at least one letter or digit.'
}

$target = Join-Path $specsDir "$id-$slug"
if (Test-Path $target) { throw "$target already exists." }
New-Item -ItemType Directory -Path $target | Out-Null

$today = Get-Date -Format 'yyyy-MM-dd'

# Windows PowerShell 5.1 reads BOM-less files as ANSI and writes UTF-8 with a
# BOM, which mangles non-ASCII characters. Force UTF-8 both ways, no BOM.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($name in @('spec', 'plan', 'tasks')) {
    $text = Get-Content -Path (Join-Path $templates "$name.md") -Raw -Encoding UTF8
    $text = $text.Replace('{{ID}}', $id).Replace('{{TITLE}}', $Title).Replace('{{DATE}}', $today)
    [System.IO.File]::WriteAllText((Join-Path $target "$name.md"), $text, $utf8NoBom)
}

Write-Host "Created specs/$id-$slug/"
Write-Host ''
Write-Host 'Next steps:'
Write-Host "  1. Fill in specs/$id-$slug/spec.md (what and why, no implementation detail)."
Write-Host '  2. Add a row to specs/README.md.'
Write-Host '  3. Get it reviewed, then set Status: Approved before writing plan.md.'
