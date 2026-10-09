<#
.SYNOPSIS
    Start, stop, and check the status of HotelApp's services -- individually or in any
    combination -- without re-deriving the startup order and the machine-specific traps
    documented in shared/local-integration-guide.md every time.

.DESCRIPTION
    Services this script knows about:
        postgres    Native PostgreSQL 18.6 Windows service (:5432). Never stopped by this
                    script -- it's a persistent system service, not a per-demo process.
        springboot  hotelapp-server-springboot, :8080
        nodejs      hotelapp-server-nodejs, :3000
        react       hotelapp-client-react, :5173
        angular     hotelapp-client-angular, :4200
        aidb        The AI service's Docker infrastructure only (pgvector-enabled Postgres
                    on :5433 + its two Flyway migrations) -- not the AI app process itself.
        ai          hotelapp-ai-service, :8000. Starting it also ensures `aidb` is up first.

    Started processes are backgrounded (hidden) by default, with output captured to
    scripts/logs/<service>.log. Pass -Visible to instead open each one in its own labeled,
    visible PowerShell window you can tile on screen for a live demo -- output still also
    goes to the same log file either way.

.EXAMPLE
    .\services.ps1 start -All
    One backend (Spring Boot), one frontend (React), the AI service, hidden.

.EXAMPLE
    .\services.ps1 start -Services react,angular,springboot -Visible
    Both frontends side by side against one shared backend, for an interview demo where you
    want to show the UI in React and Angular in two windows at once -- each in its own
    visible, labeled terminal.

.EXAMPLE
    .\services.ps1 start -All -Backend nodejs -Frontend angular
    Same idea as -All, but picking the other backend/frontend.

.EXAMPLE
    .\services.ps1 stop -All
    Stops everything this script started, in reverse order. Leaves native PostgreSQL running
    and leaves any AI Docker infrastructure (`aidb`) up -- both are deliberate; see below.

.EXAMPLE
    .\services.ps1 stop -Services aidb
    Explicitly tears down the AI service's Docker containers (keeps the data volume). Separate
    from `stop ai`, which only stops the AI app process -- so stopping the AI service for the
    day doesn't force a re-migration next time you need it.

.EXAMPLE
    .\services.ps1 status
    What's actually running right now, with live health-check results, not assumptions.

.EXAMPLE
    .\services.ps1 logs springboot -Follow
    Tail a service's log live, whether it's running hidden or visible.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('start', 'stop', 'status', 'logs', 'help')]
    [string]$Action = 'help',

    [ValidateSet('postgres', 'springboot', 'nodejs', 'react', 'angular', 'aidb', 'ai')]
    [string[]]$Services,

    [switch]$All,

    [ValidateSet('springboot', 'nodejs')]
    [string]$Backend = 'springboot',

    [ValidateSet('react', 'angular')]
    [string]$Frontend = 'react',

    [switch]$NoAi,

    [switch]$Visible,

    # For `logs <service>` -- not validated against the same set above because it's a single
    # positional value here, not a list.
    [Parameter(Position = 1)]
    [string]$Service,

    [switch]$Follow
)

$ErrorActionPreference = 'Stop'

# --- Paths -------------------------------------------------------------------------------
# This script lives at <hotelapp>/hotelapp-context/scripts/services.ps1, so two levels up is
# the folder all six repos are siblings under. Resolving from $PSScriptRoot rather than a
# hardcoded path keeps this working if the whole `hotelapp` folder is ever moved or cloned
# somewhere else, which a hardcoded C:\Users\Jeff\... path would silently break.
$ScriptDir    = $PSScriptRoot
$ContextRoot  = Split-Path -Parent $ScriptDir
$HotelAppRoot = Split-Path -Parent $ContextRoot
$LogDir       = Join-Path $ScriptDir 'logs'
$StateFile    = Join-Path $ScriptDir '.run-state.json'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

