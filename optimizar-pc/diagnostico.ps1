#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnóstico de rendimiento (solo lectura): busca las causas más comunes de
    tirones, cortes y congelamientos en Windows 10/11.
.DESCRIPTION
    No modifica nada del sistema. Muestra los resultados en pantalla y guarda un
    informe de texto en el Escritorio. Con permisos de administrador da algo más
    de detalle sobre la salud de los discos.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\diagnostico.ps1
#>
[CmdletBinding()]
param(
    [string]$Informe = (Join-Path ([Environment]::GetFolderPath('Desktop')) ('diagnostico-pc-{0:yyyyMMdd-HHmm}.txt' -f (Get-Date))),
    [int]$DiasEventos = 30
)

$ErrorActionPreference = 'Stop'

$script:Hallazgos = New-Object System.Collections.Generic.List[object]
$script:Lineas = New-Object System.Collections.Generic.List[string]

function Write-Linea {
    param([string]$Texto = '', [ConsoleColor]$Color = 'Gray')
    Write-Host $Texto -ForegroundColor $Color
    $script:Lineas.Add($Texto)
}

function Write-Titulo([string]$Texto) {
    Write-Linea
    Write-Linea "== $Texto ==" Cyan
}

function Write-Dato([string]$Etiqueta, $Valor) {
    Write-Linea ('  {0,-24} {1}' -f "${Etiqueta}:", $Valor)
}

function Write-Ok([string]$Texto) {
    Write-Linea "  [OK] $Texto" Green
}

function Add-Hallazgo {
    param(
        [ValidateSet('PROBLEMA', 'AVISO')][string]$Nivel,
        [string]$Tema,
        [string]$Detalle,
        [string]$Solucion
    )
    $script:Hallazgos.Add([pscustomobject]@{ Nivel = $Nivel; Tema = $Tema; Detalle = $Detalle; Solucion = $Solucion })
    $color = if ($Nivel -eq 'PROBLEMA') { 'Red' } else { 'Yellow' }
    Write-Linea "  [$Nivel] $Detalle" $color
}

# Cada sección va aislada: si una comprobación falla, las demás siguen.
function Invoke-Seccion([string]$Nombre, [scriptblock]$Bloque) {
    Write-Titulo $Nombre
    try { & $Bloque }
    catch { Write-Linea "  (No se pudo comprobar: $($_.Exception.Message))" DarkGray }
}

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$esPortatil = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Linea ('DIAGNÓSTICO DE RENDIMIENTO - {0:dd/MM/yyyy HH:mm}' -f (Get-Date)) White
Write-Linea ("Equipo: {0} {1} ({2})" -f $cs.Manufacturer, $cs.Model, $(if ($esPortatil) { 'portátil' } else { 'escritorio' }))
if (-not $esAdmin) {
    Write-Linea 'Nota: sin permisos de administrador algunas comprobaciones dan menos detalle.' DarkGray
}

Invoke-Seccion 'Sistema' {
    Write-Dato 'Windows' "$($os.Caption) (compilación $($os.BuildNumber))"
    $encendido = (Get-Date) - $os.LastBootUpTime
    Write-Dato 'Sin reiniciar desde hace' ('{0} días, {1} h' -f $encendido.Days, $encendido.Hours)
    if ($encendido.TotalDays -gt 7) {
        Add-Hallazgo AVISO 'Reinicio' "La PC lleva $($encendido.Days) días sin reiniciarse." `
            'Usa Inicio > Reiniciar (no "Apagar"): con el inicio rápido de Windows, "Apagar" no limpia la memoria ni los drivers.'
    } else {
        Write-Ok 'Reiniciada hace poco.'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        Add-Hallazgo AVISO 'Windows Update' 'Hay actualizaciones esperando un reinicio.' `
            'Reinicia para que terminen de instalarse; mientras tanto siguen trabajando en segundo plano.'
    }
}

