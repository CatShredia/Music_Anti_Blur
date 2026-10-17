#Requires -Version 5.1
<#
.SYNOPSIS
  Поднимает Postgres/Redis/MailHog/MinIO и API.
  Локально — опционально 0–2 Flutter-клиента; публикация — только сервер.

.PARAMETER Mode
  Пропустить меню типа: local | publish | deploy | dual | api | 1 | 2 | 3 | 4

.PARAMETER Lang
  en | ru

.PARAMETER Device1
.PARAMETER Device2
  chrome | windows | emulator | none | concrete flutter device id
#>
param(
    [string]$Mode = "",
    [string]$Lang = "",
    [string]$Device1 = "",
    [string]$Device2 = ""
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
$script:UiLang = "ru"

Set-Location $Root

# --- i18n ---

$script:Messages = @{
    ru = @{
        title                 = "Music Anti Blur"
        choose_lang           = "Язык / Language"
        lang_ru               = "Русский"
        lang_en               = "English"
        lang_prompt           = "Выбор [RU]"
        env_missing           = "Файл .env не найден или пуст."
        env_offer             = "Скопировать шаблон в .env?"
        env_local             = ".env.local.example (локальные дефолты, Postgres 5433) — продолжить"
        env_example           = ".env.example — скопировать и выйти (заполните вручную)"
        env_abort             = "Отмена — без .env скрипт не запускает инфраструктуру."
        env_prompt            = "Выбор"
        env_created_local     = "Создан .env из .env.local.example."
        env_created_example   = "Создан .env из .env.example. Заполните секреты/порты и запустите start снова."
        env_no_templates      = "Нет .env.local.example и .env.example. Создайте .env вручную."
        env_no_tty            = "Нет .env и нет интерактивного ввода. Скопируйте шаблон в .env вручную."
        choose_kind           = "Тип развертывания"
        kind_local            = "Локальная разработка"
        kind_publish          = "Публикация (только сервер)"
        kind_prompt           = "Выбор [1]"
        mode_local            = "Режим: локальная разработка"
        mode_publish          = "Режим: публикация (Compose + Production API)"
        publish_warn          = "Production без смены Jwt/паролей из шаблона .env небезопасен."
        device_slot           = "Клиент Flutter"
        device_none           = "Ничего не запускать"
        device_chrome         = "Chrome"
        device_windows        = "Windows"
        device_emulator_run   = "Эмулятор Android (уже запущен: {0})"
        device_emulator_start = "Запустить Android-эмулятор (AVD)"
        device_usb            = "USB: {0}"
        device_prompt         = "Выбор [0]"
        device_default_hint   = "по умолчанию — ничего"
        no_flutter            = "Flutter не выбран — только API + Docker."
        need_cmd              = "Не найдена команда '{0}'. Установите её и повторите."
        yes_unknown           = "Неизвестный ответ, считаем да."
        ffmpeg_missing        = "FFmpeg не найден (нужны ffmpeg и ffprobe в PATH для транскода Hangfire)."
        ffmpeg_ask            = "Установить FFmpeg сейчас?"
        ffmpeg_skip           = "Продолжаем без FFmpeg. Транскод Hangfire не завершится."
        ffmpeg_no_tty         = "Нет интерактивного ввода — установку пропускаем. Поставьте FFmpeg вручную."
        ffmpeg_fail           = "Не удалось установить FFmpeg автоматически. Windows: winget install Gyan.FFmpeg"
        ffmpeg_ready          = "FFmpeg готов: {0}"
        ffmpeg_path           = "FFmpeg установлен, но не виден в PATH этого сеанса. Откройте новый терминал и повторите start."
        winget_install        = "Установка FFmpeg через winget (Gyan.FFmpeg)..."
        choco_install         = "Установка FFmpeg через Chocolatey..."
        scoop_install         = "Установка FFmpeg через scoop..."
        no_pkg_mgr            = "Нет winget, choco или scoop — автоматическая установка невозможна."
        infra_start           = "Docker Compose: Postgres, Redis, MailHog, MinIO..."
        docker_down           = "Docker не запущен. Откройте Docker Desktop и повторите."
        docker_wait_ask       = "Docker не запущен. Запустите Docker Desktop. Ждать, пока он поднимется?"
        docker_wait           = "Ждём Docker. Когда демон будет готов, скрипт продолжит (Ctrl+C — выход)..."
        docker_wait_tick      = "Docker ещё не отвечает — ждём..."
        docker_open           = "Открываем Docker Desktop..."
        docker_ready          = "Docker запущен."
        docker_no_tty         = "Docker не запущен, нет интерактивного ввода. Запустите Docker Desktop и повторите."
        infra_wait            = "Ждём healthy у Postgres, Redis и MinIO..."
        infra_fail            = "Postgres/Redis/MinIO не стали healthy за 90 с. docker compose ps"
        api_wait              = "Ждём API {0} ..."
        api_ok                = "API отвечает."
        api_fail              = "API не ответил на {0} за 90 с. Смотрите окно/лог API."
        api_local             = "Запуск API (Development) в отдельном окне..."
        api_publish           = "Запуск API (Production) в отдельном окне..."
        publish_build         = "dotnet publish -c Release -> {0}"
        publish_fail          = "dotnet publish не удался."
        seed                  = "После API: импорт no_commit/music (минимум 4 трека из каждой папки)..."
        seed_ask              = "Импортировать треки из no_commit/music?"
        seed_skip             = "Импорт no_commit/music пропущен."
        seed_fail             = "Импорт no_commit/music завершился с кодом {0}."
        emu_already           = "Android-эмулятор уже запущен."
        emu_none              = "Нет Android-эмулятора (AVD). Создайте его в Android Studio, затем flutter emulators."
        emu_disk_warn         = "На диске AVD свободно {0} ГБ. Эмулятор Android обычно требует несколько гигабайт."
        emu_disk_hint         = "Освободите место или перенесите AVD (path= в файле {0}\<id>.ini)."
        emu_disk_fail         = "Слишком мало места ({0} ГБ) для запуска AVD {1}."
        emu_start             = "Запускаем эмулятор {0}..."
        emu_fail              = "Эмулятор {0} вышел с кодом {1}."
        emu_wait              = "Ждём Android-эмулятор в flutter devices..."
        emu_found             = "Эмулятор: {0}"
        emu_timeout           = "Эмулятор не появился в flutter devices за 120 с."
        emu_exe_missing       = "Не найден Android emulator ({0}). Проверьте ANDROID_HOME."
        flutter_pub           = "flutter pub get..."
        flutter_pub_offline   = "Нет сети (pub.dev) — flutter pub get пропускаем, используем локальный кэш."
        flutter_pub_fail      = "flutter pub get не удался."
        flutter_start         = "Запуск Flutter ({0}) в отдельном окне..."
        flutter_bad_id        = "Некорректный id устройства Flutter: '{0}'."
        chrome_missing        = "В flutter devices нет chrome."
        done_server           = "Сервер запущен без Flutter. Остановка: devops\stop.cmd"
        done_clients          = "API и Flutter запущены в отдельных окнах. Остановка: devops\stop.cmd"
        phone_header          = "Телефон (USB или Wi‑Fi в той же сети):"
        phone_apk_default     = "  APK по умолчанию ходит на http://10.0.2.2:5080 (это эмулятор)."
        phone_build           = "  Сборка под этот ноутбук:"
        phone_usb             = "  USB без LAN: adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000"
        phone_usb_then        = "    тогда в приложении http://127.0.0.1:5080"
        adb_missing           = "adb не найден. USB-телефон: поставьте platform-tools или ходите по Wi‑Fi на LAN IP."
        adb_no_device         = "adb есть, телефон не в состоянии device. USB + отладка по USB."
        adb_reverse_fail      = "adb reverse не удался. На телефоне используйте LAN IP ноутбука."
        adb_reverse_ok        = "USB: проброшены порты 5080 (API) и 9000 (MinIO) → на телефоне http://127.0.0.1:5080"
        unknown_mode          = "Неизвестный режим '{0}'. Используйте local, publish, dual, api."
        unknown_device        = "Неизвестное устройство '{0}'."
        emulator_once         = "Эмулятор уже выбран в другом слоте."
        exit                  = "Выход."
    }
    en = @{
        title                 = "Music Anti Blur"
        choose_lang           = "Language / Язык"
        lang_ru               = "Русский"
        lang_en               = "English"
        lang_prompt           = "Choice [RU]"
        env_missing           = ".env is missing or empty."
        env_offer             = "Copy a template to .env?"
        env_local             = ".env.local.example (local defaults, Postgres 5433) — continue"
        env_example           = ".env.example — copy and exit (fill in manually)"
        env_abort             = "Aborted: without .env the script will not start infrastructure."
        env_prompt            = "Choice"
        env_created_local     = "Created .env from .env.local.example."
        env_created_example   = "Created .env from .env.example. Fill in secrets/ports and run start again."
        env_no_templates      = "Neither .env.local.example nor .env.example found. Create .env manually."
        env_no_tty            = "No .env and no interactive input. Copy a template to .env manually."
        choose_kind           = "Deployment type"
        kind_local            = "Local development"
        kind_publish          = "Publish (server only)"
        kind_prompt           = "Choice [1]"
        mode_local            = "Mode: local development"
        mode_publish          = "Mode: publish (Compose + Production API)"
        publish_warn          = "Production is unsafe without changing Jwt/passwords from the .env template."
        device_slot           = "Flutter client"
        device_none           = "Do not start Flutter"
        device_chrome         = "Chrome"
        device_windows        = "Windows"
        device_emulator_run   = "Android emulator (already running: {0})"
        device_emulator_start = "Launch Android emulator (AVD)"
        device_usb            = "USB: {0}"
        device_prompt         = "Choice [0]"
        device_default_hint   = "default — none"
        no_flutter            = "No Flutter selected — API + Docker only."
        need_cmd              = "Command '{0}' not found. Install it and retry."
        yes_unknown           = "Unknown answer, treating as yes."
        ffmpeg_missing        = "FFmpeg not found (need ffmpeg and ffprobe on PATH for Hangfire transcode)."
        ffmpeg_ask            = "Install FFmpeg now?"
        ffmpeg_skip           = "Continuing without FFmpeg. Hangfire transcode will not finish."
        ffmpeg_no_tty         = "No interactive input — skipping install. Install FFmpeg manually."
        ffmpeg_fail           = "Could not install FFmpeg automatically. Windows: winget install Gyan.FFmpeg"
        ffmpeg_ready          = "FFmpeg ready: {0}"
        ffmpeg_path           = "FFmpeg installed but not on PATH in this session. Open a new terminal and run start again."
        winget_install        = "Installing FFmpeg via winget (Gyan.FFmpeg)..."
        choco_install         = "Installing FFmpeg via Chocolatey..."
        scoop_install         = "Installing FFmpeg via scoop..."
        no_pkg_mgr            = "No winget, choco, or scoop — automatic install unavailable."
        infra_start           = "Docker Compose: Postgres, Redis, MailHog, MinIO..."
        docker_down           = "Docker is not running. Start Docker Desktop and retry."
        docker_wait_ask       = "Docker is not running. Start Docker Desktop. Wait until it is up?"
        docker_wait           = "Waiting for Docker. The script will continue when the engine is ready (Ctrl+C to quit)..."
        docker_wait_tick      = "Docker is still not answering — waiting..."
        docker_open           = "Opening Docker Desktop..."
        docker_ready          = "Docker is running."
        docker_no_tty         = "Docker is not running and there is no interactive input. Start Docker Desktop and retry."
        infra_wait            = "Waiting for Postgres, Redis and MinIO to become healthy..."
        infra_fail            = "Postgres/Redis/MinIO were not healthy within 90s. docker compose ps"
        api_wait              = "Waiting for API {0} ..."
        api_ok                = "API is up."
        api_fail              = "API did not answer {0} within 90s. Check the API window/log."
        api_local             = "Starting API (Development) in a new window..."
        api_publish           = "Starting API (Production) in a new window..."
        publish_build         = "dotnet publish -c Release -> {0}"
        publish_fail          = "dotnet publish failed."
        seed                  = "After API: importing no_commit/music (at least 4 tracks per folder)..."
        seed_ask              = "Import tracks from no_commit/music?"
        seed_skip             = "Skipping no_commit/music import."
        seed_fail             = "no_commit/music import exited with code {0}."
        emu_already           = "Android emulator already running."
        emu_none              = "No Android AVD. Create one in Android Studio, then flutter emulators."
        emu_disk_warn         = "AVD disk has {0} GB free. Android emulator usually needs several GB."
        emu_disk_hint         = "Free space or move the AVD (path= in {0}\<id>.ini)."
        emu_disk_fail         = "Too little free space ({0} GB) to start AVD {1}."
        emu_start             = "Launching emulator {0}..."
        emu_fail              = "Emulator {0} exited with code {1}."
        emu_wait              = "Waiting for Android emulator in flutter devices..."
        emu_found             = "Emulator: {0}"
        emu_timeout           = "Emulator did not appear in flutter devices within 120s."
        emu_exe_missing       = "Android emulator not found ({0}). Check ANDROID_HOME."
        flutter_pub           = "flutter pub get..."
        flutter_pub_offline   = "No network (pub.dev) — skipping flutter pub get, using local cache."
        flutter_pub_fail      = "flutter pub get failed."
        flutter_start         = "Starting Flutter ({0}) in a new window..."
        flutter_bad_id        = "Invalid Flutter device id: '{0}'."
        chrome_missing        = "chrome not found in flutter devices."
        done_server           = "Server running without Flutter. Stop: devops\stop.cmd"
        done_clients          = "API and Flutter started in separate windows. Stop: devops\stop.cmd"
        phone_header          = "Phone (USB or Wi‑Fi on the same network):"
        phone_apk_default     = "  Default APK targets http://10.0.2.2:5080 (emulator)."
        phone_build           = "  Build for this laptop:"
        phone_usb             = "  USB without LAN: adb reverse tcp:5080 tcp:5080 && adb reverse tcp:9000 tcp:9000"
        phone_usb_then        = "    then use http://127.0.0.1:5080 in the app"
        adb_missing           = "adb not found. USB phone: install platform-tools or use LAN IP over Wi‑Fi."
        adb_no_device         = "adb found, but no device in 'device' state. Enable USB debugging."
        adb_reverse_fail      = "adb reverse failed. Use the laptop LAN IP on the phone."
        adb_reverse_ok        = "USB: forwarded 5080 (API) and 9000 (MinIO) → phone http://127.0.0.1:5080"
        unknown_mode          = "Unknown mode '{0}'. Use local, publish, dual, api."
        unknown_device        = "Unknown device '{0}'."
        emulator_once         = "Emulator already selected in the other slot."
        exit                  = "Exit."
    }
}

function T([string]$Key, [object[]]$FormatArgs = @()) {
    $table = $script:Messages[$script:UiLang]
    if (-not $table -or -not $table.ContainsKey($Key)) {
        $table = $script:Messages["en"]
    }
    $fmt = [string]$table[$Key]
    if ($FormatArgs.Count -gt 0) {
        return ($fmt -f $FormatArgs)
    }
    return $fmt
}

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
        throw (T "need_cmd" @($Name))
    }
}

