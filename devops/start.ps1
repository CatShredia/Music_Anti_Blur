#Requires -Version 5.1
<#
.SYNOPSIS
  Поднимает Postgres/Redis/MailHog/MinIO и API.
  Режимы local/dual/deploy ещё запускают Flutter.
  В режиме local и api после healthy API импортирует no_commit/music (если папка есть).

.PARAMETER Mode
  Пропустить меню: local | deploy | dual | api | 1 | 2 | 3 | 4 | 0
#>
param(
    [string]$Mode = ""
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch {}

$DevopsRoot = $PSScriptRoot
$Root = Split-Path -Parent $DevopsRoot
$RunDir = Join-Path $DevopsRoot ".run"
$ApiProject = Join-Path $Root "src\api\MusicAntiBlur.Api\MusicAntiBlur.Api.csproj"
$MobileDir = Join-Path $Root "src\mobile"
$HealthUrl = "http://127.0.0.1:5080/health"

Set-Location $Root

function Write-Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Warn([string]$Message) {
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Err([string]$Message) {
    Write-Host $Message -ForegroundColor Red
}

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Не найдена команда '$Name'. Установите её и повторите."
    }
}

function Test-InteractivePrompt {
    try {
        return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    } catch {
        return $true
    }
}

function Confirm-Yes([string]$Prompt, [string]$UnknownHint = "Неизвестный ответ, считаем да.") {
    $choice = Read-Host "$Prompt [Y]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return $true
    }
    $value = $choice.Trim().ToLowerInvariant()
    if ($value -in @("n", "no", "н", "нет", "0", "q", "quit")) {
        return $false
    }
    if ($value -match '^[yYдД]') {
        return $true
    }
    Write-Warn $UnknownHint
    return $true
}

function Test-FfmpegReady {
    return [bool]((Get-Command ffmpeg -ErrorAction SilentlyContinue) -and (Get-Command ffprobe -ErrorAction SilentlyContinue))
}

function Sync-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($chunk in @($machine, $user, $env:Path)) {
        if (-not [string]::IsNullOrWhiteSpace($chunk)) {
            [void]$parts.Add($chunk)
        }
    }
    $links = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    if (Test-Path -LiteralPath (Join-Path $links "ffmpeg.exe")) {
        $parts.Insert(0, $links)
    }
    $env:Path = ($parts -join ";")
}

function Find-FfmpegBinDirectory {
    $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
    $candidates = New-Object System.Collections.Generic.List[string]
    [void]$candidates.Add((Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"))
    [void]$candidates.Add("C:\ffmpeg\bin")
    [void]$candidates.Add((Join-Path $env:ProgramFiles "ffmpeg\bin"))
    if ($pf86) {
        [void]$candidates.Add((Join-Path $pf86 "ffmpeg\bin"))
    }
    [void]$candidates.Add((Join-Path $env:ProgramData "chocolatey\bin"))
    foreach ($dir in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($dir) -and (Test-Path -LiteralPath (Join-Path $dir "ffmpeg.exe"))) {
            return $dir
        }
    }
    $packages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $packages) {
        $found = Get-ChildItem -LiteralPath $packages -Directory -Filter "Gyan.FFmpeg*" -ErrorAction SilentlyContinue |
            ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue } |
            Select-Object -First 1
        if ($found) {
            return $found.DirectoryName
        }
    }
    return $null
}

function Invoke-FfmpegInstaller {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $hadInstaller = $false
    try {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            $hadInstaller = $true
            Write-Info "Установка FFmpeg через winget (Gyan.FFmpeg)..."
            & winget install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements --disable-interactivity
            # 0 = ок; -1978335189 = уже стоит / нет обновления
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
                return $true
            }
            Write-Warn "winget вернул код $LASTEXITCODE."
        }
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            $hadInstaller = $true
            Write-Info "Установка FFmpeg через Chocolatey..."
            & choco install ffmpeg -y
            return $LASTEXITCODE -eq 0
        }
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $hadInstaller = $true
            Write-Info "Установка FFmpeg через scoop..."
            & scoop install ffmpeg
            return $LASTEXITCODE -eq 0
        }
    } finally {
        $ErrorActionPreference = $prev
    }
    if (-not $hadInstaller) {
        Write-Warn "Нет winget, choco или scoop — автоматическая установка невозможна."
    }
    return $false
}