# --- The one genuinely per-machine override -----------------------------------------------
# Confirmed on this machine 2026-10-09 (see local-integration-guide.md): $env:JAVA_HOME
# defaults to a JDK 23 install, newer than the pom's pinned Java 21, and Maven is not on
# PATH at all. A different machine may need neither of these -- if `mvn -v` already resolves
# and reports Java 21 on yours, this block is harmless to leave as-is; Start-Process below
# only uses it for the springboot command specifically.
$JavaHomeOverride = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'
$MavenBinOverride  = 'C:\Users\Jeff\tools\apache-maven-3.9.16\bin'
$DockerDesktopExe  = 'C:\Users\Jeff\AppData\Local\Programs\DockerDesktop\Docker Desktop.exe'

# --- Service registry ----------------------------------------------------------------------
# Order here is display order for `status`, not start order (see $StartPriority below).
function Get-Registry {
    [ordered]@{
        postgres = @{
            Kind        = 'windows-service'
            ServiceName = 'postgresql-x64-18'
            Port        = 5432
        }
        springboot = @{
            Kind      = 'process'
            Port      = 8080
            HealthUrl = 'http://localhost:8080/api/v1/health'
            WorkDir   = Join-Path $HotelAppRoot 'hotelapp-server-springboot'
            Command   = "`$env:JAVA_HOME = '$JavaHomeOverride'; `$env:Path = `"$MavenBinOverride;`$env:JAVA_HOME\bin;`$env:Path`"; mvn spring-boot:run"
        }
        nodejs = @{
            Kind      = 'process'
            Port      = 3000
            HealthUrl = 'http://localhost:3000/api/v1/health'
            WorkDir   = Join-Path $HotelAppRoot 'hotelapp-server-nodejs'
            Command   = 'npm run dev'
        }
        react = @{
            Kind      = 'process'
            Port      = 5173
            HealthUrl = 'http://localhost:5173/'
            WorkDir   = Join-Path $HotelAppRoot 'hotelapp-client-react'
            Command   = 'npm run dev'
        }
        angular = @{
            Kind      = 'process'
            Port      = 4200
            HealthUrl = 'http://localhost:4200/'
            WorkDir   = Join-Path $HotelAppRoot 'hotelapp-client-angular'
            Command   = 'npm start'
        }
        aidb = @{
            Kind       = 'docker'
            ComposeDir = Join-Path $ContextRoot 'docker'
            # --wait is load-bearing: without it, `docker compose up -d` can return as soon as
            # containers are *started*, not once db is healthy and both Flyway runs have
            # actually exited 0 -- which would make this script lie about readiness.
            UpArgs     = @('compose', '--profile', 'ai', 'up', '-d', '--wait', 'db', 'flyway', 'flyway-ai')
            DownArgs   = @('compose', '--profile', 'ai', 'down')
        }
        ai = @{
            Kind      = 'process'
            Port      = 8000
            HealthUrl = 'http://localhost:8000/api/v1/assistant/health'
            WorkDir   = Join-Path $HotelAppRoot 'hotelapp-ai-service'
            Command   = 'uv run hotelapp-ai serve'
            DependsOn = @('aidb')
        }
    }
}

# Start order (low to high) and its reverse for stop. Fixed, not caller-controlled, so a
# request like `start -Services ai,react,springboot` still comes up in a safe order instead
# of literally the order typed.
$StartPriority = @{ postgres = 0; aidb = 1; springboot = 2; nodejs = 2; react = 3; angular = 3; ai = 4 }

# --- State file (PID bookkeeping; port checks remain the source of truth) ------------------
function Read-State {
    if (Test-Path $StateFile) {
        try { return Get-Content $StateFile -Raw | ConvertFrom-Json -AsHashtable } catch { return @{} }
    }
    return @{}
}
function Write-State($state) {
    ($state | ConvertTo-Json -Depth 4) | Set-Content -Path $StateFile -Encoding utf8
}

# --- Low-level checks -----------------------------------------------------------------------
function Get-PortOwner([int]$Port) {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($conn) { return $conn.OwningProcess }
    return $null
}

function Test-HealthUrl([string]$Url) {
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        return @{ Ok = $true; Status = $resp.StatusCode; Body = $resp.Content }
    } catch {
        return @{ Ok = $false; Status = $null; Body = $null }
    }
}

function Test-DockerReady {
    try { docker info *> $null; return $true } catch { return $false }
}

function Wait-ForDockerDesktop {
    if (Test-DockerReady) { return $true }
    Write-Host "Docker Desktop isn't responding -- launching it..." -ForegroundColor Yellow
    if (Test-Path $DockerDesktopExe) {
        Start-Process -FilePath $DockerDesktopExe | Out-Null
    } else {
        Write-Host "  Could not find Docker Desktop at '$DockerDesktopExe' -- start it yourself." -ForegroundColor Red
        return $false
    }
    Write-Host "  Waiting for the Docker engine (this can take a few minutes)..." -NoNewline
    for ($i = 0; $i -lt 60; $i++) {
        if (Test-DockerReady) { Write-Host " ready." -ForegroundColor Green; return $true }
        Start-Sleep -Seconds 5
        Write-Host "." -NoNewline
    }
    Write-Host ""
    Write-Host "  Docker still isn't responding after 5 minutes -- check it manually." -ForegroundColor Red
    return $false
}

# --- Start / stop one named service ---------------------------------------------------------
function Start-Service1([string]$Name, [hashtable]$Registry, [switch]$VisibleMode) {
    $def = $Registry[$Name]

    switch ($def.Kind) {
        'windows-service' {
            $svc = Get-Service -Name $def.ServiceName -ErrorAction SilentlyContinue
            if ($null -eq $svc) { Write-Host "[$Name] service '$($def.ServiceName)' not found." -ForegroundColor Red; return }
            if ($svc.Status -eq 'Running') { Write-Host "[$Name] already running." -ForegroundColor DarkGray; return }
            Start-Service -Name $def.ServiceName
            Write-Host "[$Name] started." -ForegroundColor Green
            return
        }
        'docker' {
            if (-not (Wait-ForDockerDesktop)) { return }
            Write-Host "[$Name] bringing up Docker infrastructure (db + migrations)..." -ForegroundColor Cyan
            Push-Location $def.ComposeDir
            try {
                & docker @($def.UpArgs)
                if ($LASTEXITCODE -ne 0) { Write-Host "[$Name] docker compose failed (exit $LASTEXITCODE)." -ForegroundColor Red; return }
                Write-Host "[$Name] db + migrations ready." -ForegroundColor Green
            } finally { Pop-Location }
            return
        }
        'process' {
            if ($def.DependsOn) {
                foreach ($dep in $def.DependsOn) { Start-Service1 -Name $dep -Registry $Registry -VisibleMode:$VisibleMode }
            }
            $owner = Get-PortOwner -Port $def.Port
            if ($owner) {
                Write-Host "[$Name] already running on port $($def.Port) (PID $owner) -- skipping." -ForegroundColor DarkGray
                return
            }
            if ($Name -eq 'ai') {
                $backendUp = (Get-PortOwner -Port 8080) -or (Get-PortOwner -Port 3000)
                if (-not $backendUp) {
                    Write-Host "[$Name] warning: no backend detected on :8080 or :3000 yet -- the AI service will report backend DOWN until one is started." -ForegroundColor Yellow
                }
            }

            $log = Join-Path $LogDir "$Name.log"
            $windowTitle = "HotelApp - $Name"
            # [Console]::OutputEncoding fixes mangled Unicode (Vite's checkmarks, etc.) in both
            # the log file and a -Visible window -- PowerShell's console default encoding on
            # Windows otherwise garbles anything a child tool writes as UTF-8.
            #
            # Written to a temp .ps1 and launched with -File, not passed inline via -Command:
            # Start-Process -ArgumentList in Windows PowerShell 5.1 does NOT quote array
            # elements that contain spaces/semicolons, so a multi-statement -Command string
            # arrives at the child process mangled (confirmed 2026-10-09 -- it silently never
            # ran at all, no log file, no error). -File with a real path sidesteps that
            # quoting entirely.
            $inner = @(
                "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8"
                "`$Host.UI.RawUI.WindowTitle = '$windowTitle'"
                "Set-Location '$($def.WorkDir)'"
                "$($def.Command) 2>&1 | Tee-Object -FilePath '$log'"
            ) -join "`r`n"
            $runnerScript = Join-Path $LogDir "$Name.run.ps1"
            Set-Content -Path $runnerScript -Value $inner -Encoding utf8

            $style = if ($VisibleMode) { 'Normal' } else { 'Hidden' }

            $proc = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList @('-NoLogo', '-NoExit', '-File', $runnerScript) `
                -WindowStyle $style `
                -PassThru

            $state = Read-State
            $state[$Name] = @{ LauncherPid = $proc.Id; Port = $def.Port; StartedAt = (Get-Date).ToString('o'); Visible = [bool]$VisibleMode }
            Write-State $state

            Write-Host "[$Name] starting (launcher PID $($proc.Id), log: $log)..." -ForegroundColor Cyan
            if ($def.HealthUrl) {
                Write-Host "  waiting for $($def.HealthUrl) ..." -NoNewline
                $ok = $false
                for ($i = 0; $i -lt 24; $i++) {
                    Start-Sleep -Seconds 2
                    $h = Test-HealthUrl -Url $def.HealthUrl
                    if ($h.Ok) { $ok = $true; break }
                    Write-Host "." -NoNewline
                }
                if ($ok) { Write-Host " up." -ForegroundColor Green }
                else { Write-Host " not responding yet -- check '$log' or run 'status'." -ForegroundColor Yellow }
            }
            return
        }
    }
}