function Test-InteractivePrompt {
    try {
        return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    } catch {
        return $true
    }
}

function Confirm-Yes([string]$Prompt, [string]$UnknownHint = "") {
    if (-not $UnknownHint) {
        $UnknownHint = T "yes_unknown"
    }
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

function Test-EnvFileUsable([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    $raw = [string](Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    return -not [string]::IsNullOrWhiteSpace($raw)
}

function Choose-Language {
    if ($Lang) {
        $v = $Lang.Trim().ToLowerInvariant()
        if ($v -in @("en", "english")) { return "en" }
        if ($v -in @("ru", "russian", "рус", "русский")) { return "ru" }
        Write-Warn "Unknown Lang '$Lang', using ru."
        return "ru"
    }
    if (-not (Test-InteractivePrompt)) {
        return "ru"
    }
    Write-Host ""
    Write-Host (T "title") -ForegroundColor Green
    Write-Host (T "choose_lang")
    Write-Host "  [1] $(T 'lang_ru')  (Enter)"
    Write-Host "  [2] $(T 'lang_en')"
    $choice = Read-Host (T "lang_prompt")
    if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim() -in @("1", "ru", "RU", "рус", "русский")) {
        return "ru"
    }
    if ($choice.Trim() -in @("2", "en", "EN", "english", "English")) {
        return "en"
    }
    return "ru"
}

function Ensure-DotEnv {
    $envFile = Join-Path $Root ".env"
    $localExample = Join-Path $Root ".env.local.example"
    $plainExample = Join-Path $Root ".env.example"

    if (Test-EnvFileUsable $envFile) {
        return
    }

    Write-Warn (T "env_missing")
    $hasLocal = Test-Path -LiteralPath $localExample
    $hasPlain = Test-Path -LiteralPath $plainExample
    if (-not $hasLocal -and -not $hasPlain) {
        throw (T "env_no_templates")
    }

    if (-not (Test-InteractivePrompt)) {
        throw (T "env_no_tty")
    }

    Write-Host (T "env_offer")
    $opts = @()
    if ($hasLocal) {
        $opts += [pscustomobject]@{ Key = "local"; Label = T "env_local" }
    }
    if ($hasPlain) {
        $opts += [pscustomobject]@{ Key = "example"; Label = T "env_example" }
    }
    $opts += [pscustomobject]@{ Key = "abort"; Label = T "env_abort" }

    for ($i = 0; $i -lt $opts.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $opts[$i].Label)
    }
    $choice = Read-Host (T "env_prompt")
    $idx = 0
    if (-not [string]::IsNullOrWhiteSpace($choice) -and $choice -match '^\d+$') {
        $idx = [int]$choice - 1
    }
    if ($idx -lt 0 -or $idx -ge $opts.Count) {
        throw (T "env_abort")
    }
    $picked = $opts[$idx].Key
    if ($picked -eq "abort") {
        throw (T "env_abort")
    }
    if ($picked -eq "local") {
        Copy-Item $localExample $envFile -Force
        Write-Info (T "env_created_local")
        return
    }
    Copy-Item $plainExample $envFile -Force
    Write-Info (T "env_created_example")
    exit 0
}

function Resolve-Kind([string]$Raw) {
    $value = $Raw.Trim().ToLowerInvariant()
    if ($value -in @("1", "local", "dev", "--local")) { return "local" }
    if ($value -in @("2", "publish", "deploy", "--deploy", "--publish")) { return "publish" }
    if ($value -in @("3", "dual", "emulator", "chrome", "emulator-chrome", "--dual")) { return "dual" }
    if ($value -in @("4", "api", "backend", "no-flutter", "phone", "--api")) { return "api" }
    if ($value -in @("0", "exit", "q", "quit", "--exit")) { return "exit" }
    return $null
}

function Choose-Kind {
    if ($Mode) {
        $parsed = Resolve-Kind $Mode
        if (-not $parsed) {
            throw (T "unknown_mode" @($Mode))
        }
        return $parsed
    }
    if (-not (Test-InteractivePrompt)) {
        return "local"
    }

    Write-Host ""
    Write-Host (T "choose_kind")
    Write-Host "  [1] $(T 'kind_local')  (Enter)"
    Write-Host "  [2] $(T 'kind_publish')"
    $choice = Read-Host (T "kind_prompt")
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return "local"
    }
    $parsed = Resolve-Kind $choice
    if ($parsed -in @("local", "publish")) {
        return $parsed
    }
    if ($parsed -eq "exit") {
        return "exit"
    }
    Write-Warn (T "kind_local")
    return "local"
}

