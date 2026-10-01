#Requires -Version 5.1
<#
.SYNOPSIS
    Aplica ajustes seguros para reducir tirones y congelamientos en Windows 10/11.
.DESCRIPTION
    Pregunta antes de cada cambio. Guarda los valores originales en
    %LOCALAPPDATA%\optimizar-pc\respaldo.json para poder deshacerlos con -Revertir.
    No toca el antivirus, Windows Update, los servicios ni nada que reduzca la seguridad.
.PARAMETER Revertir
    Deshace los cambios guardados en el respaldo.
.PARAMETER Todo
    Aplica los ajustes recomendados sin preguntar. La reparación de Windows
    (DISM + SFC) solo se ejecuta si además se indica -RepararSistema.
.PARAMETER RepararSistema
    Repara archivos dañados de Windows con DISM y SFC (tarda de 10 a 30 minutos).
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\optimizar.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\optimizar.ps1 -Revertir
#>
[CmdletBinding()]
param(
    [switch]$Revertir,
    [switch]$Todo,
    [switch]$RepararSistema
)

$ErrorActionPreference = 'Stop'

$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $esAdmin) {
    Write-Host 'Este script necesita permisos de administrador.' -ForegroundColor Red
    Write-Host 'Usa EJECUTAR.bat, o abre PowerShell con clic derecho > "Ejecutar como administrador".'
    exit 1
}

$RutaRespaldo = Join-Path $env:LOCALAPPDATA 'optimizar-pc\respaldo.json'
$PlanAltoRendimiento = '8c5e7fda-e8bf-4a96-9a85-cf2c25edf3d8'
$PlanMaximoRendimiento = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$PatronGuid = '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
$RutaGameDvr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
$RutaGameConfig = 'HKCU:\System\GameConfigStore'
$RutaGameBar = 'HKCU:\Software\Microsoft\GameBar'

# --- Respaldo ----------------------------------------------------------------
# Solo se guarda el valor original la PRIMERA vez que se toca algo, para que
# ejecutar el script dos veces no pise el respaldo con valores ya optimizados.

function Read-Respaldo {
    $r = @{ Creado = (Get-Date).ToString('s'); Registro = @() }
    if (Test-Path $RutaRespaldo) {
        $json = Get-Content -Path $RutaRespaldo -Raw | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $r[$p.Name] = $p.Value }
        $r.Registro = @($r.Registro | Where-Object { $_ })
    }
    return $r
}

function Save-Respaldo {
    $carpeta = Split-Path $RutaRespaldo
    if (-not (Test-Path $carpeta)) { New-Item -ItemType Directory -Path $carpeta | Out-Null }
    $script:Respaldo | ConvertTo-Json -Depth 5 | Set-Content -Path $RutaRespaldo -Encoding UTF8
}

function Get-ValorRegistro([string]$Ruta, [string]$Nombre) {
    if (-not (Test-Path $Ruta)) { return $null }
    $p = Get-ItemProperty -Path $Ruta -Name $Nombre -ErrorAction SilentlyContinue
    if ($p) { return $p.$Nombre }
    return $null
}

function Set-ValorRegistro([string]$Ruta, [string]$Nombre, [int]$Valor) {
    $yaGuardado = @($script:Respaldo.Registro | Where-Object { $_.Path -eq $Ruta -and $_.Name -eq $Nombre }).Count -gt 0
    if (-not $yaGuardado) {
        $actual = Get-ValorRegistro $Ruta $Nombre
        $script:Respaldo.Registro = @($script:Respaldo.Registro) + [pscustomobject]@{
            Path = $Ruta; Name = $Nombre; Existia = ($null -ne $actual); Valor = $actual
        }
        Save-Respaldo
    }
    if (-not (Test-Path $Ruta)) { New-Item -Path $Ruta -Force | Out-Null }
    New-ItemProperty -Path $Ruta -Name $Nombre -Value $Valor -PropertyType DWord -Force | Out-Null
}

