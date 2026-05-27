#Requires -Version 7.0
<#
.SYNOPSIS
    Validacion de precondiciones antes de pipeline forense.
.DESCRIPTION
    Verifica que la carpeta origen existe, no esta vacia, no es un enlace,
    y supera umbrales minimos. Busca rutas alternativas si falla.
    NO modifica archivos. NO abre contenido. Solo metadatos.
.PARAMETER RutaOrigen
    Ruta de la carpeta a auditar (por defecto: CASE_ESPRAVATO_FROM_ACER).
.PARAMETER MinArchivos
    Minimo de archivos requeridos para continuar (default: 5).
.PARAMETER MinBytes
    Tamano minimo total en bytes (default: 100KB).
.PARAMETER RutaLog
    Donde guardar el log de precondiciones.
.EXAMPLE
    .\Forensic-Precondiciones.ps1
    .\Forensic-Precondiciones.ps1 -RutaOrigen "D:\CASO" -MinArchivos 10 -MinBytes 1MB
#>

param(
    [string]$RutaOrigen  = "C:\Users\jacab\Documents\CASE_ESPRAVATO_FROM_ACER",
    [int]   $MinArchivos = 5,
    [long]  $MinBytes    = 100KB,
    [string]$RutaLog     = ".\precondiciones_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── helpers ────────────────────────────────────────────────────────────────────
$script:logBuffer = [System.Collections.Generic.List[string]]::new()

function Escribir {
    param([string]$msg, [string]$color = "White", [string]$nivel = "INFO")
    $linea = "[$(Get-Date -Format 'HH:mm:ss')] [$nivel] $msg"
    Write-Host $linea -ForegroundColor $color
    $script:logBuffer.Add($linea)
}

function OK    { param([string]$m) Escribir "  [PASS] $m" "Green"  "PASS" }
function FALLO { param([string]$m) Escribir "  [FAIL] $m" "Red"    "FAIL" }
function INFO  { param([string]$m) Escribir "  [INFO] $m" "Yellow" "INFO" }
function WARN  { param([string]$m) Escribir "  [WARN] $m" "Magenta" "WARN" }

function Guardar-Log {
    $script:logBuffer | Set-Content -Path $RutaLog -Encoding UTF8
    Write-Host "`nLog guardado: $RutaLog" -ForegroundColor Cyan
}

# ── resultado acumulado ────────────────────────────────────────────────────────
$fallosCriticos  = [System.Collections.Generic.List[string]]::new()
$advertencias    = [System.Collections.Generic.List[string]]::new()

# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n" + ("═" * 60) -ForegroundColor Cyan
Write-Host "  VALIDACION DE PRECONDICIONES FORENSES" -ForegroundColor Cyan
Write-Host "  Ruta:    $RutaOrigen" -ForegroundColor Cyan
Write-Host "  Usuario: $env:USERNAME  |  Equipo: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ("═" * 60) + "`n" -ForegroundColor Cyan

Escribir "Inicio validacion — PS $($PSVersionTable.PSVersion)  |  $([System.Environment]::OSVersion.VersionString)"

# ── CHECK 1: La ruta existe ────────────────────────────────────────────────────
Escribir "`nCHECK 1 — Existencia de ruta"
if (-not (Test-Path -LiteralPath $RutaOrigen)) {
    FALLO "La ruta NO existe: $RutaOrigen"
    $fallosCriticos.Add("Ruta no existe: $RutaOrigen")
} else {
    OK "Ruta existe: $RutaOrigen"
}

# ── CHECK 2: No es junction ni symlink ────────────────────────────────────────
Escribir "`nCHECK 2 — Tipo de elemento (no debe ser enlace)"
if (Test-Path -LiteralPath $RutaOrigen) {
    $item = Get-Item -LiteralPath $RutaOrigen
    if ($item.LinkType) {
        FALLO "La ruta es un enlace ($($item.LinkType)) → Target: $($item.Target)"
        $fallosCriticos.Add("Ruta es enlace $($item.LinkType) → $($item.Target)")
    } else {
        OK "La ruta es un directorio real (sin enlace simbolico)"
    }
}

# ── CHECK 3: Permisos de lectura ──────────────────────────────────────────────
Escribir "`nCHECK 3 — Permisos de lectura"
if (Test-Path -LiteralPath $RutaOrigen) {
    try {
        $null = Get-ChildItem -LiteralPath $RutaOrigen -ErrorAction Stop
        OK "Permisos de lectura confirmados"
    } catch {
        FALLO "Sin permiso de lectura: $_"
        $fallosCriticos.Add("Sin permiso de lectura")
    }
}

# ── CHECK 4: Conteo de archivos ───────────────────────────────────────────────
Escribir "`nCHECK 4 — Cantidad de archivos"
$archivos = @()
if (Test-Path -LiteralPath $RutaOrigen) {
    $archivos = @(Get-ChildItem -LiteralPath $RutaOrigen -Recurse -File -ErrorAction SilentlyContinue)
    $totalFiles = $archivos.Count
    if ($totalFiles -lt $MinArchivos) {
        FALLO "Solo $totalFiles archivos encontrados (minimo requerido: $MinArchivos)"
        $fallosCriticos.Add("Archivos insuficientes: $totalFiles < $MinArchivos")
    } else {
        OK "$totalFiles archivos encontrados (minimo: $MinArchivos)"
    }
}

# ── CHECK 5: Tamano total ─────────────────────────────────────────────────────
Escribir "`nCHECK 5 — Tamano total"
if ($archivos.Count -gt 0) {
    $totalBytes = ($archivos | Measure-Object -Property Length -Sum).Sum
    $totalMB    = [math]::Round($totalBytes / 1MB, 3)
    if ($totalBytes -lt $MinBytes) {
        FALLO "Tamano total: $totalMB MB (minimo requerido: $([math]::Round($MinBytes/1KB,1)) KB)"
        $fallosCriticos.Add("Tamano insuficiente: $totalBytes bytes")
    } else {
        OK "Tamano total: $totalMB MB"
    }
} elseif (Test-Path -LiteralPath $RutaOrigen) {
    FALLO "Sin archivos — no se puede calcular tamano"
    $totalBytes = 0
}

# ── CHECK 6: Fecha de ultima escritura sospechosa ────────────────────────────
Escribir "`nCHECK 6 — Fecha de ultima modificacion"
if (Test-Path -LiteralPath $RutaOrigen) {
    $ultimaEscritura = (Get-Item -LiteralPath $RutaOrigen).LastWriteTime
    $horasDesde      = [math]::Round(((Get-Date) - $ultimaEscritura).TotalHours, 1)
    INFO "LastWriteTime: $ultimaEscritura (hace $horasDesde horas)"
    if ($horasDesde -lt 1) {
        WARN "Carpeta modificada hace menos de 1 hora — posible creacion reciente o placeholder"
        $advertencias.Add("Carpeta muy reciente: $ultimaEscritura")
    } else {
        OK "Fecha de modificacion parece consistente"
    }
}

# ── CHECK 7: Senales de migracion parcial ────────────────────────────────────
Escribir "`nCHECK 7 — Deteccion de migracion parcial"
if ($archivos.Count -gt 0) {
    $extensiones = $archivos | Group-Object Extension | Sort-Object Count -Descending
    $soloMeta    = $extensiones | Where-Object {
        $_.Name -in @('.ini', '.db', '.lnk', '.tmp', '.log', '') -and $extensiones.Count -le 3
    }
    if ($soloMeta) {
        WARN "Solo se detectan archivos de metadatos/sistema — posible migracion incompleta"
        $advertencias.Add("Solo metadatos: $($extensiones.Name -join ', ')")
    } else {
        OK "Mix de tipos de archivo: $($extensiones | Select-Object -First 5 | ForEach-Object {"$($_.Name)($($_.Count))"} | Join-String -Separator ', ')"
    }
}

# ── CHECK 8: Rutas alternativas si hay fallos ─────────────────────────────────
Escribir "`nCHECK 8 — Busqueda de rutas alternativas"
$nombreCarpeta = Split-Path $RutaOrigen -Leaf
$candidatos = @(
    "C:\Users\$env:USERNAME\OneDrive\Documents\$nombreCarpeta",
    "C:\Users\$env:USERNAME\OneDrive\$nombreCarpeta",
    "C:\Users\$env:USERNAME\Downloads\$nombreCarpeta",
    "C:\Users\$env:USERNAME\Desktop\$nombreCarpeta",
    "D:\$nombreCarpeta",
    "E:\$nombreCarpeta",
    "F:\$nombreCarpeta"
)

$alternativasEncontradas = [System.Collections.Generic.List[object]]::new()
foreach ($c in $candidatos) {
    if ((Test-Path -LiteralPath $c -ErrorAction SilentlyContinue) -and ($c -ne $RutaOrigen)) {
        $cnt = @(Get-ChildItem -LiteralPath $c -Recurse -File -ErrorAction SilentlyContinue).Count
        $alternativasEncontradas.Add([PSCustomObject]@{ Ruta = $c; Archivos = $cnt })
        WARN "Ruta alternativa encontrada: $c ($cnt archivos)"
    }
}
if ($alternativasEncontradas.Count -eq 0) {
    INFO "No se encontraron rutas alternativas para '$nombreCarpeta'"
}

# ── CHECK 9: Rutas largas (>260 chars) ───────────────────────────────────────
Escribir "`nCHECK 9 — Rutas largas (>260 caracteres)"
if ($archivos.Count -gt 0) {
    $rutasLargas = $archivos | Where-Object { $_.FullName.Length -gt 260 }
    if ($rutasLargas.Count -gt 0) {
        WARN "$($rutasLargas.Count) archivo(s) con rutas > 260 chars — verificar LongPathsEnabled"
        $advertencias.Add("Rutas largas: $($rutasLargas.Count) archivos")
    } else {
        OK "Ninguna ruta supera 260 caracteres"
    }
}

# ── CHECK 10: LongPathsEnabled en registro ────────────────────────────────────
Escribir "`nCHECK 10 — LongPathsEnabled en registro"
try {
    $lpe = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -ErrorAction Stop).LongPathsEnabled
    if ($lpe -eq 1) {
        OK "LongPathsEnabled = 1 (activo)"
    } else {
        WARN "LongPathsEnabled = 0 — riesgo en rutas profundas"
        $advertencias.Add("LongPathsEnabled desactivado")
    }
} catch {
    INFO "No se pudo leer LongPathsEnabled del registro (puede requerir admin)"
}