function Ensure-Ffmpeg {
    if (Test-FfmpegReady) {
        return
    }

    Write-Warn "FFmpeg не найден (нужны ffmpeg и ffprobe в PATH для транскода Hangfire)."
    if (-not (Test-InteractivePrompt)) {
        Write-Warn "Нет интерактивного ввода — установку пропускаем. Поставьте FFmpeg вручную."
        return
    }

    if (-not (Confirm-Yes "Установить FFmpeg сейчас?")) {
        Write-Warn "Продолжаем без FFmpeg. Транскод Hangfire не завершится."
        return
    }

    if (-not (Invoke-FfmpegInstaller)) {
        Write-Warn "Не удалось установить FFmpeg автоматически. Windows: winget install Gyan.FFmpeg"
        return
    }

    Sync-SessionPath
    $bin = Find-FfmpegBinDirectory
    if ($bin) {
        $env:Path = "$bin;$env:Path"
    }

    if (Test-FfmpegReady) {
        Write-Info "FFmpeg готов: $((Get-Command ffmpeg).Source)"
        return
    }

    Write-Warn "FFmpeg установлен, но не виден в PATH этого сеанса. Откройте новый терминал и повторите start."
}

function Ensure-DotEnv {
    $envFile = Join-Path $Root ".env"
    $localExample = Join-Path $Root ".env.local.example"
    if (Test-Path $envFile) {
        return
    }

    Write-Warn "Файл .env не найден."
    if (-not (Test-Path $localExample)) {
        throw "Нет .env.local.example. Создайте .env вручную и повторите."
    }

    if (-not (Test-InteractivePrompt)) {
        throw "Нет .env и нет интерактивного ввода. Скопируйте .env.local.example в .env вручную."
    }

    if (-not (Confirm-Yes "Скопировать .env.local.example в .env и продолжить?" "Неизвестный ответ, копируем .env.")) {
        throw "Прервано: без .env скрипт не запускает инфраструктуру."
    }

    Copy-Item $localExample $envFile
    Write-Info "Создан .env из .env.local.example."
}

function Resolve-StartMode([string]$Raw) {
    $value = $Raw.Trim().ToLowerInvariant()
    if ($value -in @("1", "local", "dev", "--local")) { return "local" }
    if ($value -in @("2", "deploy", "--deploy")) { return "deploy" }
    if ($value -in @("3", "dual", "emulator", "chrome", "emulator-chrome", "--dual")) { return "dual" }
    if ($value -in @("4", "api", "backend", "no-flutter", "phone", "--api")) { return "api" }
    if ($value -in @("0", "exit", "q", "quit", "--exit")) { return "exit" }
    return $null
}

function Choose-Mode {
    if ($Mode) {
        $parsed = Resolve-StartMode $Mode
        if (-not $parsed) {
            throw "Неизвестный режим '$Mode'. Используйте local, deploy, dual, api или exit."
        }
        return $parsed
    }

    Write-Host ""
    Write-Host "Music Anti Blur" -ForegroundColor Green
    Write-Host "Режим:"
    Write-Host "  [1] Локальная разработка   (по умолчанию, Enter)"
    Write-Host "  [2] Развертывание"
    Write-Host "  [3] Эмулятор Android + Chrome"
    Write-Host "  [4] API + Docker (без Flutter, телефон)"
    Write-Host "  [0] Выход"
    $choice = Read-Host "Выбор [1]"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return "local"
    }
    $parsed = Resolve-StartMode $choice
    if ($parsed) {
        return $parsed
    }
    Write-Warn "Неизвестный пункт, берём локальную разработку."
    return "local"
}