function Stop-Service1([string]$Name, [hashtable]$Registry) {
    $def = $Registry[$Name]
    switch ($def.Kind) {
        'windows-service' {
            Write-Host "[$Name] left running on purpose -- it's a shared system service, not a per-demo process." -ForegroundColor DarkGray
            return
        }
        'docker' {
            Write-Host "[$Name] tearing down Docker infrastructure (keeping the data volume)..." -ForegroundColor Cyan
            Push-Location $def.ComposeDir
            try { & docker @($def.DownArgs) } finally { Pop-Location }
            Write-Host "[$Name] down." -ForegroundColor Green
            return
        }
        'process' {
            $owner = Get-PortOwner -Port $def.Port
            $state = Read-State
            $launcherPid = if ($state.ContainsKey($Name)) { $state[$Name].LauncherPid } else { $null }

            if (-not $owner -and -not $launcherPid) {
                Write-Host "[$Name] not running." -ForegroundColor DarkGray
                return
            }
            if ($owner) {
                Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue
            }
            if ($launcherPid) {
                # Also stop the wrapper shell and anything it spawned (npm/mvn/uv often launch
                # a child process tree; the port owner above is usually the real server, but
                # this catches a lingering parent wrapper too).
                Get-CimInstance Win32_Process -Filter "ParentProcessId=$launcherPid" -ErrorAction SilentlyContinue |
                    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                Stop-Process -Id $launcherPid -Force -ErrorAction SilentlyContinue
            }
            if ($state.ContainsKey($Name)) { $state.Remove($Name); Write-State $state }
            Write-Host "[$Name] stopped." -ForegroundColor Green
            return
        }
    }
}

