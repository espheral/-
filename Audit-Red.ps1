#Requires -Version 5.1
<#
.SYNOPSIS
    Auditoria de red local para Windows 11
.DESCRIPTION
    Escanea dispositivos, puertos abiertos y configuracion de red.
    Ejecutar con: powershell -ExecutionPolicy Bypass -File Audit-Red.ps1
#>

param(
    [string]$Rango = "",          # Ej: "192.168.1" — si esta vacio lo detecta automaticamente
    [string]$Output  = ".\audit-red.txt",
    [switch]$IncluirPuertos,      # Escanea puertos comunes en cada host
    [switch]$SoloLocal            # Solo muestra info local, sin ping sweep
)

$ErrorActionPreference = "SilentlyContinue"

# ── colores ────────────────────────────────────────────────────────────────────
function Write-Header([string]$texto) {
    Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $texto" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
}

function Write-Ok([string]$texto)   { Write-Host "  [+] $texto" -ForegroundColor Green }
function Write-Info([string]$texto) { Write-Host "  [*] $texto" -ForegroundColor Yellow }
function Write-Warn([string]$texto) { Write-Host "  [!] $texto" -ForegroundColor Red }

$lineas = [System.Collections.Generic.List[string]]::new()
function Log([string]$t) { $lineas.Add($t) }

# ── PUERTOS COMUNES A REVISAR ───────────────────────────────────────────────
$PuertosComunes = @(
    @{Puerto=21;  Servicio="FTP"},
    @{Puerto=22;  Servicio="SSH"},
    @{Puerto=23;  Servicio="Telnet"},
    @{Puerto=25;  Servicio="SMTP"},
    @{Puerto=53;  Servicio="DNS"},
    @{Puerto=80;  Servicio="HTTP"},
    @{Puerto=110; Servicio="POP3"},
    @{Puerto=135; Servicio="RPC"},
    @{Puerto=139; Servicio="NetBIOS"},
    @{Puerto=143; Servicio="IMAP"},
    @{Puerto=443; Servicio="HTTPS"},
    @{Puerto=445; Servicio="SMB"},
    @{Puerto=1433; Servicio="MSSQL"},
    @{Puerto=3306; Servicio="MySQL"},
    @{Puerto=3389; Servicio="RDP"},
    @{Puerto=5900; Servicio="VNC"},
    @{Puerto=8080; Servicio="HTTP-Alt"},
    @{Puerto=8443; Servicio="HTTPS-Alt"}
)

# ══════════════════════════════════════════════════════════════════════════════
Write-Header "AUDITORIA DE RED — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log "AUDITORIA DE RED — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Log "Equipo: $env:COMPUTERNAME  |  Usuario: $env:USERNAME"

# ── 1. INFO LOCAL ──────────────────────────────────────────────────────────────
Write-Header "1. CONFIGURACION DE RED LOCAL"
Log "`n[1. CONFIGURACION DE RED LOCAL]"

$adaptadores = Get-NetIPConfiguration | Where-Object { $_.IPv4Address }

foreach ($a in $adaptadores) {
    $ip       = $a.IPv4Address.IPAddress
    $gw       = $a.IPv4DefaultGateway.NextHop
    $dns      = ($a.DNSServer.ServerAddresses -join ", ")
    $iface    = $a.InterfaceAlias

    Write-Ok "Interfaz  : $iface"
    Write-Ok "IP Local  : $ip"
    Write-Ok "Gateway   : $gw"
    Write-Ok "DNS       : $dns"
    Write-Host ""

    Log "  Interfaz : $iface"
    Log "  IP Local : $ip"
    Log "  Gateway  : $gw"
    Log "  DNS      : $dns"
}

# Detectar rango automaticamente
if (-not $Rango) {
    $ipPrincipal = ($adaptadores | Select-Object -First 1).IPv4Address.IPAddress
    if ($ipPrincipal) {
        $partes = $ipPrincipal -split "\."
        $Rango  = "$($partes[0]).$($partes[1]).$($partes[2])"
    }
}

# ── 2. TABLA ARP (dispositivos ya conocidos) ───────────────────────────────
Write-Header "2. DISPOSITIVOS EN TABLA ARP"
Log "`n[2. TABLA ARP]"

$arp = arp -a | Select-String "(\d{1,3}\.){3}\d{1,3}" |
    Where-Object { $_ -notmatch "224\.|239\.|255\." } |
    ForEach-Object {
        $cols = ($_.ToString().Trim() -split "\s+")
        [PSCustomObject]@{ IP  = $cols[0]; MAC = $cols[1]; Tipo = $cols[2] }
    }

if ($arp) {
    $arp | Format-Table -AutoSize | Out-Host
    Log ($arp | Format-Table -AutoSize | Out-String)
} else {
    Write-Info "Tabla ARP vacia o sin permiso."
}

# ── 3. CONEXIONES ACTIVAS ──────────────────────────────────────────────────
Write-Header "3. CONEXIONES DE RED ACTIVAS"
Log "`n[3. CONEXIONES ACTIVAS]"

$conex = Get-NetTCPConnection -State Established |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State,
        @{N="Proceso";E={ (Get-Process -Id $_.OwningProcess -EA SilentlyContinue).Name }} |
    Sort-Object RemoteAddress

$conex | Format-Table -AutoSize | Out-Host
Log ($conex | Format-Table -AutoSize | Out-String)

# ── 4. PUERTOS ESCUCHANDO LOCALMENTE ──────────────────────────────────────
Write-Header "4. PUERTOS ABIERTOS EN ESTE EQUIPO"
Log "`n[4. PUERTOS ESCUCHANDO]"