# --- FFmpeg ---

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
            Write-Info (T "winget_install")
            & winget install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
                return $true
            }
            Write-Warn "winget exit $LASTEXITCODE"
        }
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            $hadInstaller = $true
            Write-Info (T "choco_install")
            & choco install ffmpeg -y
            return $LASTEXITCODE -eq 0
        }
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            $hadInstaller = $true
            Write-Info (T "scoop_install")
            & scoop install ffmpeg
            return $LASTEXITCODE -eq 0
        }
    } finally {
        $ErrorActionPreference = $prev
    }
    if (-not $hadInstaller) {
        Write-Warn (T "no_pkg_mgr")
    }
    return $false
}

function Ensure-Ffmpeg {
    if (Test-FfmpegReady) {
        return
    }
    Write-Warn (T "ffmpeg_missing")
    if (-not (Test-InteractivePrompt)) {
        Write-Warn (T "ffmpeg_no_tty")
        return
    }
    if (-not (Confirm-Yes (T "ffmpeg_ask"))) {
        Write-Warn (T "ffmpeg_skip")
        return
    }
    if (-not (Invoke-FfmpegInstaller)) {
        Write-Warn (T "ffmpeg_fail")
        return
    }
    Sync-SessionPath
    $bin = Find-FfmpegBinDirectory
    if ($bin) {
        $env:Path = "$bin;$env:Path"
    }
    if (Test-FfmpegReady) {
        Write-Info (T "ffmpeg_ready" @((Get-Command ffmpeg).Source))
        return
    }
    Write-Warn (T "ffmpeg_path")
}