function Get-PlanActivo {
    if ((powercfg /getactivescheme | Out-String) -match $PatronGuid) { return $Matches[0].ToLower() }
    return $null
}

# --- Interfaz ----------------------------------------------------------------

function Confirmar([string]$Pregunta, [bool]$PorDefecto) {
    if ($Todo) { return $PorDefecto }
    $opciones = if ($PorDefecto) { '[S/n]' } else { '[s/N]' }
    $respuesta = Read-Host "  $Pregunta $opciones"
    if ([string]::IsNullOrWhiteSpace($respuesta)) { return $PorDefecto }
    return ($respuesta.Trim() -match '^[sSyY]')
}

function Write-Titulo([string]$Texto) {
    Write-Host ''
    Write-Host "== $Texto ==" -ForegroundColor Cyan
}

$script:Aplicados = New-Object System.Collections.Generic.List[string]

function Invoke-Paso {
    param([string]$Titulo, [string]$Explicacion, [bool]$PorDefecto, [scriptblock]$Accion)
    Write-Titulo $Titulo
    Write-Host "  $Explicacion"
    if (-not (Confirmar '¿Aplicar?' $PorDefecto)) {
        Write-Host '  Omitido.' -ForegroundColor DarkGray
        return
    }
    try {
        & $Accion
        $script:Aplicados.Add($Titulo)
        Write-Host '  Hecho.' -ForegroundColor Green
    } catch {
        Write-Host "  No se pudo aplicar: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# --- Deshacer ----------------------------------------------------------------

if ($Revertir) {
    if (-not (Test-Path $RutaRespaldo)) {
        Write-Host 'No hay cambios que deshacer (no se encontró el respaldo).'
        exit 0
    }
    $r = Read-Respaldo
    $errores = 0
    function Invoke-Deshacer([string]$Que, [scriptblock]$Accion) {
        try { & $Accion; Write-Host "  [OK] $Que" -ForegroundColor Green }
        catch { $script:errores++; Write-Host "  [ERROR] $Que : $($_.Exception.Message)" -ForegroundColor Yellow }
    }

    Write-Titulo 'Deshaciendo cambios'
    if ($r.PlanEnergia) {
        Invoke-Deshacer 'Plan de energía original' {
            powercfg /setactive $r.PlanEnergia
            if ($LASTEXITCODE -ne 0) { throw "powercfg devolvió el código $LASTEXITCODE" }
            if ($r.PlanCreado) { powercfg /delete $r.PlanCreado | Out-Null }
        }
    }
    foreach ($e in $r.Registro) {
        Invoke-Deshacer "Registro: $($e.Name)" {
            if ($e.Existia) {
                New-ItemProperty -Path $e.Path -Name $e.Name -Value ([int]$e.Valor) -PropertyType DWord -Force | Out-Null
            } elseif (Test-Path $e.Path) {
                Remove-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction SilentlyContinue
            }
        }
    }
    if ($r.ContainsKey('PaginacionAutomatica') -and -not $r.PaginacionAutomatica) {
        Invoke-Deshacer 'Configuración original de la memoria virtual' {
            Set-CimInstance -InputObject (Get-CimInstance Win32_ComputerSystem) -Property @{ AutomaticManagedPagefile = $false }
            foreach ($p in @($r.ArchivosPaginacion | Where-Object { $_ })) {
                $config = Get-CimInstance Win32_PageFileSetting | Where-Object Name -eq $p.Name
                if (-not $config) { $config = New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $p.Name } }
                Set-CimInstance -InputObject $config -Property @{ InitialSize = [uint32]$p.InitialSize; MaximumSize = [uint32]$p.MaximumSize }
            }
        }
    }

    Write-Host ''
    if ($errores -eq 0) {
        Remove-Item $RutaRespaldo
        Write-Host 'Listo: todo volvió a como estaba. Reinicia la PC para terminar.' -ForegroundColor Green
    } else {
        Write-Host "Hubo $errores error(es); el respaldo se conserva en $RutaRespaldo para reintentar." -ForegroundColor Yellow
    }
    exit 0
}

# --- Optimizar ---------------------------------------------------------------

$script:Respaldo = Read-Respaldo
$esPortatil = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)

