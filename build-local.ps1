<#
.SYNOPSIS
    Builds Flutter Customer Web, generates SEO pages, merges into deploy-test/,
    and optionally starts a local server with correct SPA fallback routing.

.DESCRIPTION
    Combines the Flutter SPA and static SEO pages into a single deploy-test/
    directory that mirrors the production routing contract:
      /s/**        → static SEO HTML (served directly from file)
      /catalog/**  → Flutter index.html (SPA fallback)
      /**          → Flutter index.html (SPA fallback)

    PRODUCTION_DOMAIN must be set in scripts/generate-seo-pages/.env.
    For local testing use: PRODUCTION_DOMAIN=http://localhost:3000

.PARAMETER SkipFlutterBuild
    Skip the Flutter web build step and reuse customer_app/build/web/.
    Use this when the Flutter code has not changed since the last build.

.PARAMETER SkipSeoGenerate
    Skip the SEO generation step and reuse scripts/generate-seo-pages/dist/.
    Use this when catalog SEO data has not changed.

.PARAMETER NoServe
    Merge only — do not start the local dev server after merging.

.EXAMPLE
    # Full build + serve
    .\build-local.ps1

    # Reuse existing Flutter build, regenerate SEO, merge, and serve
    .\build-local.ps1 -SkipFlutterBuild

    # Reuse all cached outputs, just re-merge and serve (fastest)
    .\build-local.ps1 -SkipFlutterBuild -SkipSeoGenerate

    # Merge only, no server (for CI or manual inspection)
    .\build-local.ps1 -SkipFlutterBuild -SkipSeoGenerate -NoServe
#>
param(
    [switch]$SkipFlutterBuild,
    [switch]$SkipSeoGenerate,
    [switch]$NoServe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'  # we check $LASTEXITCODE manually for native tools

$Root = $PSScriptRoot

function Write-Step([string]$text) {
    Write-Host "`n$text" -ForegroundColor Cyan
}
function Write-Ok([string]$text)   { Write-Host "  [ok] $text" -ForegroundColor Green }
function Write-Skip([string]$text) { Write-Host "  [-]  $text" -ForegroundColor DarkGray }
function Write-Fail([string]$text) {
    Write-Host "`n  [FAIL] $text" -ForegroundColor Red
    exit 1
}

Write-Host "`nDODO Booker - Local Build + Test" -ForegroundColor White
Write-Host "  Domain  : http://localhost:3000  (local test only, NOT production)"
Write-Host "  Output  : $Root\deploy-test\"

# ── 1. Flutter build ───────────────────────────────────────────────────────────
if ($SkipFlutterBuild) {
    Write-Skip "[1/3] Flutter build skipped (-SkipFlutterBuild)"
} else {
    Write-Step "[1/3] Building Flutter Customer Web (flutter build web)..."
    Push-Location (Join-Path $Root "customer_app")
    try {
        flutter build web --base-href /
        if ($LASTEXITCODE -ne 0) { Write-Fail "flutter build web failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    Write-Ok "Flutter build complete → customer_app/build/web/"
}

# ── 2. SEO generation ─────────────────────────────────────────────────────────
if ($SkipSeoGenerate) {
    Write-Skip "[2/3] SEO generation skipped (-SkipSeoGenerate)"
} else {
    Write-Step "[2/3] Generating SEO pages (node index.js)..."

    $envFile = Join-Path $Root "scripts\generate-seo-pages\.env"
    if (-not (Test-Path $envFile)) {
        Write-Fail ".env not found at $envFile`n  Copy .env.example to .env and set PRODUCTION_DOMAIN=http://localhost:3000"
    }

    Push-Location (Join-Path $Root "scripts\generate-seo-pages")
    try {
        node index.js
        if ($LASTEXITCODE -ne 0) { Write-Fail "SEO generation failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    Write-Ok "SEO generation complete → scripts/generate-seo-pages/dist/"
}

# ── 3. Merge ──────────────────────────────────────────────────────────────────
Write-Step "[3/3] Merging Flutter + SEO → deploy-test/..."
node (Join-Path $Root "scripts\merge.mjs")
if ($LASTEXITCODE -ne 0) { Write-Fail "Merge failed (exit $LASTEXITCODE)" }
Write-Ok "Merge complete."

# ── 4. Serve ──────────────────────────────────────────────────────────────────
if ($NoServe) {
    Write-Host "`n  [-NoServe] Skipping local server." -ForegroundColor DarkGray
    Write-Host "  To test: npx serve deploy-test --single --listen 3000"
    exit 0
}

node (Join-Path $Root "scripts\test-server.mjs")