# --- infra / API ---

function Test-DockerReady {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        docker info 1>$null 2>$null
        return $LASTEXITCODE -eq 0
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Start-DockerDesktop {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Docker\Docker\Docker Desktop.exe")
        (Join-Path $env:LOCALAPPDATA "Docker\Docker Desktop.exe")
    )
    foreach ($exe in $candidates) {
        if ($exe -and (Test-Path -LiteralPath $exe)) {
            Write-Info (T "docker_open")
            Start-Process -FilePath $exe | Out-Null
            return
        }
    }
}

function Ensure-Docker {
    if (Test-DockerReady) {
        return
    }
    Write-Warn (T "docker_down")
    if (-not (Test-InteractivePrompt)) {
        throw (T "docker_no_tty")
    }
    if (-not (Confirm-Yes (T "docker_wait_ask"))) {
        throw (T "docker_down")
    }
    Start-DockerDesktop
    Write-Info (T "docker_wait")
    $lastTick = Get-Date
    while (-not (Test-DockerReady)) {
        Start-Sleep -Seconds 3
        if (((Get-Date) - $lastTick).TotalSeconds -ge 15) {
            Write-Info (T "docker_wait_tick")
            $lastTick = Get-Date
        }
    }
    Write-Info (T "docker_ready")
}