function Start-Infra {
    Write-Info "Docker Compose: Postgres, Redis, MailHog, MinIO..."
    docker info 1>$null 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker не запущен. Откройте Docker Desktop и повторите."
    }

    docker compose --env-file .env up -d
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up не удался."
    }

    Write-Info "Ждём healthy у Postgres, Redis и MinIO..."
    $deadline = (Get-Date).AddSeconds(90)
    do {
        $pgId = docker compose ps -q postgres
        $rdId = docker compose ps -q redis
        $mnId = docker compose ps -q minio
        if ($pgId -and $rdId -and $mnId) {
            $pg = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $pgId
            $rd = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $rdId
            $mn = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $mnId
            if ($pg -eq "healthy" -and $rd -eq "healthy" -and $mn -eq "healthy") {
                return
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Postgres/Redis/MinIO не стали healthy за 90 с. docker compose ps"
}

function Wait-Api {
    Write-Info "Ждём API $HealthUrl ..."
    $deadline = (Get-Date).AddSeconds(90)
    do {
        try {
            $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
                Write-Info "API отвечает."
                return
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)

    throw "API не ответил на $HealthUrl за 90 с. Смотрите окно/лог API."
}

function Start-ApiLocal {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    Write-Info "Запуск API (Development) в отдельном окне..."
    $cmd = @"
`$Host.UI.RawUI.WindowTitle = 'Music Anti Blur — API'
Set-Location -LiteralPath '$Root'
`$env:ASPNETCORE_ENVIRONMENT='Development'
dotnet run --project '$ApiProject'
"@
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-Command", $cmd) -PassThru
    Set-Content -Path (Join-Path $RunDir "api.pid") -Value $proc.Id -Encoding ASCII
}

function Start-ApiDeploy {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $out = Join-Path $RunDir "api"
    Write-Info "dotnet publish -c Release -> $out"
    dotnet publish $ApiProject -c Release -o $out --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish не удался."
    }

    Write-Info "Запуск API (Production) в отдельном окне..."
    $dll = Join-Path $out "MusicAntiBlur.Api.dll"
    $cmd = @"
`$Host.UI.RawUI.WindowTitle = 'Music Anti Blur — API'
Set-Location -LiteralPath '$Root'
`$env:ASPNETCORE_ENVIRONMENT='Production'
dotnet '$dll'
"@
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-Command", $cmd) -PassThru
    Set-Content -Path (Join-Path $RunDir "api.pid") -Value $proc.Id -Encoding ASCII
}

function Get-FlutterDeviceRows {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(& flutter devices 2>$null)) {
        $text = [string]$line
        if ($text -notmatch '•') {
            continue
        }
        $parts = @($text -split '•' | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 2) {
            continue
        }
        [void]$rows.Add([pscustomobject]@{
            Name     = $parts[0]
            Id       = $parts[1]
            Platform = $(if ($parts.Count -ge 3) { $parts[2] } else { "" })
        })
    }
    if ($rows.Count -eq 0) {
        return @()
    }
    return , $rows.ToArray()
}

function Test-ChromeDevicePresent {
    foreach ($row in @(Get-FlutterDeviceRows)) {
        if ($row.Id -eq "chrome") {
            return $true
        }
    }
    return $false
}

function Get-AndroidEmulatorDeviceId {
    foreach ($row in @(Get-FlutterDeviceRows)) {
        if ($row.Id -match '^emulator-\d+$') {
            return $row.Id
        }
    }
    return $null
}

function Get-FirstAndroidAvdId {
    foreach ($line in @(& flutter emulators 2>$null)) {
        $text = [string]$line
        if ($text -notmatch '•') {
            continue
        }
        $parts = @($text -split '•' | ForEach-Object { $_.Trim() })
        $id = $parts[0]
        if ([string]::IsNullOrWhiteSpace($id) -or $id -eq "Id" -or $id -match '^-{2,}') {
            continue
        }
        if ($text.ToLowerInvariant() -match 'android|pixel') {
            return $id
        }
    }
    return $null
}

function Get-AndroidEmulatorExe {
    $sdk = $env:ANDROID_HOME
    if (-not $sdk) {
        $sdk = $env:ANDROID_SDK_ROOT
    }
    if (-not $sdk) {
        $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    }
    $exe = Join-Path $sdk "emulator\emulator.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Не найден Android emulator ($exe). Проверьте ANDROID_HOME."
    }
    return $exe
}

function Get-PathFreeGigabytes([string]$Path) {
    try {
        $resolved = $Path
        if (Test-Path -LiteralPath $Path) {
            $resolved = (Resolve-Path -LiteralPath $Path).Path
        }
        $root = [System.IO.Path]::GetPathRoot($resolved)
        if ([string]::IsNullOrWhiteSpace($root)) {
            return $null
        }
        $drive = Get-PSDrive -Name $root.Substring(0, 1) -ErrorAction Stop
        return [math]::Round($drive.Free / 1GB, 1)
    } catch {
        return $null
    }
}

function Assert-ChromeDevice {
    if (Test-ChromeDevicePresent) {
        return
    }
    throw "В flutter devices нет chrome. Нужен Google Chrome и включённый web: flutter config --enable-web."
}