Invoke-Seccion 'Procesador' {
    $cpu = @(Get-CimInstance Win32_Processor)
    Write-Dato 'Modelo' $cpu[0].Name.Trim()
    Write-Dato 'Núcleos / hilos' ('{0} / {1}' -f ($cpu | Measure-Object NumberOfCores -Sum).Sum, ($cpu | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
    $carga = ($cpu | Measure-Object LoadPercentage -Average).Average
    Write-Dato 'Uso ahora mismo' ('{0:N0} %' -f $carga)
    if ($carga -gt 80) {
        Add-Hallazgo AVISO 'Procesador ocupado' ('El procesador está al {0:N0} % ahora mismo.' -f $carga) `
            'Mira en "Procesos que más consumen" qué lo está usando y ciérralo si no lo necesitas.'
    }
}

Invoke-Seccion 'Memoria RAM' {
    $modulos = @(Get-CimInstance Win32_PhysicalMemory)
    $visibleGB = $os.TotalVisibleMemorySize / 1MB
    $libreGB = $os.FreePhysicalMemory / 1MB
    $instaladaGB = if ($modulos.Count) { ($modulos | Measure-Object Capacity -Sum).Sum / 1GB } else { $visibleGB }
    $usoPct = 100 * (1 - $libreGB / $visibleGB)
    Write-Dato 'Instalada' ('{0:N0} GB' -f $instaladaGB)
    Write-Dato 'En uso ahora' ('{0:N1} GB ({1:N0} %)' -f ($visibleGB - $libreGB), $usoPct)
    if ($modulos.Count) {
        Write-Dato 'Módulos' (($modulos | ForEach-Object { '{0:N0} GB' -f ($_.Capacity / 1GB) }) -join ' + ')
        $velocidad = ($modulos | Measure-Object ConfiguredClockSpeed -Maximum).Maximum
        if ($velocidad) { Write-Dato 'Velocidad' "$velocidad MHz" }
    }

    if ($instaladaGB -lt 7.5) {
        Add-Hallazgo PROBLEMA 'Poca RAM' ('Solo hay {0:N0} GB de RAM. Al llenarse, Windows usa el disco como memoria y todo se congela.' -f $instaladaGB) `
            'Cierra el navegador y otros programas antes de jugar. La solución real es ampliar a 16 GB (es de las mejoras más baratas).'
    } elseif ($instaladaGB -lt 15) {
        Add-Hallazgo AVISO 'RAM justa' ('{0:N0} GB de RAM alcanzan justo: un juego actual + navegador + Discord pueden llenarla.' -f $instaladaGB) `
            'Cierra lo que no uses mientras juegas. Si se te queda corta a menudo, amplía a 16 GB.'
    } else {
        Write-Ok 'Cantidad de RAM suficiente.'
    }
    if ($usoPct -gt 85) {
        Add-Hallazgo PROBLEMA 'RAM llena' ('La RAM está al {0:N0} % ahora mismo.' -f $usoPct) `
            'Cierra programas que no estés usando (mira "Procesos que más consumen").'
    }
    if ($modulos.Count -eq 1 -and -not $esPortatil) {
        Add-Hallazgo AVISO 'Un solo módulo de RAM' 'Hay un solo módulo de RAM (single channel): la memoria rinde aprox. la mitad y se nota en juegos.' `
            'Usa 2 módulos iguales, en las ranuras que indica el manual de la placa (normalmente la 2 y la 4).'
    }
}

Invoke-Seccion 'Memoria virtual (archivo de paginación)' {
    $paginacion = @(Get-CimInstance Win32_PageFileUsage)
    if ($paginacion.Count -eq 0) {
        Add-Hallazgo PROBLEMA 'Paginación desactivada' 'El archivo de paginación está desactivado: cuando la RAM se llena, los programas se cuelgan o se cierran de golpe.' `
            'Ejecuta optimizar.ps1 (lo deja "administrado por el sistema").'
        return
    }
    foreach ($p in $paginacion) {
        Write-Dato $p.Name ('{0:N1} GB asignados, {1:N0} MB en uso (pico {2:N0} MB)' -f ($p.AllocatedBaseSize / 1KB), $p.CurrentUsage, $p.PeakUsage)
    }
    if ($cs.AutomaticManagedPagefile) {
        Write-Ok 'Administrado automáticamente por Windows.'
    } else {
        Add-Hallazgo AVISO 'Paginación manual' 'El tamaño de la paginación está fijado a mano; si se queda corto provoca congelamientos.' `
            'Lo más seguro es dejarlo "administrado por el sistema" (optimizar.ps1 lo hace).'
    }
}

Invoke-Seccion 'Discos' {
    $discoSistema = $null
    try { $discoSistema = (Get-Partition -DriveLetter $env:SystemDrive[0] | Get-Disk).Number } catch { }

    foreach ($d in Get-PhysicalDisk | Sort-Object DeviceId) {
        $mt = "$($d.MediaType)"
        $tipo = if ($mt -in 'SSD', '4') { 'SSD' } elseif ($mt -in 'HDD', '3') { 'HDD' } else { 'desconocido' }
        $esSistema = "$($d.DeviceId)" -eq "$discoSistema"
        $etiqueta = if ($esSistema) { "Disco $($d.DeviceId) (Windows)" } else { "Disco $($d.DeviceId)" }
        Write-Dato $etiqueta ('{0} - {1}, {2}, {3:N0} GB' -f $d.FriendlyName, $tipo, $d.BusType, ($d.Size / 1GB))

        $salud = "$($d.HealthStatus)"
        if ($salud -notin 'Healthy', '0') {
            Add-Hallazgo PROBLEMA 'Disco con fallos' "Windows marca el disco $($d.FriendlyName) con estado de salud '$salud'." `
                'Haz copia de seguridad de tus archivos YA y planea cambiar ese disco.'
        }

        $contadores = $null
        if ($esAdmin) { try { $contadores = $d | Get-StorageReliabilityCounter } catch { } }
        if ($contadores) {
            if ($contadores.Temperature) { Write-Dato '  Temperatura' "$($contadores.Temperature) °C" }
            if ($contadores.Wear) {
                Write-Dato '  Desgaste' "$($contadores.Wear) %"
                if ($contadores.Wear -ge 90) {
                    Add-Hallazgo PROBLEMA 'SSD gastado' "El SSD $($d.FriendlyName) está al $($contadores.Wear) % de su vida útil." `
                        'Haz copia de seguridad y planea cambiarlo.'
                }
            }
        }

        if ($esSistema -and $tipo -eq 'HDD') {
            Add-Hallazgo PROBLEMA 'Windows en disco mecánico' 'Windows está instalado en un disco mecánico (HDD): es la causa nº 1 de congelamientos con "disco al 100 %".' `
                'Pasar Windows y tus juegos a un SSD es la mejora más notable que puedes hacer (un SSD de 500 GB es barato).'
        }
    }

    foreach ($v in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        if (-not $v.Size) { continue }
        $pct = 100 * $v.FreeSpace / $v.Size
        Write-Dato "Unidad $($v.DeviceID)" ('{0:N0} GB libres de {1:N0} GB ({2:N0} %)' -f ($v.FreeSpace / 1GB), ($v.Size / 1GB), $pct)
        if ($v.DeviceID -ne $env:SystemDrive) { continue }
        if ($pct -lt 10 -or $v.FreeSpace -lt 15GB) {
            Add-Hallazgo PROBLEMA 'Disco lleno' ('Solo quedan {0:N0} GB libres en {1}. Windows necesita espacio para la memoria virtual y las actualizaciones.' -f ($v.FreeSpace / 1GB), $v.DeviceID) `
                'Libera espacio: desinstala juegos/programas que no uses y ejecuta "Liberador de espacio en disco" > "Limpiar archivos del sistema".'
        } elseif ($pct -lt 20) {
            Add-Hallazgo AVISO 'Poco espacio libre' ('Queda el {0:N0} % libre en {1}.' -f $pct, $v.DeviceID) `
                'Intenta mantener al menos un 20 % libre en el disco de Windows.'
        } else {
            Write-Ok "Espacio libre suficiente en $($v.DeviceID)."
        }
    }
}

Invoke-Seccion 'Tarjeta gráfica' {
    foreach ($g in Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Remote|Virtual|Parsec' }) {
        Write-Dato 'Modelo' $g.Name
        Write-Dato 'Driver' ('{0} (del {1:dd/MM/yyyy})' -f $g.DriverVersion, $g.DriverDate)
        if ($g.Name -match 'Basic Display|básico de Microsoft|Standard VGA|VGA estándar') {
            Add-Hallazgo PROBLEMA 'Sin driver de video' "No hay driver de video instalado ($($g.Name))." `
                'Instala el driver desde la web del fabricante: nvidia.com, amd.com o intel.com.'
        } elseif ($g.DriverDate -and $g.DriverDate -lt (Get-Date).AddMonths(-12)) {
            Add-Hallazgo AVISO 'Driver de video viejo' ('El driver de {0} es de {1:MM/yyyy}.' -f $g.Name, $g.DriverDate) `
                'Actualízalo desde la web oficial (nvidia.com, amd.com o intel.com), no desde Windows Update: los drivers nuevos corrigen tirones en juegos.'
        } else {
            Write-Ok 'Driver reciente.'
        }
    }
}

Invoke-Seccion 'Energía' {
    $activo = powercfg /getactivescheme | Out-String
    $guid = if ($activo -match '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}') { $Matches[0].ToLower() }
    $nombre = if ($activo -match '\(([^)]+)\)') { $Matches[1] } else { $guid }
    Write-Dato 'Plan activo' $nombre
    switch ($guid) {
        'a1841308-3541-4fab-bc81-f71556f20b4a' {
            Add-Hallazgo PROBLEMA 'Plan de ahorro de energía' 'Está activo el plan "Economizador": limita el procesador a propósito.' `
                'Ejecuta optimizar.ps1 o elige "Alto rendimiento" en Panel de control > Opciones de energía.'
            break
        }
        '8c5e7fda-e8bf-4a96-9a85-cf2c25edf3d8' { Write-Ok 'Alto rendimiento.'; break }
        'e9a42b02-d5df-448d-aa00-03f14749eb61' { Write-Ok 'Máximo rendimiento.'; break }
        { $nombre -match 'Alto rendimiento|Máximo rendimiento|High performance|Ultimate performance' } { Write-Ok "$nombre."; break }
        default {
            Add-Hallazgo AVISO 'Plan de energía' 'Plan "Equilibrado" (u otro): el procesador sube y baja de velocidad todo el rato, lo que puede causar microtirones.' `
                'optimizar.ps1 puede activar "Alto rendimiento".'
        }
    }
    if ($esPortatil) {
        $bateria = Get-CimInstance Win32_Battery | Select-Object -First 1
        if ($bateria.BatteryStatus -eq 1) {
            Add-Hallazgo AVISO 'Funcionando con batería' 'El portátil está usando la batería: Windows y la tarjeta gráfica bajan el rendimiento para ahorrar.' `
                'Juega siempre con el cargador conectado.'
        }
    }
}

Invoke-Seccion 'Xbox Game Bar y Modo de juego' {
    function Get-Valor([string]$Ruta, [string]$Nombre) {
        if (-not (Test-Path $Ruta)) { return $null }
        $p = Get-ItemProperty -Path $Ruta -Name $Nombre -ErrorAction SilentlyContinue
        if ($p) { return $p.$Nombre }
    }
    $grabando = @(
        Get-Valor 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
        Get-Valor 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
        Get-Valor 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled'
    ) -contains 1
    if ($grabando) {
        Add-Hallazgo AVISO 'Captura de Xbox Game Bar' 'La captura de juegos de Xbox Game Bar está activada; grabar en segundo plano causa tirones.' `
            'optimizar.ps1 la desactiva (OBS, ShadowPlay y Discord siguen funcionando).'
    } else {
        Write-Ok 'Captura de Xbox Game Bar desactivada.'
    }
    if ((Get-Valor 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -eq 0) {
        Add-Hallazgo AVISO 'Modo de juego' 'El Modo de juego de Windows está desactivado.' `
            'Actívalo en Configuración > Juegos > Modo de juego, o con optimizar.ps1.'
    } else {
        Write-Ok 'Modo de juego activado.'
    }
}

Invoke-Seccion 'Programas que arrancan con Windows' {
    # El Administrador de tareas guarda lo que deshabilitaste en StartupApproved:
    # si el primer byte del valor es impar, ese programa no arranca.
    $deshabilitados = @{}
    foreach ($raiz in 'HKCU:', 'HKLM:') {
        foreach ($sub in 'Run', 'Run32', 'StartupFolder') {
            $ruta = "$raiz\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\$sub"
            if (-not (Test-Path $ruta)) { continue }
            $clave = Get-Item $ruta
            foreach ($nombre in $clave.GetValueNames()) {
                $datos = $clave.GetValue($nombre)
                if ($datos -is [byte[]] -and $datos.Length -gt 0 -and ($datos[0] % 2) -eq 1) { $deshabilitados[$nombre] = $true }
            }
        }
    }
    $activos = @(Get-CimInstance Win32_StartupCommand |
        Where-Object { -not $deshabilitados.ContainsKey($_.Name) -and -not $deshabilitados.ContainsKey($_.Command) } |
        Sort-Object Name -Unique)
    foreach ($programa in $activos) { Write-Linea "   - $($programa.Name)" }
    if ($activos.Count -gt 8) {
        Add-Hallazgo AVISO 'Muchos programas al inicio' "$($activos.Count) programas arrancan con Windows y se quedan gastando RAM y procesador." `
            'Ctrl+Shift+Esc > Aplicaciones de arranque: deshabilita lo que no necesites al encender (Steam, Epic, Discord, Spotify, OneDrive... se pueden abrir a mano). No toques el antivirus ni los drivers de audio o touchpad.'
    } else {
        Write-Ok "$($activos.Count) programas al inicio."
    }
}

Invoke-Seccion 'Procesos que más consumen ahora mismo' {
    $segundos = 3
    # Sin permisos de administrador algunos procesos del sistema no dejan leer su CPU.
    function Get-TiempoCpu($Proceso) { try { $Proceso.CPU } catch { $null } }
    $antes = @{}
    foreach ($p in Get-Process) {
        $t = Get-TiempoCpu $p
        if ($null -ne $t) { $antes[$p.Id] = $t }
    }
    Start-Sleep -Seconds $segundos
    $nucleos = [Environment]::ProcessorCount
    $muestras = foreach ($p in Get-Process) {
        $t = Get-TiempoCpu $p
        $cpu = 0
        if ($null -ne $t -and $antes.ContainsKey($p.Id)) { $cpu = 100 * ($t - $antes[$p.Id]) / ($segundos * $nucleos) }
        [pscustomobject]@{ Nombre = $p.ProcessName; Cpu = $cpu; Ram = $p.WorkingSet64 }
    }
    # Agrupa por nombre: el navegador, por ejemplo, abre decenas de procesos.
    $porPrograma = $muestras | Where-Object { $_.Nombre -ne 'Idle' } | Group-Object Nombre | ForEach-Object {
        [pscustomobject]@{
            Nombre   = $_.Name
            Cantidad = $_.Count
            Cpu      = ($_.Group | Measure-Object Cpu -Sum).Sum
            Ram      = ($_.Group | Measure-Object Ram -Sum).Sum
        }
    }
    Write-Linea '  Por memoria RAM:'
    foreach ($p in $porPrograma | Sort-Object Ram -Descending | Select-Object -First 8) {
        $extra = if ($p.Cantidad -gt 1) { "  ($($p.Cantidad) procesos)" } else { '' }
        Write-Linea ('   {0,-30} {1,8:N0} MB{2}' -f $p.Nombre, ($p.Ram / 1MB), $extra)
    }
    Write-Linea "  Por procesador (últimos $segundos s):"
    foreach ($p in $porPrograma | Sort-Object Cpu -Descending | Select-Object -First 5) {
        Write-Linea ('   {0,-30} {1,8:N1} %' -f $p.Nombre, $p.Cpu)
    }
}

Invoke-Seccion "Errores registrados en los últimos $DiasEventos días" {
    $desde = (Get-Date).AddDays(-$DiasEventos)
    $revisiones = @(
        @{
            Nivel = 'PROBLEMA'; Tema = 'Congelamientos totales o apagados de golpe'
            Filtros = @(@{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41 })
            Solucion = 'Si la PC se queda congelada y tienes que apagarla con el botón, suele ser temperatura, fuente de poder o driver de video. Revisa temperaturas con HWiNFO y actualiza el driver de video.'
        }
        @{
            Nivel = 'PROBLEMA'; Tema = 'Pantallazos azules'
            Filtros = @(@{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001 })
            Solucion = 'Anota el código del pantallazo y búscalo. Suelen ser drivers o RAM defectuosa: prueba "Diagnóstico de memoria de Windows" desde el menú Inicio.'
        }
        @{
            Nivel = 'PROBLEMA'; Tema = 'El driver de video dejó de responder'
            Filtros = @(
                @{ LogName = 'System'; ProviderName = 'Display'; Id = 4101 }
                @{ LogName = 'System'; ProviderName = 'nvlddmkm'; Level = 2 }
                @{ LogName = 'System'; ProviderName = 'amdkmdag'; Level = 2 }
            )
            Solucion = 'La pantalla se congela unos segundos y vuelve: reinstala limpio el driver de video (DDU + driver nuevo). Si sigue, revisa la temperatura de la gráfica y la fuente de poder.'
        }
        @{
            Nivel = 'PROBLEMA'; Tema = 'Errores o bloqueos del disco'
            Filtros = @(
                @{ LogName = 'System'; ProviderName = 'disk'; Id = 7, 11, 51, 153 }
                @{ LogName = 'System'; ProviderName = 'storahci'; Id = 129 }
                @{ LogName = 'System'; ProviderName = 'stornvme'; Id = 11, 129 }
            )
            Solucion = 'El disco deja de responder unos segundos (eso congela todo). Haz copia de seguridad, revisa el cable SATA y la salud del disco con CrystalDiskInfo.'
        }
        @{
            Nivel = 'PROBLEMA'; Tema = 'Windows se quedó sin memoria'
            Filtros = @(@{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Resource-Exhaustion-Detector'; Id = 2004 })
            Solucion = 'Cierra programas mientras juegas, deja la paginación en automático (optimizar.ps1) y considera ampliar la RAM.'
        }
        @{
            Nivel = 'AVISO'; Tema = 'Errores de hardware (WHEA)'
            Filtros = @(@{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger' })
            Solucion = 'Indican inestabilidad de procesador, RAM o PCIe. Si tienes overclock o XMP/EXPO activado, prueba a quitarlo; si sigue, revisa temperaturas y fuente.'
        }
        @{
            Nivel = 'AVISO'; Tema = 'Programas que se colgaron'; MostrarProgramas = $true
            Filtros = @(@{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002 })
            Solucion = 'Actualiza o reinstala esos programas. Si es siempre el mismo juego, verifica sus archivos desde Steam/Epic.'
        }
    )

    foreach ($rev in $revisiones) {
        $eventos = @()
        foreach ($f in $rev.Filtros) {
            $filtro = $f.Clone()
            $filtro.StartTime = $desde
            try { $eventos += @(Get-WinEvent -FilterHashtable $filtro -ErrorAction SilentlyContinue) } catch { }
        }
        if ($eventos.Count -eq 0) {
            Write-Ok "$($rev.Tema): ninguno."
            continue
        }
        $ultimo = ($eventos | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
        $detalle = '{0}: {1} veces (la última el {2:dd/MM/yyyy HH:mm}).' -f $rev.Tema, $eventos.Count, $ultimo
        if ($rev.MostrarProgramas) {
            $programas = $eventos | ForEach-Object { $_.Properties[0].Value } | Group-Object |
                Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name) ($($_.Count))" }
            $detalle += ' Sobre todo: ' + ($programas -join ', ') + '.'
        }
        Add-Hallazgo $rev.Nivel $rev.Tema $detalle $rev.Solucion
    }
}

Write-Titulo 'RESUMEN'
$ordenados = @($script:Hallazgos | Sort-Object { if ($_.Nivel -eq 'PROBLEMA') { 0 } else { 1 } })
if ($ordenados.Count -eq 0) {
    Write-Linea '  No encontré problemas evidentes en Windows.' Green
} else {
    $problemas = @($ordenados | Where-Object Nivel -eq 'PROBLEMA').Count
    Write-Linea ("  {0} problema(s) y {1} aviso(s). Empieza por los problemas:" -f $problemas, ($ordenados.Count - $problemas))
    foreach ($h in $ordenados) {
        Write-Linea
        Write-Linea "  [$($h.Nivel)] $($h.Tema)" $(if ($h.Nivel -eq 'PROBLEMA') { 'Red' } else { 'Yellow' })
        Write-Linea "    Qué pasa:  $($h.Detalle)"
        Write-Linea "    Qué hacer: $($h.Solucion)"
    }
}
Write-Linea
Write-Linea '  Windows no informa bien las temperaturas: si los tirones aparecen tras un rato jugando,' DarkGray
Write-Linea '  usa HWiNFO (gratis) y comprueba que el procesador no pase de 90 °C ni la gráfica de 85 °C.' DarkGray

try {
    Set-Content -Path $Informe -Value $script:Lineas.ToArray() -Encoding UTF8
    Write-Host ''
    Write-Host "Informe guardado en: $Informe" -ForegroundColor White
} catch {
    Write-Host "No se pudo guardar el informe: $($_.Exception.Message)" -ForegroundColor Yellow
}