function Start-Infra {
    Write-Info (T "infra_start")
    Ensure-Docker
    docker compose --env-file .env up -d
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed"
    }
    Write-Info (T "infra_wait")
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
    throw (T "infra_fail")
}

function Wait-Api {
    Write-Info (T "api_wait" @($HealthUrl))
    $deadline = (Get-Date).AddSeconds(90)
    do {
        try {
            $r = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 300) {
                Write-Info (T "api_ok")
                return
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    } while ((Get-Date) -lt $deadline)
    throw (T "api_fail" @($HealthUrl))
}

function Start-ApiLocal {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    Write-Info (T "api_local")
    $cmd = @"
`$Host.UI.RawUI.WindowTitle = 'Music Anti Blur — API'
Set-Location -LiteralPath '$Root'
`$env:ASPNETCORE_ENVIRONMENT='Development'
dotnet run --project '$ApiProject'
"@
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoExit", "-Command", $cmd) -PassThru
    Set-Content -Path (Join-Path $RunDir "api.pid") -Value $proc.Id -Encoding ASCII
}

function Start-ApiPublish {
    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    $out = Join-Path $RunDir "api"
    Write-Info (T "publish_build" @($out))
    dotnet publish $ApiProject -c Release -o $out --nologo
    if ($LASTEXITCODE -ne 0) {
        throw (T "publish_fail")
    }
    Write-Info (T "api_publish")
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

# --- Flutter devices ---

function Out-ObjectArray {
    param($Items)
    $copy = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Items) {
        foreach ($item in $Items) {
            [void]$copy.Add($item)
        }
    }
    , $copy.ToArray()
}

function Get-FlutterDeviceRows {
    $rows = New-Object System.Collections.Generic.List[object]
    if (Get-Command flutter -ErrorAction SilentlyContinue) {
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
    }
    Out-ObjectArray $rows
}

function Get-AndroidEmulatorDeviceId {
    foreach ($row in (Get-FlutterDeviceRows)) {
        if ($row.Id -match '^emulator-\d+$') {
            return $row.Id
        }
    }
    return $null
}

function Get-UsbAndroidDeviceIds {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($row in (Get-FlutterDeviceRows)) {
        $id = [string]$row.Id
        $plat = [string]$row.Platform
        if ($id -match '^emulator-\d+$') {
            continue
        }
        if ($id -in @("chrome", "windows", "edge", "linux", "macos", "web-server")) {
            continue
        }
        if ($plat -match 'android' -or $id -match '^[0-9a-fA-F]{6,}$' -or $row.Name -match 'android|phone|pixel|samsung|xiaomi') {
            [void]$list.Add($row)
        }
    }
    Out-ObjectArray $list
}

function Get-FirstAndroidAvdId {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        return $null
    }
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
        throw (T "emu_exe_missing" @($exe))
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

function Start-AndroidEmulatorIfNeeded {
    if (Get-AndroidEmulatorDeviceId) {
        Write-Info (T "emu_already")
        return
    }
    $avdId = Get-FirstAndroidAvdId
    if (-not $avdId) {
        throw (T "emu_none")
    }
    $avdHome = Join-Path $env:USERPROFILE ".android\avd"
    $free = Get-PathFreeGigabytes $avdHome
    if ($null -ne $free -and $free -lt 6) {
        Write-Warn (T "emu_disk_warn" @($free))
        Write-Warn (T "emu_disk_hint" @($avdHome))
        if ($free -lt 2) {
            throw (T "emu_disk_fail" @($free, $avdId))
        }
    }
    $exe = Get-AndroidEmulatorExe
    Write-Info (T "emu_start" @($avdId))
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
        $msg = T "emu_fail" @($avdId, $proc.ExitCode)
        if ($fatal.Count -gt 0) {
            $msg += " " + (($fatal | ForEach-Object { $_.Trim() }) -join " ")
        }
        throw $msg
    }
}