# --- Status ----------------------------------------------------------------------------------
function Show-Status([hashtable]$Registry) {
    $rows = foreach ($name in $Registry.Keys) {
        $def = $Registry[$name]
        $row = [ordered]@{ Service = $name; Port = $def.Port; State = 'stopped'; PID = ''; Health = '' }
        switch ($def.Kind) {
            'windows-service' {
                $svc = Get-Service -Name $def.ServiceName -ErrorAction SilentlyContinue
                $row.State = if ($svc -and $svc.Status -eq 'Running') { 'running' } else { 'stopped' }
                $row.Health = 'n/a'
            }
            'docker' {
                Push-Location $def.ComposeDir
                try {
                    $running = & docker compose --profile ai ps --status running --format '{{.Name}}' 2>$null
                } finally { Pop-Location }
                $row.State = if ($running) { 'running' } else { 'stopped' }
                $row.Health = 'n/a'
            }
            'process' {
                $owner = Get-PortOwner -Port $def.Port
                if ($owner) {
                    $row.State = 'running'
                    $row.PID = $owner
                    if ($def.HealthUrl) {
                        $h = Test-HealthUrl -Url $def.HealthUrl
                        $row.Health = if ($h.Ok) { "OK ($($h.Status))" } else { 'DOWN' }
                    } else {
                        $row.Health = 'n/a'
                    }
                }
            }
        }
        [PSCustomObject]$row
    }
    $rows | Format-Table -AutoSize
}