function Start-AndroidEmulatorIfNeeded {
    if (Get-AndroidEmulatorDeviceId) {
        Write-Info "Android-эмулятор уже запущен."
        return
    }

    $avdId = Get-FirstAndroidAvdId
    if (-not $avdId) {
        throw "Нет Android-эмулятора (AVD). Создайте его в Android Studio, затем flutter emulators."
    }

    $avdHome = Join-Path $env:USERPROFILE ".android\avd"
    $free = Get-PathFreeGigabytes $avdHome
    if ($null -ne $free -and $free -lt 6) {
        Write-Warn "На диске AVD свободно ${free} ГБ. Эмулятор Android обычно требует несколько гигабайт свободного места."
        Write-Warn "Освободите место на этом диске или перенесите AVD (path= в файле $avdHome\<id>.ini)."
        if ($free -lt 2) {
            throw "Слишком мало места (${free} ГБ) для запуска AVD $avdId."
        }
    }

    $exe = Get-AndroidEmulatorExe
    Write-Info "Запускаем эмулятор $avdId..."
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $errLog = Join-Path $RunDir "emulator-launch.err.log"
    $outLog = Join-Path $RunDir "emulator-launch.out.log"
    Remove-Item -Force -ErrorAction SilentlyContinue $errLog, $outLog
    $proc = Start-Process -FilePath $exe -ArgumentList @("-avd", $avdId) -PassThru -RedirectStandardError $errLog -RedirectStandardOutput $outLog
    Start-Sleep -Seconds 5
    if ($proc.HasExited) {
        $detail = ""
        foreach ($log in @($errLog, $outLog)) {
            if (Test-Path -LiteralPath $log) {
                $detail += [string](Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue)
            }
        }
        $fatal = @($detail -split "`r?`n" | Where-Object { $_ -match 'FATAL|Error:|ERROR\s+\|' } | Select-Object -First 8)
        $msg = "Эмулятор $avdId вышел с кодом $($proc.ExitCode)."
        if ($fatal.Count -gt 0) {
            $msg += " " + (($fatal | ForEach-Object { $_.Trim() }) -join " ")
        }
        throw $msg
    }
}

function Wait-AndroidEmulatorDevice {
    Write-Info "Ждём Android-эмулятор в flutter devices..."
    $deadline = (Get-Date).AddSeconds(120)
    do {
        $id = Get-AndroidEmulatorDeviceId
        if ($id) {
            Write-Info "Эмулятор: $id"
            return $id
        }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)

    throw "Эмулятор не появился в flutter devices за 120 с."
}

function Start-PowerShellWindow([string]$Title, [string]$PidName, [string]$ScriptBody) {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $safeName = ($PidName -replace '\.pid$', '' -replace '[^\w.-]', '-')
    $runner = Join-Path $RunDir "$safeName.ps1"
    Set-Content -Path $runner -Value $ScriptBody -Encoding UTF8
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-NoProfile", "-File", $runner) -PassThru
    Set-Content -Path (Join-Path $RunDir $PidName) -Value $proc.Id -Encoding ASCII
}

function Start-FlutterWindow([string]$Title, [string]$DeviceId, [string]$PidName, [bool]$RunPubGet) {
    $titleEsc = $Title.Replace("'", "''")
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add("`$Host.UI.RawUI.WindowTitle = '$titleEsc'")
    [void]$lines.Add("Set-Location -LiteralPath '$MobileDir'")
    if ($RunPubGet) {
        [void]$lines.Add("flutter pub get")
        [void]$lines.Add("if (`$LASTEXITCODE -ne 0) { Write-Host 'flutter pub get не удался.' -ForegroundColor Red; pause; exit `$LASTEXITCODE }")
    }
    if ($DeviceId) {
        [void]$lines.Add("flutter run --device-id=$DeviceId")
    } else {
        [void]$lines.Add("flutter run")
    }
    Start-PowerShellWindow -Title $Title -PidName $PidName -ScriptBody ($lines -join "`r`n")
}

function Start-FlutterDev {
    param([string[]]$DeviceIds = @())

    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    if ($DeviceIds.Count -eq 0) {
        Write-Info "Запуск Flutter в отдельном окне..."
        $deviceId = $env:FLUTTER_DEVICE
        Start-FlutterWindow -Title "Music Anti Blur — Flutter" -DeviceId $deviceId -PidName "flutter.pid" -RunPubGet $true
        return
    }

    Write-Info "flutter pub get..."
    Push-Location $MobileDir
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) {
            throw "flutter pub get не удался."
        }
    } finally {
        Pop-Location
    }

    foreach ($id in $DeviceIds) {
        if ($id -match '\s') {
            throw "Некорректный id устройства Flutter: '$id'."
        }
        Write-Info "Запуск Flutter ($id) в отдельном окне..."
        $safe = $id -replace '[^\w.-]', '-'
        Start-FlutterWindow -Title "Music Anti Blur — Flutter ($id)" -DeviceId $id -PidName "flutter-$safe.pid" -RunPubGet $false
    }
}

function Get-LanIPv4 {
    $addrs = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($item in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
            $ip = [string]$item.IPAddress
            if ($ip -and $ip -notlike '127.*' -and $ip -notlike '169.254.*') {
                if (-not $addrs.Contains($ip)) {
                    [void]$addrs.Add($ip)
                }
            }
        }
    } catch {}
    return , $addrs.ToArray()
}