function Wait-AndroidEmulatorDevice {
    Write-Info (T "emu_wait")
    $deadline = (Get-Date).AddSeconds(120)
    do {
        $id = Get-AndroidEmulatorDeviceId
        if ($id) {
            Write-Info (T "emu_found" @($id))
            return $id
        }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    throw (T "emu_timeout")
}

function Get-DeviceMenuOptions([bool]$ExcludeEmulator) {
    $opts = New-Object System.Collections.Generic.List[object]
    [void]$opts.Add([pscustomobject]@{ Key = "none"; Label = "$(T 'device_none') ($(T 'device_default_hint'))"; Resolve = "none" })

    if (Get-Command flutter -ErrorAction SilentlyContinue) {
        $rows = Get-FlutterDeviceRows
        $ids = @($rows | ForEach-Object { $_.Id })

        if ($ids -contains "chrome") {
            [void]$opts.Add([pscustomobject]@{ Key = "chrome"; Label = T "device_chrome"; Resolve = "chrome" })
        }
        if ($ids -contains "windows") {
            [void]$opts.Add([pscustomobject]@{ Key = "windows"; Label = T "device_windows"; Resolve = "windows" })
        }

        if (-not $ExcludeEmulator) {
            $runningEmu = Get-AndroidEmulatorDeviceId
            if ($runningEmu) {
                [void]$opts.Add([pscustomobject]@{
                        Key     = "emulator"
                        Label   = (T "device_emulator_run" @($runningEmu))
                        Resolve = $runningEmu
                    })
            } elseif (Get-FirstAndroidAvdId) {
                [void]$opts.Add([pscustomobject]@{
                        Key     = "emulator"
                        Label   = T "device_emulator_start"
                        Resolve = "emulator:launch"
                    })
            }
        }

        foreach ($usb in (Get-UsbAndroidDeviceIds)) {
            [void]$opts.Add([pscustomobject]@{
                    Key     = $usb.Id
                    Label   = (T "device_usb" @("$($usb.Name) ($($usb.Id))"))
                    Resolve = $usb.Id
                })
        }
    }

    Out-ObjectArray $opts
}

function Resolve-DeviceToken([string]$Token, [bool]$AllowEmulator) {
    if ([string]::IsNullOrWhiteSpace($Token) -or $Token.Trim().ToLowerInvariant() -in @("none", "0", "-")) {
        return "none"
    }
    $t = $Token.Trim()
    $tl = $t.ToLowerInvariant()
    if ($tl -eq "chrome") { return "chrome" }
    if ($tl -eq "windows") { return "windows" }
    if ($tl -eq "emulator") {
        if (-not $AllowEmulator) {
            throw (T "emulator_once")
        }
        return "emulator:launch"
    }
    if ($t -match '^emulator-\d+$') {
        if (-not $AllowEmulator) {
            throw (T "emulator_once")
        }
        return $t
    }
    return $t
}

function Choose-DeviceSlot([int]$SlotNumber, [bool]$ExcludeEmulator) {
    $paramVal = if ($SlotNumber -eq 1) { $Device1 } else { $Device2 }
    if ($paramVal) {
        return Resolve-DeviceToken $paramVal (-not $ExcludeEmulator)
    }
    if (-not (Test-InteractivePrompt)) {
        return "none"
    }

    $opts = Get-DeviceMenuOptions $ExcludeEmulator
    Write-Host ""
    Write-Host "$(T 'device_slot') #$SlotNumber"
    for ($i = 0; $i -lt $opts.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f $i, $opts[$i].Label)
    }
    $choice = Read-Host (T "device_prompt")
    if ([string]::IsNullOrWhiteSpace($choice)) {
        return "none"
    }
    if ($choice -match '^\d+$') {
        $idx = [int]$choice
        if ($idx -ge 0 -and $idx -lt $opts.Count) {
            return [string]$opts[$idx].Resolve
        }
    }
    $byKey = $opts | Where-Object { $_.Key -eq $choice -or $_.Resolve -eq $choice } | Select-Object -First 1
    if ($byKey) {
        return [string]$byKey.Resolve
    }
    return Resolve-DeviceToken $choice (-not $ExcludeEmulator)
}

