<#
.SYNOPSIS
    SynaptixLabs project start script (Windows PowerShell)
    Generic scaffold — edit the CONFIGURATION section for your project.

.DESCRIPTION
    Handles: stale process cleanup, cache cleaning, build stamping,
    backend + frontend launch, health check, PYTHONDONTWRITEBYTECODE.
    Based on AGENTS project start.ps1 patterns.

.PARAMETER Stop
    Stop all running project processes.
.PARAMETER Production
    Run in production mode (no hot-reload).
.PARAMETER BackendOnly
    Start only the backend server.
.PARAMETER Test
    Run the project test suite.
.PARAMETER Port
    Backend port (default from config or 8000).
#>
param(
    [switch]$Stop,
    [switch]$Production,
    [switch]$BackendOnly,
    [switch]$Test,
    [switch]$Status,
    [int]$Port = 0
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================================
# CONFIGURATION — Edit this section per project
# ============================================================================
$ProjectName     = "{{PROJECT_NAME}}"          # e.g. "My Project"
$BackendType     = "python"                     # "python" | "node"
$BackendDir      = "backend"                    # Relative to repo root ("." for monolith)
$BackendCmd      = "uvicorn app.main:app"       # Python: uvicorn entrypoint. Node: ignored (uses npm)
$ReloadDirs      = @("app", "modules")          # Python: --reload-dir targets (empty = watch all)
$FrontendDir     = "frontend"                   # matches the shipped skeleton; "" if none/monolith
$DefaultPort     = 8000                         # Backend port
$UIPort          = 5173                         # Frontend port
$HealthPath      = "/health"                    # Health check endpoint path
$EnvFileName     = ".env"                       # Env file name (relative to BackendDir)
# ============================================================================

if ($Port -eq 0) {
    # Try reading PORT from .env
    $envPath = Join-Path $ScriptDir $BackendDir $EnvFileName
    if ($BackendDir -eq ".") { $envPath = Join-Path $ScriptDir $EnvFileName }
    if (Test-Path $envPath) {
        $portLine = Get-Content $envPath | Where-Object { $_ -match "^PORT=" }
        if ($portLine) { $Port = [int]($portLine -replace "^PORT=","") }
    }
    if ($Port -eq 0) { $Port = $DefaultPort }
}

# ── Find Python ───────────────────────────────────────
function Find-Python {
    $candidates = @(
        (Join-Path $ScriptDir $BackendDir ".venv\Scripts\python.exe"),
        (Join-Path $ScriptDir $BackendDir "venv\Scripts\python.exe")
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return "python"
}

# ── Kill process on port ──────────────────────────────
function Clear-Port([int]$PortNum) {
    $conn = Get-NetTCPConnection -LocalPort $PortNum -State Listen -ErrorAction SilentlyContinue
    if ($conn) {
        $procId = $conn[0].OwningProcess
        Write-Host "[start.ps1] Port $PortNum in use by PID $procId - killing..." -ForegroundColor Yellow
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}

# ── Stop command ──────────────────────────────────────
if ($Stop) {
    Write-Host "[start.ps1] Stopping servers..." -ForegroundColor Yellow
    Clear-Port $Port
    if ($FrontendDir) { Clear-Port $UIPort }
    Write-Host "[start.ps1] Done." -ForegroundColor Green
    return
}

# ── Status command ────────────────────────────────────
if ($Status) {
    Write-Host "[start.ps1] Checking $ProjectName status..." -ForegroundColor Cyan
    $beUp = $null -ne (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    $feUp = $false
    if ($FrontendDir) {
        $feUp = $null -ne (Get-NetTCPConnection -LocalPort $UIPort -State Listen -ErrorAction SilentlyContinue)
    }
    Write-Host "  Backend  (port $Port):   $(if ($beUp) { 'UP' } else { 'DOWN' })" -ForegroundColor $(if ($beUp) { 'Green' } else { 'Red' })
    if ($FrontendDir) {
        Write-Host "  Frontend (port $UIPort): $(if ($feUp) { 'UP' } else { 'DOWN' })" -ForegroundColor $(if ($feUp) { 'Green' } else { 'Red' })
    }
    if ($beUp) {
        try {
            $h = Invoke-RestMethod "http://localhost:$Port$HealthPath" -TimeoutSec 3
            Write-Host "  Health:  $($h.status) | Build: $($h.build_stamp)" -ForegroundColor Green
        } catch {
            Write-Host "  Health:  endpoint unreachable" -ForegroundColor Yellow
        }
    }
    return
}

# ── Resolve runtime ───────────────────────────────────
$py = $null
if ($BackendType -eq "python") {
    $py = Find-Python
    Write-Host "[start.ps1] Python: $py" -ForegroundColor Cyan
}

# ── Validate .env ─────────────────────────────────────
$envCheck = if ($BackendDir -eq ".") { Join-Path $ScriptDir $EnvFileName } else { Join-Path $ScriptDir $BackendDir $EnvFileName }
if (-not (Test-Path $envCheck)) {
    Write-Host "[start.ps1] WARNING: $EnvFileName not found at $envCheck" -ForegroundColor Yellow
}

# ── Test command ──────────────────────────────────────
if ($Test) {
    if ($BackendType -eq "python") {
        Push-Location (Join-Path $ScriptDir $BackendDir)
        & $py -m pytest -v --tb=short
        Pop-Location
    } elseif ($BackendType -eq "node") {
        Push-Location $ScriptDir
        & npm.cmd test
        Pop-Location
    }
    return
}

# ═══════════════════════════════════════════════════════
# STEP 1: Kill stale processes
# ═══════════════════════════════════════════════════════
Write-Host "[start.ps1] Killing stale processes..." -ForegroundColor Yellow
Clear-Port $Port
if ($FrontendDir -and -not $BackendOnly) { Clear-Port $UIPort }
Start-Sleep -Seconds 1
Write-Host "[start.ps1] Processes cleared" -ForegroundColor Green

# ═══════════════════════════════════════════════════════
# STEP 2: Clean caches
# ═══════════════════════════════════════════════════════
if ($BackendType -eq "python") {
    Write-Host "[start.ps1] Cleaning Python bytecache..." -ForegroundColor Yellow
    $cacheCount = 0
    Get-ChildItem -Path (Join-Path $ScriptDir $BackendDir) -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\\/]\.venv[\\\/]' } |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $cacheCount++ }
    Write-Host "[start.ps1] Removed $cacheCount __pycache__ directories" -ForegroundColor Green
}
if ($FrontendDir) {
    $nextCache = Join-Path $ScriptDir $FrontendDir ".next" "cache"
    if (Test-Path $nextCache) {
        Remove-Item -Recurse -Force $nextCache -ErrorAction SilentlyContinue
        Write-Host "[start.ps1] Cleared .next/cache" -ForegroundColor Green
    }
}

# ═══════════════════════════════════════════════════════
# STEP 3: Build stamp
# ═══════════════════════════════════════════════════════
$buildStamp = (Get-Date).ToString("yyyy-MM-dd_HH:mm:ss")
$env:BUILD_STAMP = $buildStamp
Write-Host "[start.ps1] Build stamp: $buildStamp" -ForegroundColor Green

# ═══════════════════════════════════════════════════════
# STEP 4: Start frontend (if applicable)
# ═══════════════════════════════════════════════════════
$frontendJob = $null
$startFrontend = $FrontendDir -and (-not $BackendOnly) -and (-not $Production)

if ($startFrontend) {
    $feDir = Join-Path $ScriptDir $FrontendDir
    if (-not (Test-Path (Join-Path $feDir "node_modules"))) {
        Write-Host "[start.ps1] Installing frontend dependencies..." -ForegroundColor Yellow
        Push-Location $feDir; npm.cmd install; Pop-Location
    }
    Write-Host "[start.ps1] Starting frontend on http://localhost:$UIPort" -ForegroundColor Green
    $frontendJob = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c cd /d `"$feDir`" && npx vite --port $UIPort --host" `
        -PassThru -NoNewWindow
    Write-Host "[start.ps1] Frontend PID: $($frontendJob.Id)"
}

# ═══════════════════════════════════════════════════════
# STEP 5: Banner + Start backend
# ═══════════════════════════════════════════════════════
Write-Host ""
Write-Host "  ============================================" -ForegroundColor DarkCyan
Write-Host "   $ProjectName" -ForegroundColor DarkCyan
Write-Host "  --------------------------------------------" -ForegroundColor DarkCyan
Write-Host "   Build:    $buildStamp" -ForegroundColor DarkCyan
Write-Host "   Backend:  http://localhost:$Port" -ForegroundColor DarkCyan
if ($startFrontend) {
    Write-Host "   Frontend: http://localhost:$UIPort" -ForegroundColor DarkCyan
}
Write-Host "   API docs: http://localhost:$Port/docs" -ForegroundColor DarkCyan
Write-Host "   Press Ctrl+C to stop" -ForegroundColor DarkCyan
Write-Host "  ============================================" -ForegroundColor DarkCyan
Write-Host ""

$beDir = if ($BackendDir -eq ".") { $ScriptDir } else { Join-Path $ScriptDir $BackendDir }
Push-Location $beDir

if ($BackendType -eq "python") {
    # Disable .pyc bytecache — prevents stale code on Windows where file locks
    # block __pycache__ deletion. Slightly slower startup, guarantees fresh imports.
    $env:PYTHONDONTWRITEBYTECODE = "1"
    # Split "uvicorn app.main:app" into module + arg so `python -m` receives `uvicorn` as the
    # module and `app.main:app` as a separate token. Passing the whole string would run
    # `python -m "uvicorn app.main:app"` — an invalid module name — because PowerShell does not
    # word-split a string variable the way a POSIX shell does.
    $beCmdParts = $BackendCmd -split '\s+'
    try {
        if ($Production) {
            & $py -m @beCmdParts --host 0.0.0.0 --port $Port
        } else {
            $reloadArgs = @("--reload")
            foreach ($rd in $ReloadDirs) {
                if ($rd) { $reloadArgs += "--reload-dir"; $reloadArgs += $rd }
            }
            & $py -m @beCmdParts --host 0.0.0.0 --port $Port @reloadArgs
        }
    } finally {
        Pop-Location
        if ($frontendJob -and (-not $frontendJob.HasExited)) {
            Stop-Process -Id $frontendJob.Id -Force -ErrorAction SilentlyContinue
        }
    }
} elseif ($BackendType -eq "node") {
    $env:PORT = $Port
    try {
        if ($Production) {
            & npm.cmd run build
            & npm.cmd run start
        } else {
            & npm.cmd run dev
        }
    } finally {
        Pop-Location
        if ($frontendJob -and (-not $frontendJob.HasExited)) {
            Stop-Process -Id $frontendJob.Id -Force -ErrorAction SilentlyContinue
        }
    }
}