Write-Host 'OPTIMIZAR PC - ajustes contra tirones y congelamientos' -ForegroundColor White
Write-Host 'Pulsa Enter para aceptar la opción recomendada (la que va en mayúscula).'

Write-Titulo 'Punto de restauración'
try {
    $avisos = $null
    Checkpoint-Computer -Description 'Antes de optimizar-pc' -RestorePointType MODIFY_SETTINGS -WarningVariable avisos -WarningAction SilentlyContinue
    if ($avisos) { Write-Host '  Ya hay un punto de restauración de las últimas 24 h; se usará ese.' -ForegroundColor DarkGray }
    else { Write-Host '  Creado.' -ForegroundColor Green }
} catch {
    Write-Host '  No se pudo crear (la Protección del sistema está desactivada).' -ForegroundColor Yellow
    Write-Host '  Los ajustes de este script se pueden deshacer igual con la opción 3 de EJECUTAR.bat.'
    if (-not (Confirmar '¿Continuar de todas formas?' $true)) { exit 0 }
}

$planActual = Get-PlanActivo
$yaEnAlto = $planActual -in $PlanAltoRendimiento, $PlanMaximoRendimiento
# Si en una ejecución anterior se recreó el plan, tiene otro GUID: no duplicarlo otra vez.
if ($script:Respaldo.PlanCreado -and $planActual -eq $script:Respaldo.PlanCreado) { $yaEnAlto = $true }
if ($yaEnAlto) {
    Write-Titulo 'Plan de energía'
    Write-Host '  Ya está en alto rendimiento.' -ForegroundColor DarkGray
} else {
    $explicacion = 'Evita que el procesador baje de velocidad en mitad de un juego (una causa típica de microtirones).'
    if ($esPortatil) { $explicacion += ' En portátil gasta más batería: úsalo con el cargador conectado.' }
    Invoke-Paso 'Plan de energía: Alto rendimiento' $explicacion $true {
        $destino = $PlanAltoRendimiento
        if ((powercfg /list | Out-String) -notmatch $PlanAltoRendimiento) {
            # Algunos equipos esconden el plan; se puede recrear a partir de la plantilla.
            $salida = powercfg -duplicatescheme $PlanAltoRendimiento | Out-String
            if ($LASTEXITCODE -ne 0 -or $salida -notmatch $PatronGuid) {
                throw 'este equipo solo admite el plan Equilibrado. Usa Configuración > Sistema > Energía > Modo de energía: "Mejor rendimiento".'
            }
            $destino = $Matches[0]
            $script:Respaldo.PlanCreado = $destino
        }
        if (-not $script:Respaldo.PlanEnergia) { $script:Respaldo.PlanEnergia = $planActual }
        Save-Respaldo
        powercfg /setactive $destino
        if ($LASTEXITCODE -ne 0) { throw "powercfg devolvió el código $LASTEXITCODE" }
    }
}

$capturaActiva = @(
    Get-ValorRegistro $RutaGameConfig 'GameDVR_Enabled'
    Get-ValorRegistro $RutaGameDvr 'AppCaptureEnabled'
    Get-ValorRegistro $RutaGameDvr 'HistoricalCaptureEnabled'
) -contains 1
if ($capturaActiva) {
    Invoke-Paso 'Desactivar la captura de Xbox Game Bar' 'Grabar el juego en segundo plano consume disco y gráfica y causa tirones. OBS, ShadowPlay y Discord siguen funcionando; solo deja de funcionar Win+Alt+R.' $true {
        Set-ValorRegistro $RutaGameConfig 'GameDVR_Enabled' 0
        Set-ValorRegistro $RutaGameDvr 'AppCaptureEnabled' 0
        Set-ValorRegistro $RutaGameDvr 'HistoricalCaptureEnabled' 0
    }
} else {
    Write-Titulo 'Captura de Xbox Game Bar'
    Write-Host '  Ya está desactivada.' -ForegroundColor DarkGray
}