$listening = Get-NetTCPConnection -State Listen |
    Select-Object LocalAddress, LocalPort,
        @{N="Proceso";E={ (Get-Process -Id $_.OwningProcess -EA SilentlyContinue).Name }} |
    Sort-Object LocalPort

$listening | Format-Table -AutoSize | Out-Host
Log ($listening | Format-Table -AutoSize | Out-String)

# ── 5. PING SWEEP ──────────────────────────────────────────────────────────
if (-not $SoloLocal -and $Rango) {
    Write-Header "5. ESCANEO DE RED: $Rango.1 - $Rango.254"
    Log "`n[5. PING SWEEP $Rango.0/24]"
    Write-Info "Escaneando $Rango.1 al $Rango.254 (puede tardar 1-2 min)..."

    $jobs = 1..254 | ForEach-Object {
        $ip = "$Rango.$_"
        Start-Job -ScriptBlock {
            param($h)
            $p = Test-Connection -ComputerName $h -Count 1 -Quiet -TimeoutSeconds 1
            if ($p) {
                $nombre = try { [System.Net.Dns]::GetHostEntry($h).HostName } catch { "?" }
                [PSCustomObject]@{ IP = $h; Hostname = $nombre; Estado = "ACTIVO" }
            }
        } -ArgumentList $ip
    }

    $hosts = $jobs | Wait-Job | Receive-Job | Where-Object { $_ }
    $jobs | Remove-Job

    if ($hosts) {
        Write-Ok "Dispositivos encontrados: $($hosts.Count)"
        $hosts | Sort-Object { [Version]$_.IP } | Format-Table -AutoSize | Out-Host
        Log ($hosts | Sort-Object { [Version]$_.IP } | Format-Table -AutoSize | Out-String)

        # ── 6. ESCANEO DE PUERTOS POR HOST ────────────────────────────────
        if ($IncluirPuertos) {
            Write-Header "6. ESCANEO DE PUERTOS EN HOSTS ACTIVOS"
            Log "`n[6. PUERTOS POR HOST]"

            foreach ($host in ($hosts | Sort-Object { [Version]$_.IP })) {
                Write-Info "Escaneando $($host.IP) ($($host.Hostname))..."
                $abiertos = @()

                foreach ($p in $PuertosComunes) {
                    $r = Test-NetConnection -ComputerName $host.IP -Port $p.Puerto -WarningAction SilentlyContinue
                    if ($r.TcpTestSucceeded) {
                        $abiertos += "$($p.Puerto)/$($p.Servicio)"
                        Write-Ok "  $($host.IP):$($p.Puerto) ($($p.Servicio)) ABIERTO"
                    }
                }

                if ($abiertos.Count -eq 0) {
                    Write-Info "  $($host.IP) — sin puertos comunes abiertos"
                    Log "  $($host.IP): sin puertos comunes abiertos"
                } else {
                    Log "  $($host.IP) ($($host.Hostname)): $($abiertos -join ', ')"
                }
            }
        }
    } else {
        Write-Warn "No se encontraron hosts activos. Verifica el rango o el firewall."
        Log "Sin hosts activos detectados."
    }
}

# ── 7. SHARES DE RED ───────────────────────────────────────────────────────
Write-Header "7. RECURSOS COMPARTIDOS SMB"
Log "`n[7. SHARES SMB]"

$shares = Get-SmbShare | Select-Object Name, Path, Description, ScopeName
$shares | Format-Table -AutoSize | Out-Host
Log ($shares | Format-Table -AutoSize | Out-String)

# ── 8. WIFI ────────────────────────────────────────────────────────────────
Write-Header "8. REDES WIFI"
Log "`n[8. WIFI]"

$wifi = netsh wlan show interfaces 2>$null
if ($wifi) {
    $wifi | Out-Host
    Log ($wifi | Out-String)
} else {
    Write-Info "Sin adaptador WiFi o no disponible."
    Log "Sin WiFi."
}

# ── 9. RESUMEN FIREWALL ────────────────────────────────────────────────────
Write-Header "9. ESTADO DEL FIREWALL"
Log "`n[9. FIREWALL]"

$fw = Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
$fw | Format-Table -AutoSize | Out-Host
Log ($fw | Format-Table -AutoSize | Out-String)

# Reglas con puerto abierto hacia dentro
$reglasEntrada = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow |
    Where-Object { $_.DisplayName -notmatch "Core|DHCP|mDNS|Teredo|Cortana|Remote Desktop" } |
    Select-Object -First 20 DisplayName, Profile
if ($reglasEntrada) {
    Write-Info "Reglas de entrada activas (top 20):"
    $reglasEntrada | Format-Table -AutoSize | Out-Host
    Log ($reglasEntrada | Format-Table -AutoSize | Out-String)
}

# ── GUARDAR REPORTE ────────────────────────────────────────────────────────
Write-Header "REPORTE"
$lineas | Set-Content -Path $Output -Encoding UTF8
Write-Ok "Reporte guardado en: $(Resolve-Path $Output)"
Write-Host ""
Write-Host "  Uso avanzado:" -ForegroundColor Magenta
Write-Host "    .\Audit-Red.ps1 -IncluirPuertos          # escanea puertos en cada host" -ForegroundColor DarkGray
Write-Host "    .\Audit-Red.ps1 -Rango '10.0.0'          # rango personalizado" -ForegroundColor DarkGray
Write-Host "    .\Audit-Red.ps1 -SoloLocal               # solo info de este equipo" -ForegroundColor DarkGray
Write-Host "    .\Audit-Red.ps1 -IncluirPuertos -Rango '192.168.0'" -ForegroundColor DarkGray
Write-Host ""