# --- Logs ------------------------------------------------------------------------------------
function Show-Logs([string]$Name, [switch]$FollowMode) {
    $log = Join-Path $LogDir "$Name.log"
    if (-not (Test-Path $log)) { Write-Host "No log yet for '$Name' (looked at $log)." -ForegroundColor Yellow; return }
    if ($FollowMode) { Get-Content -Path $log -Tail 20 -Wait }
    else { Get-Content -Path $log -Tail 40 }
}

# --- Expand -All / -Services into an ordered, deduplicated list ------------------------------
function Expand-Targets {
    if ($All) {
        $targets = @('postgres', $Backend, $Frontend)
        if (-not $NoAi) { $targets += 'ai' }
        return $targets
    }
    if ($Services) { return $Services }
    return @()
}

function Sort-ByPriority([string[]]$Names, [bool]$Reverse) {
    $sorted = $Names | Sort-Object -Property @{ Expression = { $StartPriority[$_] } }
    if ($Reverse) { [array]::Reverse($sorted) }
    return $sorted
}

# --- Usage -----------------------------------------------------------------------------------
function Show-Help {
    Get-Help $PSCommandPath -Full | Out-Host
}

# --- Dispatch ----------------------------------------------------------------------------------
$Registry = Get-Registry

switch ($Action) {
    'help' { Show-Help }

    'start' {
        $targets = Expand-Targets
        if (-not $targets) { Write-Host "Specify -All or -Services <name,name,...>." -ForegroundColor Red; Show-Help; break }
        foreach ($name in (Sort-ByPriority -Names $targets -Reverse $false)) {
            Start-Service1 -Name $name -Registry $Registry -VisibleMode:$Visible
        }
    }

    'stop' {
        if ($All) {
            # Deliberately every process-kind service, not just the -All *start* defaults --
            # e.g. if you started both frontends (one via -All, one via an extra -Services
            # call), `stop -All` should still stop both, not just the one -All would have
            # started. `postgres` and `aidb` are excluded on purpose: a shared system service
            # and persisted Docker data respectively -- neither is a per-demo process. An
            # explicit `-Services aidb` is the only way to tear down the AI Docker infra.
            $targets = $Registry.Keys | Where-Object { $Registry[$_].Kind -eq 'process' }
        } elseif ($Services) {
            $targets = $Services
        } else {
            Write-Host "Specify -All or -Services <name,name,...>." -ForegroundColor Red; Show-Help; break
        }
        foreach ($name in (Sort-ByPriority -Names $targets -Reverse $true)) {
            Stop-Service1 -Name $name -Registry $Registry
        }
    }

    'status' { Show-Status -Registry $Registry }

    'logs' {
        if (-not $Service) { Write-Host "Usage: services.ps1 logs <service> [-Follow]" -ForegroundColor Red; break }
        Show-Logs -Name $Service -FollowMode:$Follow
    }
}