if ((Get-ValorRegistro $RutaGameBar 'AutoGameModeEnabled') -eq 0) {
    Invoke-Paso 'Activar el Modo de juego' 'Windows da prioridad al juego y pausa tareas de fondo (como instalar actualizaciones) mientras juegas.' $true {
        Set-ValorRegistro $RutaGameBar 'AutoGameModeEnabled' 1
    }
} else {
    Write-Titulo 'Modo de juego'
    Write-Host '  Ya está activado.' -ForegroundColor DarkGray
}

$sistema = Get-CimInstance Win32_ComputerSystem
if (-not $sistema.AutomaticManagedPagefile) {
    Invoke-Paso 'Memoria virtual administrada por Windows' 'La paginación está desactivada o fijada a mano. Si se queda corta, la PC se congela cuando se llena la RAM. Windows la ajustará solo (necesita reiniciar).' $true {
        if (-not $script:Respaldo.ContainsKey('PaginacionAutomatica')) {
            $script:Respaldo.PaginacionAutomatica = $false
            $script:Respaldo.ArchivosPaginacion = @(Get-CimInstance Win32_PageFileSetting | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Name; InitialSize = $_.InitialSize; MaximumSize = $_.MaximumSize }
                })
            Save-Respaldo
        }
        Set-CimInstance -InputObject $sistema -Property @{ AutomaticManagedPagefile = $true }
    }
} else {
    Write-Titulo 'Memoria virtual'
    Write-Host '  Ya la administra Windows.' -ForegroundColor DarkGray
}

Invoke-Paso 'Borrar archivos temporales' 'Borra los temporales de más de 1 día (de Windows y de tu usuario). Los que estén en uso se saltan.' $true {
    $limite = (Get-Date).AddDays(-1)
    $liberado = 0
    foreach ($carpeta in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Select-Object -Unique) {
        if (-not (Test-Path $carpeta)) { continue }
        Get-ChildItem -Path $carpeta -Recurse -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limite } |
            ForEach-Object {
                $tamano = $_.Length
                try { Remove-Item -LiteralPath $_.FullName -Force; $liberado += $tamano } catch { }
            }
    }
    Write-Host ('  Liberados {0:N0} MB.' -f ($liberado / 1MB))
}

Invoke-Paso 'Optimizar discos' 'SSD: envía TRIM para que no pierda velocidad. Disco mecánico: desfragmenta (puede tardar; puedes seguir usando la PC).' $true {
    $volumenes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.FileSystem -in 'NTFS', 'ReFS' }
    foreach ($v in $volumenes) {
        Write-Host "  Optimizando $($v.DriveLetter):..."
        try { Optimize-Volume -DriveLetter $v.DriveLetter }
        catch { Write-Host "  $($v.DriveLetter): no admite optimización ($($_.Exception.Message))" -ForegroundColor DarkGray }
    }
}

Invoke-Paso 'Reparar archivos de Windows (DISM + SFC)' 'Arregla archivos del sistema dañados, que pueden causar cuelgues. Tarda de 10 a 30 minutos y necesita internet.' ([bool]$RepararSistema) {
    DISM.exe /Online /Cleanup-Image /RestoreHealth
    if ($LASTEXITCODE -ne 0) { Write-Host "  DISM terminó con el código $LASTEXITCODE." -ForegroundColor Yellow }
    sfc.exe /scannow
}

Write-Titulo 'Resumen'
if ($script:Aplicados.Count -eq 0) {
    Write-Host '  No se aplicó ningún cambio.'
} else {
    foreach ($a in $script:Aplicados) { Write-Host "  - $a" -ForegroundColor Green }
    Write-Host ''
    Write-Host '  Reinicia la PC (Inicio > Reiniciar) para que todo tenga efecto.' -ForegroundColor White
    Write-Host '  Si algo no te convence, la opción 3 de EJECUTAR.bat lo deshace.'
}
