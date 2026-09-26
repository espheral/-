#Requires -Version 5.1
<#
.SYNOPSIS
    Auditoria de seguridad de Windows 10/11 de solo lectura.
.DESCRIPTION
    No cambia nada: solo lee estado y escribe un informe Markdown. Por defecto
    redacta IP, MAC, nombre del equipo, usuario y correos para poder compartirlo.
    Ejecutalo primero como usuario normal; como administrador anade BitLocker,
    Secure Boot, exclusiones de Defender y SMBv1.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\Audit-Windows.ps1
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\Audit-Windows.ps1 -Output .\informe.md -NoRedact
#>
[CmdletBinding()]
param(
    [string]$Output = "",
    [switch]$NoRedact
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Lines = New-Object System.Collections.Generic.List[string]
$script:Crit = 0
$script:Warn = 0

function Add-Line([string]$Text) { $script:Lines.Add($Text) }
function Add-Section([string]$Text) { Add-Line ''; Add-Line "## $Text"; Add-Line '' }
function Add-Ok([string]$Text) { Add-Line "- [OK] $Text" }
function Add-Info([string]$Text) { Add-Line "- [INFO] $Text" }
function Add-Warn([string]$Text) { $script:Warn++; Add-Line "- [AVISO] $Text" }
function Add-Crit([string]$Text) { $script:Crit++; Add-Line "- [CRÍTICO] $Text" }
function Get-Short([string]$Path) { $Path.Replace($env:USERPROFILE, '~') }
function Get-RegValue([string]$Key, [string]$Name) {
    $item = Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $item) { return $item.$Name }
    return $null
}

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $Output) {
    $Output = Join-Path (Get-Location) ("auditoria-windows-{0}-{1}.md" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
}

function Test-System {
    Add-Section 'Sistema'
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    Add-Info ("SO: {0} {1} (build {2}.{3}) · {4}" -f $os.Caption, (Get-RegValue $cv 'DisplayVersion'),
        $os.BuildNumber, (Get-RegValue $cv 'UBR'), $os.OSArchitecture)
    Add-Info ("Último arranque: {0} · administrador: {1} · PowerShell {2}" -f $os.LastBootUpTime,
        $(if ($IsAdmin) { 'sí' } else { 'no' }), $PSVersionTable.PSVersion)
    if ($os.Caption -match 'Windows 10') {
        Add-Crit 'Windows 10 está fuera de soporte desde el 14-10-2025 salvo que tengas ESU; migra a Windows 11'
    }
}

function Test-Updates {
    Add-Section 'Actualizaciones'
    $last = Get-HotFix | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($last) {
        $days = [int]((Get-Date) - $last.InstalledOn).TotalDays
        $msg = "Último parche instalado: $($last.HotFixID) hace $days días"
        if ($days -gt 45) { Add-Warn "$msg; revisa Windows Update" } else { Add-Ok $msg }
    } else {
        Add-Info 'No se pudo leer el historial de parches (Get-HotFix)'
    }
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
    if ($pending) { Add-Warn 'Reinicio pendiente para completar actualizaciones' }
}

function Test-Defender {
    Add-Section 'Microsoft Defender'
    $mp = Get-MpComputerStatus
    if (-not $mp) { Add-Warn 'No se pudo leer Defender (¿antivirus de terceros o servicio detenido?)'; return }
    if ($mp.RealTimeProtectionEnabled) { Add-Ok 'Protección en tiempo real activa' } else { Add-Crit 'Protección en tiempo real desactivada' }
    if ($mp.AntivirusSignatureAge -gt 3) { Add-Warn "Firmas con $($mp.AntivirusSignatureAge) días" } else { Add-Ok "Firmas con $($mp.AntivirusSignatureAge) días" }
    if ($mp.IsTamperProtected) { Add-Ok 'Protección contra alteraciones activa' } else { Add-Warn 'Protección contra alteraciones desactivada' }
    if ($mp.AMRunningMode -and $mp.AMRunningMode -ne 'Normal') { Add-Info "Defender en modo $($mp.AMRunningMode)" }
    $pref = Get-MpPreference
    $excl = @($pref.ExclusionPath) + @($pref.ExclusionProcess) + @($pref.ExclusionExtension) |
        Where-Object { $_ -and $_ -notlike 'N/A*' }
    if ($excl.Count -gt 0) {
        Add-Warn "Exclusiones de Defender ($($excl.Count)); cada una es un punto ciego:"
        $excl | ForEach-Object { Add-Line "    - $(Get-Short $_)" }
    } elseif (-not $IsAdmin) {
        Add-Info 'Exclusiones de Defender visibles solo como administrador'
    } else {
        Add-Ok 'Sin exclusiones de Defender'
    }
    if ($pref.PUAProtection -eq 1) { Add-Ok 'Bloqueo de aplicaciones potencialmente no deseadas activo' } else { Add-Info 'Bloqueo de PUA no activo' }
}

function Test-Firewall {
    Add-Section 'Cortafuegos'
    $profiles = Get-NetFirewallProfile
    if (-not $profiles) { Add-Info 'No se pudo leer el cortafuegos'; return }
    foreach ($p in $profiles) {
        if (-not $p.Enabled) { Add-Crit "Perfil $($p.Name) desactivado" }
        elseif ("$($p.DefaultInboundAction)" -eq 'Allow') { Add-Crit "Perfil $($p.Name) permite entrantes por defecto" }
        else { Add-Ok "Perfil $($p.Name) activo" }
    }
    $net = Get-NetConnectionProfile | Where-Object { "$($_.NetworkCategory)" -eq 'Private' }
    if ($net) { Add-Info "Redes marcadas como privadas (más permisivas): $(($net.Name) -join ', ')" }
}

function Test-Hardening {
    Add-Section 'Endurecimiento'
    $sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    if ((Get-RegValue $sys 'EnableLUA') -eq 0) { Add-Crit 'UAC desactivado' }
    elseif ((Get-RegValue $sys 'ConsentPromptBehaviorAdmin') -eq 0) { Add-Warn 'UAC eleva sin preguntar a los administradores' }
    else { Add-Ok 'UAC activo' }
    if ($IsAdmin) {
        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive
        if ($bl -and "$($bl.ProtectionStatus)" -eq 'On') { Add-Ok "BitLocker activo en $env:SystemDrive" }
        elseif ($bl) { Add-Warn "BitLocker no protege $env:SystemDrive (estado: $($bl.ProtectionStatus))" }
        else { Add-Info 'BitLocker no disponible (¿Windows Home? revisa Cifrado de dispositivo)' }
        try {
            if (Confirm-SecureBootUEFI -ErrorAction Stop) { Add-Ok 'Secure Boot activo' } else { Add-Warn 'Secure Boot desactivado' }
        } catch { Add-Info 'Secure Boot no aplicable (BIOS heredada) o no legible' }
        $smb = Get-SmbServerConfiguration
        if ($smb -and $smb.EnableSMB1Protocol) { Add-Crit 'SMBv1 habilitado' } elseif ($smb) { Add-Ok 'SMBv1 deshabilitado' }
    } else {
        Add-Info 'BitLocker, Secure Boot y SMBv1: repite como administrador'
    }
    $hvci = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    if ($hvci -eq 1) { Add-Ok 'Integridad de memoria (HVCI) activa' } else { Add-Warn 'Integridad de memoria (HVCI) desactivada' }
    if ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL') -in 1, 2) { Add-Ok 'Protección LSA activa' }
    else { Add-Info 'Protección LSA (RunAsPPL) no configurada' }
    foreach ($scope in 'LocalMachine', 'CurrentUser') {
        $pol = Get-ExecutionPolicy -Scope $scope
        if ("$pol" -in 'Unrestricted', 'Bypass') { Add-Warn "ExecutionPolicy $scope=$pol" }
    }
}

function Test-Accounts {
    Add-Section 'Cuentas y acceso remoto'
    $admins = Get-LocalGroupMember -SID 'S-1-5-32-544'
    if ($admins) { Add-Info "Administradores locales: $(($admins | ForEach-Object { $_.Name.Split('\')[-1] }) -join ', ')" }
    if ($IsAdmin) { Add-Info 'Trabajas con una sesión elevada; para el día a día conviene una cuenta estándar' }
    $builtin = Get-LocalUser | Where-Object { $_.SID.Value -like '*-500' -and $_.Enabled }
    if ($builtin) { Add-Warn 'Cuenta Administrador integrada habilitada' }
    $guest = Get-LocalUser | Where-Object { $_.SID.Value -like '*-501' -and $_.Enabled }
    if ($guest) { Add-Warn 'Cuenta Invitado habilitada' }
    if ((Get-RegValue 'HKLM:\System\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections') -eq 0) {
        $nla = Get-RegValue 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication'
        if ($nla -eq 1) { Add-Warn 'Escritorio remoto (RDP) habilitado (con NLA)' } else { Add-Crit 'Escritorio remoto (RDP) habilitado sin NLA' }
    } else { Add-Ok 'Escritorio remoto deshabilitado' }
    $sshd = Get-Service sshd
    if ($sshd -and "$($sshd.Status)" -eq 'Running') {
        $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
        $pa = Select-String -Path $cfg -Pattern '^\s*PasswordAuthentication\s+(\S+)' | Select-Object -First 1
        if ($pa -and $pa.Matches[0].Groups[1].Value -eq 'no') { Add-Ok 'OpenSSH Server activo solo con claves' }
        else { Add-Warn 'OpenSSH Server activo y admite contraseña' }
    }
    $winrm = Get-Service WinRM
    if ($winrm -and "$($winrm.Status)" -eq 'Running') { Add-Info 'WinRM en ejecución (administración remota)' }
}

function Get-PortLabel([int]$Port) {
    $map = @{ 22 = 'SSH'; 2375 = 'Docker API sin TLS'; 3000 = 'web dev/Grafana'; 3306 = 'MySQL'; 3389 = 'RDP';
        5000 = 'web dev'; 5432 = 'PostgreSQL'; 5900 = 'VNC'; 5985 = 'WinRM'; 6379 = 'Redis'; 7860 = 'Gradio';
        8080 = 'Open WebUI/web'; 8188 = 'ComfyUI'; 8888 = 'Jupyter'; 11434 = 'Ollama API'; 1234 = 'LM Studio';
        27017 = 'MongoDB' }
    if ($map.ContainsKey($Port)) { return $map[$Port] }
    return ''
}

function Test-Network {
    Add-Section 'Puertos a la escucha'
    $names = @{}
    Get-Process | ForEach-Object { $names[[int]$_.Id] = $_.ProcessName }
    $listen = Get-NetTCPConnection -State Listen | Sort-Object LocalPort, LocalAddress -Unique
    $windowsStd = 135, 139, 445, 5040, 7680
    $ephemeral = 0
    foreach ($c in $listen) {
        $port = [int]$c.LocalPort
        $addr = "$($c.LocalAddress)"
        $proc = $names[[int]$c.OwningProcess]
        $label = Get-PortLabel $port
        $desc = "TCP ${addr}:$port ($proc)$(if ($label) { " [$label]" })"
        if ($addr -in '127.0.0.1', '::1') { Add-Ok "$desc solo local"; continue }
        if ($port -ge 49152 -and -not $label) { $ephemeral++; continue }
        if ($port -eq 2375) { Add-Crit "${desc}: API de Docker sin TLS expuesta" }
        elseif ($port -in $windowsStd) { Add-Info "$desc servicio estándar de Windows; el perfil Público del cortafuegos debe bloquearlo" }
        elseif ($label) { Add-Warn "$desc escucha en $(if ($addr -in '0.0.0.0', '::') { 'todas las interfaces' } else { 'una interfaz de red' }); limita a 127.0.0.1 o filtra" }
        else { Add-Info "$desc escucha en $addr" }
    }
    if ($ephemeral -gt 0) { Add-Info "$ephemeral puertos dinámicos (RPC/aplicaciones) no detallados" }
    if (-not $listen) { Add-Info 'No se pudieron leer los puertos a la escucha' }
    $v6 = @(Get-NetIPAddress -AddressFamily IPv6 | Where-Object { "$($_.PrefixOrigin)" -in 'RouterAdvertisement', 'Dhcp' })
    if ($v6.Count -gt 0) {
        Add-Info 'Hay IPv6 global: los servicios en [::] pueden ser alcanzables desde Internet si el router no filtra entrantes'
        if ($v6 | Where-Object { "$($_.SuffixOrigin)" -eq 'Link' }) {
            Add-Warn 'IPv6 global con identificador EUI-64 (derivado de la MAC): estable y rastreable'
        }
    }
}

function Test-LocalAI {
    Add-Section 'IA local y WSL'
    $ollamaHost = @($env:OLLAMA_HOST, [Environment]::GetEnvironmentVariable('OLLAMA_HOST', 'User'),
        [Environment]::GetEnvironmentVariable('OLLAMA_HOST', 'Machine')) | Where-Object { $_ } | Select-Object -First 1
    if ($ollamaHost -and $ollamaHost -notmatch '^(127\.|localhost|\[::1\])') {
        Add-Warn "OLLAMA_HOST=$ollamaHost; la API de Ollama no tiene autenticación"
    } elseif (Get-Command ollama) { Add-Ok 'Ollama escucha solo en local (OLLAMA_HOST por defecto)' }
    else { Add-Info 'Ollama no detectado' }
    $origins = [Environment]::GetEnvironmentVariable('OLLAMA_ORIGINS', 'User')
    if ($origins -eq '*') { Add-Warn "OLLAMA_ORIGINS='*': cualquier web puede llamar a la API local" }
    if (Get-Command wsl.exe) {
        $env:WSL_UTF8 = '1'
        $distros = (wsl.exe -l -q) -replace "`0", '' | Where-Object { $_.Trim() }
        if ($distros) { Add-Info "Distribuciones WSL: $($distros -join ', '); audítalas con audit-linux.sh" }
        $wslcfg = Join-Path $env:USERPROFILE '.wslconfig'
        if (Test-Path $wslcfg) {
            $cfg = Get-Content $wslcfg -Raw
            if ($cfg -match '(?im)^\s*networkingMode\s*=\s*mirrored') { Add-Info 'WSL en modo de red mirrored: sus puertos comparten las interfaces de Windows' }
            if ($cfg -match '(?im)^\s*firewall\s*=\s*false') { Add-Warn '.wslconfig desactiva el cortafuegos de Hyper-V para WSL' }
        }
    }
}

function Read-Json([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content $Path -Raw | ConvertFrom-Json } catch { Add-Info "No se pudo interpretar $(Get-Short $Path)"; return $null }
}

function Get-Names($Obj) {
    if ($null -eq $Obj) { return @() }
    return @($Obj.PSObject.Properties | ForEach-Object { $_.Name })
}

function Test-Agents {
    Add-Section 'Claude y otros agentes'
    $claude = Get-Command claude
    if ($claude) { Add-Info "Claude Code: $(& claude --version 2>$null | Select-Object -First 1)" }
    $settings = Read-Json (Join-Path $env:USERPROFILE '.claude\settings.json')
    if ($settings) {
        $perm = $settings.permissions
        if ($perm -and $perm.defaultMode -eq 'bypassPermissions') { Add-Crit 'Claude Code: defaultMode=bypassPermissions (sin confirmaciones)' }
        $broad = @($perm.allow) | Where-Object { $_ -in 'Bash', 'Bash(*)', 'PowerShell', 'PowerShell(*)' -or $_ -like 'Bash(rm*' -or $_ -like 'Bash(curl*' }
        if ($broad) { Add-Warn "Claude Code: permisos amplios pre-aprobados: $($broad -join ', ')" }
        $hooks = Get-Names $settings.hooks
        if ($hooks.Count -gt 0) { Add-Info "Claude Code: hooks configurados ($($hooks -join ', ')); ejecutan comandos automáticamente" }
        $envSecrets = Get-Names $settings.env | Where-Object { $_ -match 'KEY|TOKEN|SECRET' }
        if ($envSecrets) { Add-Warn "Claude Code guarda secretos en settings.json: $($envSecrets -join ', ')" }
    }
    $cj = Read-Json (Join-Path $env:USERPROFILE '.claude.json')
    if ($cj) {
        $mcp = @(Get-Names $cj.mcpServers)
        if ($cj.projects) { foreach ($p in $cj.projects.PSObject.Properties) { $mcp += Get-Names $p.Value.mcpServers } }
        $mcp = $mcp | Sort-Object -Unique
        if ($mcp) { Add-Info "Claude Code: servidores MCP locales (ejecutan código con tus permisos): $($mcp -join ', ')" }
    }
    $desktop = Read-Json (Join-Path $env:APPDATA 'Claude\claude_desktop_config.json')
    if ($desktop -and $desktop.mcpServers) {
        foreach ($s in $desktop.mcpServers.PSObject.Properties) {
            $cmd = "$($s.Value.command) $(@($s.Value.args) -join ' ')".Trim()
            Add-Info "Claude Desktop MCP '$($s.Name)': $(Get-Short $cmd)"
            $secret = Get-Names $s.Value.env | Where-Object { $_ -match 'KEY|TOKEN|SECRET|PASSWORD' }
            if ($secret) { Add-Warn "Claude Desktop MCP '$($s.Name)' guarda en claro: $($secret -join ', ')" }
        }
    }
    $codex = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (Test-Path $codex) {
        $t = Get-Content $codex -Raw
        if ($t -match 'approval_policy\s*=\s*"never"') { Add-Warn 'Codex: approval_policy="never"' }
        if ($t -match 'sandbox_mode\s*=\s*"danger-full-access"') { Add-Warn 'Codex: sandbox_mode="danger-full-access"' }
    }
}

function Test-Credentials {
    Add-Section 'Credenciales en disco'
    if (Test-Path (Join-Path $env:USERPROFILE '.git-credentials')) { Add-Crit '~\.git-credentials guarda tokens Git en texto plano' }
    if (Get-Command git) {
        $helper = & git config --global credential.helper 2>$null
        if ($helper -eq 'store') { Add-Crit 'git credential.helper=store (texto plano); usa manager' }
        elseif ($helper) { Add-Ok "git credential.helper=$helper" }
    }
    $userEnv = [Environment]::GetEnvironmentVariables('User')
    $secretVars = @($userEnv.Keys) | Where-Object { $_ -match 'API_KEY|TOKEN|SECRET|PASSWORD' }
    if ($secretVars) { Add-Warn "Variables de entorno de usuario con secretos en claro: $($secretVars -join ', ')" }
    $ssh = Join-Path $env:USERPROFILE '.ssh'
    if ((Test-Path $ssh) -and (Get-Command ssh-keygen)) {
        Get-ChildItem $ssh -File | Where-Object { $_.Name -like 'id_*' -and $_.Extension -ne '.pub' } | ForEach-Object {
            & ssh-keygen -y -P '' -f $_.FullName *> $null
            if ($LASTEXITCODE -eq 0) { Add-Warn "Clave privada ~\.ssh\$($_.Name) sin passphrase" }
            else { Add-Ok "Clave privada ~\.ssh\$($_.Name) con passphrase" }
            $open = (Get-Acl $_.FullName).Access | Where-Object { "$($_.IdentityReference)" -match 'Everyone|Todos|\\Users$|\\Usuarios$' }
            if ($open) { Add-Crit "Clave privada ~\.ssh\$($_.Name) legible por otros usuarios" }
        }
    }
    $hist = (Get-PSReadLineOption).HistorySavePath
    if ($hist -and (Test-Path $hist)) {
        $hits = (Select-String -Path $hist -Pattern '(api[_-]?key|token|secret|passw(or)?d)\s*=|sk-ant-|ghp_|github_pat_|AKIA[0-9A-Z]{16}').Count
        if ($hits -gt 0) { Add-Warn "Historial de PowerShell: $hits líneas con posible secreto (no se muestran; bórralas)" }
    }
    $sensitive = Get-ChildItem -Path (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'), (Join-Path $env:USERPROFILE 'Documents') -File -Recurse -Depth 2 -Include '*.p12', '*.pfx', '*.kdbx', '*.pem', '*password*.csv', '*contrase*.csv', '*backup-codes*', '*recovery*' |
        Select-Object -First 30
    if ($sensitive) {
        Add-Warn 'Ficheros sensibles por nombre en Descargas/Escritorio/Documentos (certificados, exportaciones de contraseñas, códigos):'
        $sensitive | ForEach-Object { Add-Line "    - $(Get-Short $_.FullName)" }
    }
}

function Test-Persistence {
    Add-Section 'Persistencia'
    $startup = Get-CimInstance Win32_StartupCommand
    if ($startup) { Add-Info "Programas de inicio: $(($startup | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', ')" }
    else { Add-Info 'No se pudieron leer los programas de inicio' }
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and "$($_.State)" -ne 'Disabled' }
    if ($tasks) {
        Add-Info "Tareas programadas de terceros activas ($(@($tasks).Count)); verifica que reconoces todas:"
        $tasks | ForEach-Object {
            $exe = @($_.Actions)[0].Execute
            Add-Line "    - $($_.TaskPath)$($_.TaskName) → $(if ($exe) { Split-Path $exe -Leaf })"
        }
    }
}

function Protect-Text([string]$Text) {
    if ($NoRedact) { return $Text }
    $t = $Text -replace '\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b', '<mac>'
    $t = $t -replace '\b(?!127\.0\.0\.1\b)(?!0\.0\.0\.0\b)(\d{1,3}\.){3}\d{1,3}\b', '<ipv4>'
    $t = $t -replace '(?<![0-9A-Fa-f:])([0-9A-Fa-f]{1,4}:){4,7}[0-9A-Fa-f]{1,4}(?![0-9A-Fa-f:])', '<ipv6>'
    $t = $t -replace '(?<![0-9A-Fa-f:])[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4})*::([0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4})*)?(?![0-9A-Fa-f:])', '<ipv6>'
    $t = $t -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<email>'
    if ($env:COMPUTERNAME.Length -gt 2) { $t = $t -replace [regex]::Escape($env:COMPUTERNAME), '<host>' }
    if ($env:USERNAME.Length -gt 2) { $t = $t -replace ('\b' + [regex]::Escape($env:USERNAME) + '\b'), '<user>' }
    return $t
}

Add-Line '# Auditoría de seguridad Windows (solo lectura)'
Add-Line ''
Add-Line "Fecha: $(Get-Date -Format s) · redacción de datos identificativos: $(if ($NoRedact) { 'desactivada' } else { 'activada' })"
Test-System
Test-Updates
Test-Defender
Test-Firewall
Test-Hardening
Test-Accounts
Test-Network
Test-LocalAI
Test-Agents
Test-Credentials
Test-Persistence
Add-Line ''
Add-Line '## Resumen'
Add-Line ''
Add-Line "- CRÍTICO: $script:Crit"
Add-Line "- AVISO: $script:Warn"
Add-Line ''
Add-Line 'No se ha modificado el sistema.'

$report = Protect-Text ($script:Lines -join [Environment]::NewLine)
$report | Out-File -FilePath $Output -Encoding utf8
Write-Output $report
Write-Host "`n[+] Informe guardado en $Output" -ForegroundColor Green