function Expand-DeviceChoice([string]$Choice) {
    if ($Choice -eq "none" -or [string]::IsNullOrWhiteSpace($Choice)) {
        return $null
    }
    if ($Choice -eq "emulator:launch" -or $Choice -eq "emulator") {
        Start-AndroidEmulatorIfNeeded
        return Wait-AndroidEmulatorDevice
    }
    if ($Choice -eq "chrome") {
        $rows = Get-FlutterDeviceRows
        if (-not ($rows | Where-Object { $_.Id -eq "chrome" })) {
            throw (T "chrome_missing")
        }
        return "chrome"
    }
    return $Choice
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
        [void]$lines.Add("if (`$LASTEXITCODE -ne 0) { Write-Host 'flutter pub get failed.' -ForegroundColor Red; pause; exit `$LASTEXITCODE }")
    }
    [void]$lines.Add("flutter run --device-id=$DeviceId")
    Start-PowerShellWindow -Title $Title -PidName $PidName -ScriptBody ($lines -join "`r`n")
}

function Test-PubNetwork {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -sI --max-time 5 --connect-timeout 5 https://pub.dev 1>$null 2>$null
            return $LASTEXITCODE -eq 0
        }
        $req = [System.Net.HttpWebRequest]::Create("https://pub.dev")
        $req.Method = "HEAD"
        $req.Timeout = 5000
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch {
        return $false
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Invoke-FlutterPubGet {
    if (-not (Test-PubNetwork)) {
        Write-Warn (T "flutter_pub_offline")
        return
    }
    Write-Info (T "flutter_pub")
    Push-Location $MobileDir
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) {
            if (-not (Test-PubNetwork)) {
                Write-Warn (T "flutter_pub_offline")
                return
            }
            throw (T "flutter_pub_fail")
        }
    } finally {
        Pop-Location
    }
}

function Start-FlutterDev {
    param([string[]]$DeviceIds = @())

    $ids = @($DeviceIds | Where-Object { $_ -and $_ -ne "none" })
    if ($ids.Count -eq 0) {
        return
    }

    New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
    Invoke-FlutterPubGet

    $slot = 0
    foreach ($id in $ids) {
        $slot++
        if ($id -match '\s') {
            throw (T "flutter_bad_id" @($id))
        }
        Write-Info (T "flutter_start" @($id))
        $safe = $id -replace '[^\w.-]', '-'
        Start-FlutterWindow -Title "Music Anti Blur — Flutter ($id)" -DeviceId $id -PidName "flutter-$slot-$safe.pid" -RunPubGet $false
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
    Out-ObjectArray $addrs
}

function Try-AdbReverse {
    if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
        Write-Warn (T "adb_missing")
        return
    }
    $lines = @(& adb devices 2>$null)
    $ready = @($lines | Where-Object { $_ -match '\tdevice$' })
    if ($ready.Count -eq 0) {
        Write-Warn (T "adb_no_device")
        return
    }
    & adb reverse tcp:5080 tcp:5080 | Out-Null
    & adb reverse tcp:9000 tcp:9000 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn (T "adb_reverse_fail")
        return
    }
    Write-Info (T "adb_reverse_ok")
}