function Try-AdbReverse {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Write-Warn "adb не найден. USB-телефон: поставьте platform-tools или ходите по Wi‑Fi на LAN IP."
        return
    }
    $lines = @(& adb devices 2>$null)
    $ready = @($lines | Where-Object { $_ -match '\tdevice$' })
    if ($ready.Count -eq 0) {
        Write-Warn "adb есть, телефон не в состоянии device. USB + отладка по USB."
        return
    }
    & adb reverse tcp:5080 tcp:5080 | Out-Null
    & adb reverse tcp:9000 tcp:9000 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "adb reverse не удался. На телефоне используйте LAN IP ноутбука."
        return
    }
    Write-Info "USB: проброшены порты 5080 (API) и 9000 (MinIO) → на телефоне http://127.0.0.1:5080"
}

function Write-PhoneHints {
    Write-Host ""
    Write-Host "Телефон (USB или Wi‑Fi в той же сети):" -ForegroundColor DarkGray
    Write-Host "  APK по умолчанию ходит на http://10.0.2.2:5080 (это эмулятор)." -ForegroundColor DarkGray
    Write-Host "  Сборка под этот ноутбук:" -ForegroundColor DarkGray
    $ips = @(Get-LanIPv4)
    if ($ips.Count -eq 0) {
        Write-Host "    flutter build apk --release --dart-define=API_BASE_URL=http://<LAN-IP>:5080" -ForegroundColor DarkGray
    } else {
        foreach ($ip in $ips) {
            Write-Host "    flutter build apk --release --dart-define=API_BASE_URL=http://${ip}:5080" -ForegroundColor DarkGray
        }
    }
    Write-Host "  USB без LAN: adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000" -ForegroundColor DarkGray
    Write-Host "    тогда в приложении http://127.0.0.1:5080" -ForegroundColor DarkGray
    Try-AdbReverse
}

Assert-Command docker
Assert-Command dotnet

$selected = Choose-Mode
if ($selected -eq "exit") {
    Write-Info "Выход."
    exit 0
}

if ($selected -ne "api") {
    Assert-Command flutter
}

Ensure-DotEnv
Ensure-Ffmpeg

Write-Host ""
if ($selected -eq "local") {
    Write-Info "Режим: локальная разработка"
} elseif ($selected -eq "dual") {
    Write-Info "Режим: эмулятор Android + Chrome"
    Assert-ChromeDevice
    Start-AndroidEmulatorIfNeeded
} elseif ($selected -eq "api") {
    Write-Info "Режим: API + Docker (без Flutter)"
} else {
    Write-Info "Режим: развертывание (Release API + Flutter hot reload)"
    Write-Warn "Production без смены Jwt/паролей из .env.example небезопасен."
}

Start-Infra

if ($selected -eq "deploy") {
    Start-ApiDeploy
} else {
    Start-ApiLocal
}

Wait-Api

if ($selected -ne "deploy") {
    $seedScript = Join-Path $DevopsRoot "seed-local-music.ps1"
    Write-Info "После API: импорт no_commit/music (минимум 4 трека из каждой папки)..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $seedScript -ApiBase "http://127.0.0.1:5080"
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Импорт no_commit/music завершился с кодом $LASTEXITCODE."
    }
}

if ($selected -eq "dual") {
    $emulatorId = Wait-AndroidEmulatorDevice
    Start-FlutterDev -DeviceIds @("chrome", $emulatorId)
} elseif ($selected -ne "api") {
    Start-FlutterDev
}

Write-Host ""
Write-Host "HTTP API     http://127.0.0.1:5080" -ForegroundColor DarkGray
Write-Host "Swagger      http://127.0.0.1:5080/swagger  (только Development)" -ForegroundColor DarkGray
Write-Host "MailHog      http://127.0.0.1:8025" -ForegroundColor DarkGray
Write-Host "MinIO S3     http://127.0.0.1:9000" -ForegroundColor DarkGray
Write-Host "MinIO UI     http://127.0.0.1:9001  (minio / minio-local-only)" -ForegroundColor DarkGray
Write-Host "Hangfire     http://127.0.0.1:5080/hangfire" -ForegroundColor DarkGray
if ($selected -eq "api") {
    Write-PhoneHints
    Write-Info "API запущен без Flutter. Остановка: devops\stop.cmd"
} else {
    Write-Info "API и Flutter запущены в отдельных окнах. Остановка: devops\stop.cmd"
}
