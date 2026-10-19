#Requires -Version 5.1
<#
.SYNOPSIS
  Останавливает API, Flutter, приложение в Android-эмуляторе и Docker Compose (Postgres, Redis, MailHog, MinIO).

.PARAMETER Volumes
  Также удалить volumes Postgres и MinIO.
#>
param(
    [switch]$Volumes
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}

$DevopsRoot = $PSScriptRoot
$Root = Split-Path -Parent $DevopsRoot
$script:CallerLocation = (Get-Location).Path
$RunDir = Join-Path $DevopsRoot ".run"
$ApiPidFile = Join-Path $RunDir "api.pid"

Set-Location $Root

function Write-Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Host $Message -ForegroundColor Yellow
}

function Stop-PidTree([int]$ProcessId) {
    if ($ProcessId -le 0) {
        return
    }
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
        Write-Warn "Процесс $ProcessId уже не запущен, пропускаем."
        return
    }
    cmd.exe /c "taskkill /PID $ProcessId /T /F >nul 2>&1" | Out-Null
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 128) {
        Write-Warn "Не удалось остановить $ProcessId (код $LASTEXITCODE), продолжаем."
    }
}

function Stop-PidFile([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) {
        return
    }
    $raw = (Get-Content $Path -ErrorAction SilentlyContinue | Select-Object -First 1)
    $procId = 0
    if ([int]::TryParse("$raw", [ref]$procId) -and $procId -gt 0) {
        Write-Info "Останавливаем ${Label} (pid $procId)..."
        Stop-PidTree $procId
    }
    Remove-Item $Path -ErrorAction SilentlyContinue
}

function Stop-CommandMatch([string]$Pattern, [string]$Label) {
    $candidates = @()
    try {
        $candidates = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match $Pattern })
    } catch {
        Write-Warn "Не удалось получить список процессов ${Label}, продолжаем."
        return
    }

    foreach ($proc in $candidates) {
        $id = [int]$proc.ProcessId
        Write-Info "Останавливаем процесс $id ($($proc.Name), $Label)..."
        Stop-PidTree $id
    }
}

function Stop-Api {
    Stop-PidFile $ApiPidFile "API"
    Stop-CommandMatch "MusicAntiBlur\.Api" "API"
}

function Stop-Flutter {
    Get-ChildItem -Path $RunDir -Filter "flutter*.pid" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-PidFile $_.FullName "Flutter"
    }
    Stop-CommandMatch "Music Anti Blur — Flutter" "Flutter"
    Stop-CommandMatch "flutter(\.bat)? run" "Flutter"
}

function Get-AdbExe {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) {
        $sdk = $env:ANDROID_SDK_ROOT
    }
    if (-not $sdk) {
        $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    }
    $exe = Join-Path $sdk "platform-tools\adb.exe"
    if (Test-Path -LiteralPath $exe) {
        return $exe
    }
    return $null
}

function Stop-EmulatorApp {
    $adb = Get-AdbExe
    if (-not $adb) {
        Write-Warn "adb не найден, приложение в эмуляторе не останавливаем."
        return
    }
    $package = "com.musicantiblur.music_anti_blur"
    $serials = @()
    foreach ($line in @(& $adb devices 2>$null)) {
        if ("$line" -match '^(emulator-\d+)\s+device\b') {
            $serials += $Matches[1]
        }
    }
    foreach ($serial in $serials) {
        Write-Info "Останавливаем приложение в $serial..."
        & $adb -s $serial shell am force-stop $package
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Не удалось остановить приложение на $serial."
        }
    }
}

function Stop-Infra {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Warn "docker не найден, Compose пропускаем."
        return
    }
    docker info 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Docker не запущен, Compose пропускаем."
        return
    }

    $envFile = Join-Path $Root ".env"
    $composeArgs = @("compose")
    if (Test-Path $envFile) {
        $composeArgs += @("--env-file", ".env")
    }
    $composeArgs += @("down")
    if ($Volumes) {
        $composeArgs += @("--volumes")
        Write-Info "Docker Compose down --volumes (данные Postgres будут удалены)..."
    } else {
        Write-Info "Docker Compose down (тома сохраняются)..."
    }

    & docker @composeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose down не удался."
    }
}

try {
    Write-Host ""
    Write-Host "Music Anti Blur — остановка" -ForegroundColor Green
    try {
        Stop-Api
    } catch {
        Write-Warn "Остановка API прошла с ошибкой: $($_.Exception.Message). Продолжаем."
    }
    try {
        Stop-Flutter
    } catch {
        Write-Warn "Остановка Flutter прошла с ошибкой: $($_.Exception.Message). Продолжаем."
    }
    try {
        Stop-EmulatorApp
    } catch {
        Write-Warn "Остановка приложения в эмуляторе: $($_.Exception.Message). Продолжаем."
    }
    try {
        Stop-Infra
    } catch {
        Write-Warn "Compose: $($_.Exception.Message)"
    }
    Write-Info "Инфраструктура выключена."
    if (-not $Volumes) {
        Write-Warn "Тома Postgres и MinIO на месте. Полная очистка: devops\stop.cmd -Volumes"
    }
} finally {
    if ($script:CallerLocation) {
        Set-Location -LiteralPath $script:CallerLocation
    }
}