function Write-PhoneHints {
    Write-Host ""
    Write-Host (T "phone_header") -ForegroundColor DarkGray
    Write-Host (T "phone_apk_default") -ForegroundColor DarkGray
    Write-Host (T "phone_build") -ForegroundColor DarkGray
    $ips = Get-LanIPv4
    if ($ips.Count -eq 0) {
        Write-Host "    flutter build apk --release --dart-define=API_BASE_URL=http://<LAN-IP>:5080" -ForegroundColor DarkGray
    } else {
        foreach ($ip in $ips) {
            Write-Host "    flutter build apk --release --dart-define=API_BASE_URL=http://${ip}:5080" -ForegroundColor DarkGray
        }
    }
    Write-Host (T "phone_usb") -ForegroundColor DarkGray
    Write-Host (T "phone_usb_then") -ForegroundColor DarkGray
    Try-AdbReverse
}

function Test-IsUsbDeviceId([string]$Id) {
    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    if ($Id -in @("chrome", "windows", "none") -or $Id -match '^emulator' ) { return $false }
    foreach ($usb in (Get-UsbAndroidDeviceIds)) {
        if ($usb.Id -eq $Id) { return $true }
    }
    return $false
}

# --- main ---

$script:UiLang = Choose-Language
Assert-Command docker
Assert-Command dotnet
Ensure-DotEnv

$kindRaw = Choose-Kind
if ($kindRaw -eq "exit") {
    Write-Info (T "exit")
    exit 0
}

# Map legacy aliases to local + devices
$kind = $kindRaw
$presetDevices = @()
if ($kindRaw -eq "dual") {
    $kind = "local"
    $presetDevices = @("chrome", "emulator:launch")
} elseif ($kindRaw -eq "api") {
    $kind = "local"
    $presetDevices = @("none", "none")
} elseif ($kindRaw -eq "deploy") {
    $kind = "publish"
}

$deviceChoices = @("none", "none")
if ($kind -eq "local") {
    if ($presetDevices.Count -eq 2 -and -not $Device1 -and -not $Device2 -and $Mode) {
        $deviceChoices = $presetDevices
    } else {
        $d1 = Choose-DeviceSlot 1 $false
        $excludeEmu = ($d1 -eq "emulator:launch" -or $d1 -eq "emulator" -or $d1 -match '^emulator-\d+$')
        $d2 = Choose-DeviceSlot 2 $excludeEmu
        $deviceChoices = @($d1, $d2)
    }
}

$needFlutter = $false
foreach ($d in $deviceChoices) {
    if ($d -and $d -ne "none") {
        $needFlutter = $true
        break
    }
}
if ($needFlutter) {
    Assert-Command flutter
}

Ensure-Ffmpeg

Write-Host ""
if ($kind -eq "publish") {
    Write-Info (T "mode_publish")
    Write-Warn (T "publish_warn")
} else {
    Write-Info (T "mode_local")
    if (-not $needFlutter) {
        Write-Info (T "no_flutter")
    }
}

Start-Infra

if ($kind -eq "publish") {
    Start-ApiPublish
} else {
    Start-ApiLocal
}

Wait-Api

if ($kind -eq "local") {
    $doSeed = $true
    if (Test-InteractivePrompt) {
        $doSeed = Confirm-Yes (T "seed_ask")
    }
    if ($doSeed) {
        $seedScript = Join-Path $DevopsRoot "seed-local-music.ps1"
        Write-Info (T "seed")
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $seedScript -ApiBase "http://127.0.0.1:5080"
        if ($LASTEXITCODE -ne 0) {
            Write-Warn (T "seed_fail" @($LASTEXITCODE))
        }
    } else {
        Write-Info (T "seed_skip")
    }
}

$resolvedIds = @()
$wantUsbHints = $false
if ($kind -eq "local" -and $needFlutter) {
    foreach ($choice in $deviceChoices) {
        $id = Expand-DeviceChoice $choice
        if ($id) {
            $resolvedIds += $id
            if (Test-IsUsbDeviceId $id) {
                $wantUsbHints = $true
            }
        }
    }
    Start-FlutterDev -DeviceIds $resolvedIds
}

Write-Host ""
Write-Host "HTTP API     http://127.0.0.1:5080" -ForegroundColor DarkGray
Write-Host "Swagger      http://127.0.0.1:5080/swagger  (Development)" -ForegroundColor DarkGray
Write-Host "MailHog      http://127.0.0.1:8025" -ForegroundColor DarkGray
Write-Host "MinIO S3     http://127.0.0.1:9000" -ForegroundColor DarkGray
Write-Host "MinIO UI     http://127.0.0.1:9001  (minio / minio-local-only)" -ForegroundColor DarkGray
Write-Host "Hangfire     http://127.0.0.1:5080/hangfire" -ForegroundColor DarkGray

if ($wantUsbHints -or (-not $needFlutter -and $kind -eq "local")) {
    Write-PhoneHints
}

if ($needFlutter) {
    Write-Info (T "done_clients")
} else {
    Write-Info (T "done_server")
}