# ══════════════════════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ══════════════════════════════════════════════════════════════════════════════
Write-Host "`n" + ("═" * 60) -ForegroundColor Cyan
Write-Host "  RESUMEN DE PRECONDICIONES" -ForegroundColor Cyan
Write-Host ("═" * 60) -ForegroundColor Cyan

# Exportar snapshot de metadatos
$snapshot = [PSCustomObject]@{
    FechaValidacion   = Get-Date -Format "o"
    Usuario           = $env:USERNAME
    Equipo            = $env:COMPUTERNAME
    RutaOrigen        = $RutaOrigen
    ArchivosEncontrados = $archivos.Count
    TotalBytes        = if ($archivos.Count -gt 0) { ($archivos | Measure-Object Length -Sum).Sum } else { 0 }
    FallosCriticos    = $fallosCriticos.Count
    Advertencias      = $advertencias.Count
    AlternativasHalladas = $alternativasEncontradas.Count
    Veredicto         = if ($fallosCriticos.Count -eq 0) { "PROCEDER" } else { "BLOQUEAR" }
}

$snapshot | Format-List

# Guardar snapshot JSON
$snapshotPath = ".\precondiciones_snapshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$snapshot | ConvertTo-Json | Set-Content -Path $snapshotPath -Encoding UTF8
Write-Host "Snapshot guardado: $snapshotPath" -ForegroundColor Cyan

# Si hay alternativas, exportarlas
if ($alternativasEncontradas.Count -gt 0) {
    $altPath = ".\rutas_alternativas_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $alternativasEncontradas | Export-Csv -Path $altPath -NoTypeInformation -Encoding UTF8
    Write-Host "Alternativas exportadas: $altPath" -ForegroundColor Yellow
}

# Veredicto final
Write-Host ""
if ($fallosCriticos.Count -gt 0) {
    Write-Host ("  VEREDICTO: NO EJECUTAR PIPELINE" ) -ForegroundColor Red -BackgroundColor DarkRed
    Write-Host ""
    $fallosCriticos | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Guardar-Log
    exit 2
} elseif ($advertencias.Count -gt 0) {
    Write-Host "  VEREDICTO: PROCEDER CON REVISION MANUAL" -ForegroundColor Yellow
    Write-Host ""
    $advertencias | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Guardar-Log
    exit 1
} else {
    Write-Host "  VEREDICTO: PROCEDER — todas las precondiciones cumplidas" -ForegroundColor Green
    Guardar-Log
    exit 0
}
