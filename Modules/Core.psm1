#Requires -Version 2.0
# ==============================================================================
# Core.psm1  -  Funciones base compartidas por todos los modulos
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   El "nucleo" del proyecto. Contiene las funciones que usan TODOS los demas
#   modulos: como mostrar mensajes con color, pausar la pantalla, el menu
#   principal, el helper de progreso, y la logica de carga y ejecucion de
#   perfiles JSON.
#
#   Debe cargarse PRIMERO en GhostCleaner.ps1 porque los demas modulos
#   dependen de Write-GC e Invoke-WithProgress definidos aqui.
#
# NUEVO EN ESTA VERSION:
#   - Initialize-GhostCleaner acepta -RootPath para conocer la raiz del proyecto
#   - Load-GCProfile: lee un JSON de Profiles\ y lo convierte en objeto PS
#   - Invoke-Profile: ejecuta todas las acciones habilitadas en el perfil
#
# ==============================================================================


# ==============================================================================
# EnsureAdmin
# ==============================================================================
# Detiene la ejecucion si el usuario no tiene privilegios de Administrador.
# ==============================================================================

function EnsureAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)

    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Ejecuta como Administrador.'
    }
}


# ==============================================================================
# Initialize-GhostCleaner
# ==============================================================================
# Prepara el entorno: crea la carpeta Backup\ y define variables globales.
#
# PARAMETROS:
#   $RootPath : ruta raiz del proyecto (se la pasa GhostCleaner.ps1 con
#               $PSScriptRoot para que este modulo no tenga que adivinarla)
#
# VARIABLES GLOBALES QUE DEFINE:
#   $global:GC_Root   : ruta raiz del proyecto
#   $global:GC_Backup : ruta a la carpeta Backup\
#   $global:GC_Config : null hasta que se cargue un perfil con Load-GCProfile
# ==============================================================================

function Initialize-GhostCleaner {
    param(
        [Parameter(Mandatory = $true)] [string]$RootPath,
        # -DryRun: simula la ejecucion. Invoke-WithProgress no llega a invocar
        # el scriptblock real, solo informa de lo que HARIA. Util para revisar
        # un perfil nuevo o para auditorias en equipos de produccion.
        [switch]$DryRun,
        # -Silent: modo desatendido para GPO/SCCM. Quita pausas de teclado y
        # reduce el ruido en pantalla (el log a fichero sigue siendo completo).
        [switch]$Silent
    )

    $global:GC_Root    = $RootPath
    $global:GC_Backup  = Join-Path $RootPath 'Backup'
    $global:GC_Logs    = Join-Path $RootPath 'Logs'
    $global:GC_Config  = $null   # Se rellena cuando se carga un perfil
    $global:GC_DryRun  = [bool]$DryRun
    $global:GC_Silent  = [bool]$Silent
    # Acumula un resumen de cada operacion (OK / Fallo / Omitida) para poder
    # generar despues un informe con Export-GCReport.
    $global:GC_Report  = New-Object System.Collections.Generic.List[Object]

    if (-not (Test-Path $global:GC_Backup)) {
        New-Item $global:GC_Backup -ItemType Directory | Out-Null
    }
    if (-not (Test-Path $global:GC_Logs)) {
        New-Item $global:GC_Logs -ItemType Directory | Out-Null
    }

    Initialize-GCLogFile
}


# ==============================================================================
# Initialize-GCLogFile
# ==============================================================================
# Crea el archivo de log de esta sesion y rota los antiguos.
#
# POR QUE UN LOG EN DISCO Y NO SOLO EN PANTALLA:
#   La consola se cierra y se pierde todo. Para uso en empresa (o para mirar
#   "que hizo esto el mes pasado" en tu propio PC) interesa dejar constancia
#   en un archivo con fecha y hora de cada linea.
#
# ROTACION:
#   Cada ejecucion crea un archivo nuevo (GhostCleaner_AAAAMMDD_HHmmss.log).
#   Get-ChildItem + Sort-Object + Select-Object -Skip nos quedamos solo con
#   los $KeepLogs mas recientes y borramos el resto con Remove-Item.
# ==============================================================================

function Initialize-GCLogFile {
    param(
        [int]$KeepLogs = 20
    )

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $global:GC_LogFile = Join-Path $global:GC_Logs ('GhostCleaner_' + $stamp + '.log')

    ('==== GhostCleaner - sesion iniciada ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ====') |
        Out-File -FilePath $global:GC_LogFile -Encoding UTF8 -Append

    $oldLogs = Get-ChildItem -Path $global:GC_Logs -Filter '*.log' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $KeepLogs

    foreach ($old in $oldLogs) {
        Remove-Item -Path $old.FullName -Force -ErrorAction SilentlyContinue
    }
}


# ==============================================================================
# Write-GC
# ==============================================================================
# Funcion de logging centralizada con colores por nivel.
#
# NIVELES:
#   Info    -> cyan    : algo esta ocurriendo
#   Action  -> verde   : accion completada con exito
#   Warning -> amarillo: algo no fue como esperabamos, pero no es fatal
#   Error   -> rojo    : algo fallo
# ==============================================================================

function Write-GC {
    param(
        [Parameter(Mandatory = $true)] [string]$Message,
        [ValidateSet('Info','Action','Warning','Error')] [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Action'  { 'Green'  }
        'Warning' { 'Yellow' }
        'Error'   { 'Red'    }
        default   { 'Cyan'   }
    }

    # En modo -Silent no pintamos en pantalla (lo necesita GPO/SCCM, donde no
    # hay nadie mirando la consola), pero el log a fichero se escribe SIEMPRE.
    if (-not $global:GC_Silent) {
        Write-Host ('[GhostCleaner] ' + $Message) -ForegroundColor $color
    }

    # $global:GC_LogFile solo existe tras Initialize-GhostCleaner. El "if"
    # evita un error si alguien llama Write-GC antes de inicializar el modulo.
    if ($global:GC_LogFile) {
        $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] [' + $Level + '] ' + $Message
        # -ErrorAction SilentlyContinue: si el disco esta lleno o el archivo
        # esta bloqueado, preferimos perder una linea de log a romper el script.
        $line | Out-File -FilePath $global:GC_LogFile -Encoding UTF8 -Append -ErrorAction SilentlyContinue
    }
}


# ==============================================================================
# Pause-ForContinue
# ==============================================================================
# Pausa hasta que el usuario pulse una tecla. Se usa al final de cada opcion
# del menu para que el usuario pueda leer los resultados antes de volver.
# ==============================================================================

function Pause-ForContinue {
    Write-Host ''
    Write-Host 'Pulsa cualquier tecla para volver al menu...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}


# ==============================================================================
# Invoke-WithProgress
# ==============================================================================
# Envuelve la ejecucion de cualquier funcion mostrando inicio y resultado.
#
# USA .Invoke() EN LUGAR DE & $ScriptBlock porque & crea un scope hijo donde
# las funciones de otros modulos pueden no resolverse. .Invoke() ejecuta en
# el scope de sesion actual donde -Global ya registro todo.
# ==============================================================================

function Invoke-WithProgress {
    param(
        [Parameter(Mandatory = $true)] [string]$OperationName,
        [Parameter(Mandatory = $true)] [scriptblock]$ScriptBlock
    )

    # Modo simulacion: ni siquiera invocamos el scriptblock. Solo dejamos
    # constancia de que ESTA operacion se habria ejecutado. Pensado para
    # revisar un perfil antes de aplicarlo de verdad (".\GhostCleaner.ps1
    # -Profile Aggressive -DryRun").
    if ($global:GC_DryRun) {
        Write-GC -Message ('[DRY-RUN] Se omite, simulacion activa: ' + $OperationName) -Level 'Warning'
        $global:GC_Report.Add([PSCustomObject]@{
            Operacion = $OperationName
            Resultado = 'Simulado (DryRun)'
            Detalle   = 'No se aplico ningun cambio real'
            Hora      = Get-Date
        })
        return $true
    }

    Write-GC -Message $OperationName -Level 'Action'

    try {
        $ScriptBlock.Invoke()
        Write-GC -Message ('OK: ' + $OperationName) -Level 'Info'
        $global:GC_Report.Add([PSCustomObject]@{
            Operacion = $OperationName
            Resultado = 'OK'
            Detalle   = ''
            Hora      = Get-Date
        })
        return $true
    } catch {
        Write-GC -Message ('Fallo: ' + $OperationName + ' -> ' + $_.Exception.Message) -Level 'Error'
        $global:GC_Report.Add([PSCustomObject]@{
            Operacion = $OperationName
            Resultado = 'Fallo'
            Detalle   = $_.Exception.Message
            Hora      = Get-Date
        })
        return $false
    }
}


# ==============================================================================
# Load-GCProfile
# ==============================================================================
# Lee el archivo JSON del perfil indicado y lo guarda en $global:GC_Config.
#
# PARAMETROS:
#   $ProfileName : nombre del perfil sin extension (Safe, Balanced, Aggressive
#                  o cualquier otro que el usuario haya creado en Profiles\)
#
# COMO FUNCIONA:
#   1. Construye la ruta: <raiz>\Profiles\<nombre>.json
#   2. Lee el archivo con Get-Content y lo une en un string con -join
#      (necesario para PS 2.0; en PS 3+ se puede usar directamente)
#   3. ConvertFrom-Json convierte el texto JSON en un objeto de PowerShell
#      con propiedades accesibles como $obj.privacy.enabled
#   4. Guarda el resultado en $global:GC_Config para que todos los modulos
#      puedan consultarlo
#
# COMPATIBILIDAD PS 2.0:
#   ConvertFrom-Json no existe en PS 2.0 (llego en PS 3.0). En PS 2.0 usamos
#   JavaScriptSerializer de .NET, que si esta disponible desde Win 7.
# ==============================================================================

function Load-GCProfile {
    param(
        [Parameter(Mandatory = $true)] [string]$ProfileName
    )

    $profilePath = Join-Path $global:GC_Root ('Profiles\' + $ProfileName + '.json')

    if (-not (Test-Path $profilePath)) {
        throw ('Perfil no encontrado: ' + $profilePath + '. Los perfiles disponibles estan en la carpeta Profiles\.')
    }

    Write-GC -Message ('Cargando perfil: ' + $ProfileName + ' (' + $profilePath + ')') -Level 'Action'

    try {
        $jsonText = (Get-Content -Path $profilePath -ErrorAction Stop) -join "`n"

        # Intentamos ConvertFrom-Json (PS 3.0+) y si no existe usamos .NET
        $convertCmd = Get-Command 'ConvertFrom-Json' -ErrorAction SilentlyContinue

        if ($convertCmd) {
            # PS 3.0 y superior: cmdlet nativo
            $global:GC_Config = $jsonText | ConvertFrom-Json
        } else {
            # PS 2.0 / .NET 3.5: JavaScriptSerializer
            Add-Type -AssemblyName 'System.Web.Extensions'
            $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            # En PS 2.0 ConvertFrom-Json no existe, pero el serializer devuelve
            # un Hashtable; lo convertimos a PSCustomObject para acceso uniforme
            $dict = $serializer.DeserializeObject($jsonText)
            $global:GC_Config = [PSCustomObject]$dict
        }

        Write-GC -Message ('Perfil cargado correctamente: ' + $ProfileName) -Level 'Info'
    } catch {
        throw ('Error al leer el perfil ' + $ProfileName + ': ' + $_.Exception.Message)
    }
}


# ==============================================================================
# Get-ProfileValue
# ==============================================================================
# Helper para leer un valor del perfil de forma segura.
# Devuelve $Default si la propiedad no existe en el JSON (compatibilidad con
# perfiles mas antiguos o incompletos que no tengan todas las claves).
#
# PARAMETROS:
#   $Section  : nombre de la seccion en el JSON (p.ej. "privacy")
#   $Key      : nombre del campo dentro de la seccion (p.ej. "enabled")
#   $Default  : valor a devolver si no se encuentra (por defecto $false)
#
# EJEMPLO DE USO:
#   $ok = Get-ProfileValue -Section 'privacy' -Key 'enabled' -Default $false
# ==============================================================================

function Get-ProfileValue {
    param(
        [Parameter(Mandatory = $true)] [string]$Section,
        [Parameter(Mandatory = $true)] [string]$Key,
        $Default = $false
    )

    if ($null -eq $global:GC_Config) { return $Default }

    $section = $global:GC_Config.$Section
    if ($null -eq $section) { return $Default }

    $value = $section.$Key
    if ($null -eq $value) { return $Default }

    return $value
}


# ==============================================================================
# Test-GCProfile
# ==============================================================================
# Valida que un perfil JSON tiene la forma minima esperada ANTES de ejecutarlo.
# Pensado sobre todo para perfiles personalizados creados a mano: un JSON mal
# formado o con una secciones distinta no debe tirar el script a mitad de
# camino, sino avisar claramente desde el principio.
#
# QUE COMPRUEBA:
#   - Que el archivo existe y el JSON es valido (ya lo intenta Load-GCProfile,
#     aqui solo confirmamos que el objeto resultante no es $null)
#   - Que las secciones conocidas, si existen, tienen un campo "enabled"
#     booleano (si alguien escribe "enabled": "true" como texto en vez de
#     true, lo detectamos aqui en lugar de que falle mas adelante sin avisar)
#
# DEVUELVE:
#   $true si el perfil es valido. Si no, escribe los problemas encontrados
#   con Write-GC -Level 'Warning' y devuelve $false.
# ==============================================================================

function Test-GCProfile {
    param(
        [Parameter(Mandatory = $true)] [string]$ProfileName
    )

    $problemas = @()
    $seccionesConocidas = @('privacy', 'services', 'tasks', 'hosts', 'optimizer', 'security', 'apps', 'browsers', 'firewallBlock', 'plugins')

    try {
        Load-GCProfile -ProfileName $ProfileName
    } catch {
        Write-GC -Message ('Perfil invalido: ' + $_.Exception.Message) -Level 'Warning'
        return $false
    }

    if ($null -eq $global:GC_Config) {
        Write-GC -Message 'El perfil se cargo vacio.' -Level 'Warning'
        return $false
    }

    foreach ($seccion in $seccionesConocidas) {
        $valor = $global:GC_Config.$seccion
        if ($null -ne $valor) {
            # $valor.enabled puede no existir; en ese caso $null -is [bool] es $false,
            # que es justo lo que queremos detectar como "falta el campo enabled".
            if ($valor.enabled -isnot [bool]) {
                $problemas += ('Seccion "' + $seccion + '": falta "enabled" o no es true/false.')
            }
        }
    }

    if ($problemas.Count -gt 0) {
        Write-GC -Message ('El perfil "' + $ProfileName + '" tiene avisos:') -Level 'Warning'
        foreach ($p in $problemas) {
            Write-GC -Message ('  - ' + $p) -Level 'Warning'
        }
        return $false
    }

    Write-GC -Message ('Perfil "' + $ProfileName + '" validado correctamente.') -Level 'Info'
    return $true
}


# ==============================================================================
# Test-GCDomainJoined
# ==============================================================================
# Comprueba si el equipo pertenece a un dominio de Active Directory.
#
# POR QUE IMPORTA:
#   En un equipo de dominio, muchos de estos ajustes (telemetria, Defender,
#   tareas programadas) pueden estar gestionados por GPO. Si GhostCleaner
#   cambia algo que la politica de grupo vuelve a poner como estaba en el
#   siguiente reinicio o al refrescar politicas (gpupdate), el cambio no
#   "se pierde" por un bug del script: lo esta sobreescribiendo el dominio.
#   Avisamos de esto en vez de dejar que el usuario piense que GhostCleaner
#   no funciono.
#
# COMO LO DETECTA:
#   Win32_ComputerSystem.PartOfDomain es una propiedad WMI que indica
#   exactamente esto. Get-WmiObject existe desde PS 2.0 (en PS 3.0+ tambien
#   existe Get-CimInstance, mas moderno, pero usamos el mas compatible).
# ==============================================================================

function Test-GCDomainJoined {
    try {
        $cs = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        return [bool]$cs.PartOfDomain
    } catch {
        # Si WMI falla por lo que sea, asumimos que no esta en dominio en vez
        # de interrumpir el script por un dato que solo es informativo.
        return $false
    }
}


# ==============================================================================
# New-GCRestorePoint
# ==============================================================================
# Crea un punto de restauracion de Windows antes de tocar nada. Es la red de
# seguridad "a nivel sistema": si algo sale mal de verdad, el usuario puede
# restaurar Windows entero al estado anterior desde "Restaurar sistema".
#
# QUE ES UN SCRIPTBLOCK / POR QUE Checkpoint-Computer:
#   Checkpoint-Computer es un cmdlet nativo de Windows (modulo Microsoft.PowerShell.Management)
#   que envuelve la misma funcion que usa el Panel de Control. No esta disponible
#   en todas las ediciones (p.ej. Windows Server lo desactiva por defecto) ni si
#   "Proteccion del sistema" esta apagada, por eso todo va en try/catch.
#
# LIMITE DE WINDOWS (no de este script):
#   Windows solo permite UN punto de restauracion cada 24h por defecto fuera de
#   instalaciones de programas. Si ya se creo uno hoy, esta funcion lo detecta
#   y no lo trata como error real.
# ==============================================================================

function New-GCRestorePoint {
    param(
        [string]$Description = 'GhostCleaner - antes de aplicar perfil'
    )

    if ($global:GC_DryRun) {
        Write-GC -Message '[DRY-RUN] Se omite la creacion del punto de restauracion.' -Level 'Warning'
        return $true
    }

    try {
        Write-GC -Message 'Creando punto de restauracion del sistema...' -Level 'Action'
        # 'MODIFY_SETTINGS' es el tipo de evento que mejor describe lo que hacemos.
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-GC -Message 'Punto de restauracion creado.' -Level 'Info'
        return $true
    } catch {
        # No interrumpimos el script por esto: es una red de seguridad extra,
        # no un requisito para aplicar el perfil. Solo avisamos.
        Write-GC -Message ('No se pudo crear el punto de restauracion: ' + $_.Exception.Message) -Level 'Warning'
        Write-GC -Message 'Continuando sin punto de restauracion (revisa que "Proteccion del sistema" este activa).' -Level 'Warning'
        return $false
    }
}


# ==============================================================================
# Backup-GCSystemState
# ==============================================================================
# Guarda en Backup\ una "foto" del estado actual ANTES de cambiar nada:
#   - El archivo hosts original, tal cual esta ahora
#   - El estado (StartType) de los servicios que el perfil va a tocar
#   - Las claves de registro de telemetria que Privacy.psm1 va a modificar
#
# POR QUE ESTO Y NO SOLO Restore.psm1:
#   Restore.psm1 deshace cambios conocidos a base hardcodeada. Esta funcion
#   en cambio guarda el estado REAL de ESTE equipo en ESTE momento, en un
#   archivo con fecha, asi que sirve como referencia exacta de "como estaba
#   esto antes de tocarlo", utilil sobre todo en auditorias de empresa.
#
# FORMATO: JSON plano, facil de leer a mano o de parsear con otro script.
# ==============================================================================

function Backup-GCSystemState {
    if ($global:GC_DryRun) {
        Write-GC -Message '[DRY-RUN] Se omite el backup de estado previo.' -Level 'Warning'
        return
    }

    Write-GC -Message 'Guardando backup del estado previo del sistema...' -Level 'Action'

    $stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $global:GC_Backup ('SystemState_' + $stamp + '.json')

    $estado = New-Object PSObject

    # --- Archivo hosts original, linea por linea -----------------------------
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    if (Test-Path $hostsPath) {
        $estado | Add-Member -MemberType NoteProperty -Name 'HostsOriginal' -Value (Get-Content -Path $hostsPath -ErrorAction SilentlyContinue)
    }

    # --- Estado de servicios relevantes ---------------------------------------
    $serviciosAVigilar = @('DiagTrack', 'dmwappushservice', 'SysMain')
    $estadoServicios = @()
    foreach ($s in $serviciosAVigilar) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc) {
            $estadoServicios += [PSCustomObject]@{
                Nombre       = $s
                Estado       = $svc.Status.ToString()
                TipoArranque = (Get-WmiObject -Class Win32_Service -Filter ("Name='" + $s + "'") -ErrorAction SilentlyContinue).StartMode
            }
        }
    }
    $estado | Add-Member -MemberType NoteProperty -Name 'Servicios' -Value $estadoServicios

    # --- Claves de registro de telemetria que Privacy.psm1 toca ---------------
    $clavesRegistro = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
    )
    $estadoRegistro = @()
    foreach ($clave in $clavesRegistro) {
        if (Test-Path $clave) {
            try {
                $props = Get-ItemProperty -Path $clave -ErrorAction Stop
                $estadoRegistro += [PSCustomObject]@{ Ruta = $clave; Propiedades = $props }
            } catch {
                $estadoRegistro += [PSCustomObject]@{ Ruta = $clave; Propiedades = 'No se pudo leer' }
            }
        }
    }
    $estado | Add-Member -MemberType NoteProperty -Name 'Registro' -Value $estadoRegistro
    $estado | Add-Member -MemberType NoteProperty -Name 'Fecha'    -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

    try {
        $convertCmd = Get-Command 'ConvertTo-Json' -ErrorAction SilentlyContinue
        if ($convertCmd) {
            $estado | ConvertTo-Json -Depth 6 | Out-File -FilePath $backupFile -Encoding UTF8
        } else {
            # PS 2.0: sin ConvertTo-Json, guardamos un volcado legible con Out-String
            $estado | Out-String | Out-File -FilePath $backupFile -Encoding UTF8
        }
        Write-GC -Message ('Backup de estado guardado en: ' + $backupFile) -Level 'Info'
    } catch {
        Write-GC -Message ('No se pudo guardar el backup de estado: ' + $_.Exception.Message) -Level 'Warning'
    }
}


# ==============================================================================
# Export-GCReport
# ==============================================================================
# Vuelca $global:GC_Report (la lista de operaciones que se han ido acumulando
# en Invoke-WithProgress) a un archivo HTML o TXT legible. Pensado para poder
# adjuntar "que hizo GhostCleaner en este equipo" a un ticket o documentacion
# interna de empresa.
#
# PARAMETROS:
#   $Format : 'HTML' (por defecto) o 'TXT'
# ==============================================================================

function Export-GCReport {
    param(
        [ValidateSet('HTML', 'TXT')] [string]$Format = 'HTML'
    )

    if ($global:GC_Report.Count -eq 0) {
        Write-GC -Message 'No hay operaciones registradas; no se genera informe.' -Level 'Warning'
        return
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    if ($Format -eq 'TXT') {
        $reportFile = Join-Path $global:GC_Logs ('Informe_' + $stamp + '.txt')
        $lineas = @('Informe GhostCleaner - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), '')
        foreach ($item in $global:GC_Report) {
            $lineas += ('[' + $item.Resultado + '] ' + $item.Operacion + $(if ($item.Detalle) { ' - ' + $item.Detalle } else { '' }))
        }
        $lineas | Out-File -FilePath $reportFile -Encoding UTF8
    } else {
        $reportFile = Join-Path $global:GC_Logs ('Informe_' + $stamp + '.html')
        $filas = ''
        foreach ($item in $global:GC_Report) {
            $colorFila = switch ($item.Resultado) {
                'OK'                 { '#1f9d55' }
                'Fallo'               { '#c0392b' }
                'Simulado (DryRun)'   { '#7f8c8d' }
                default               { '#333333' }
            }
            $filas += '<tr><td>' + $item.Hora.ToString('HH:mm:ss') + '</td><td>' + $item.Operacion + '</td>' +
                      '<td style="color:' + $colorFila + ';font-weight:bold;">' + $item.Resultado + '</td>' +
                      '<td>' + $item.Detalle + '</td></tr>'
        }

        $html = '<html><head><meta charset="utf-8"><title>Informe GhostCleaner</title>' +
                '<style>body{font-family:Segoe UI,Arial,sans-serif;background:#0f1115;color:#e6e6e6;padding:24px;}' +
                'table{width:100%;border-collapse:collapse;}th,td{padding:8px 12px;border-bottom:1px solid #2b2f36;text-align:left;}' +
                'th{background:#1b1f27;}h1{color:#5fd0d0;}</style></head><body>' +
                '<h1>Informe de ejecucion - GhostCleaner</h1>' +
                '<p>Generado: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '</p>' +
                '<table><tr><th>Hora</th><th>Operacion</th><th>Resultado</th><th>Detalle</th></tr>' + $filas + '</table>' +
                '</body></html>'

        $html | Out-File -FilePath $reportFile -Encoding UTF8
    }

    Write-GC -Message ('Informe exportado a: ' + $reportFile) -Level 'Action'
    return $reportFile
}


# ==============================================================================
# Import-GCPlugins
# ==============================================================================
# Sistema de plugins minimo: cualquier .psm1 que alguien deje en la carpeta
# Plugins\ se carga igual que un modulo del nucleo, sin tocar nada de este
# proyecto. Pensado para quien quiera anadir un modulo propio (por ejemplo,
# limpiar una app concreta de su empresa) sin tener que tocar GhostCleaner.ps1
# ni mandar un pull request para algo muy especifico de su caso.
#
# CONVENCION QUE DEBE SEGUIR UN PLUGIN:
#   - Vivir en <raiz>\Plugins\NombrePlugin.psm1
#   - Exponer una funcion Invoke-NombrePlugin (incluso vacia si solo quiere
#     registrar helpers) para que el menu/los perfiles puedan llamarlo igual
#     que a los modulos del nucleo.
#   - Puede usar Write-GC, Get-ProfileValue y el resto de helpers de Core.psm1
#     con total normalidad, porque se carga con -Global igual que ellos.
#
# COMO SE EJECUTAN DESDE UN PERFIL:
#   Anade una clave "plugins": { "enabled": true, "list": ["NombrePlugin"] }
#   al JSON y se ejecutaran junto al resto de modulos.
# ==============================================================================

function Import-GCPlugins {
    $pluginsPath = Join-Path $global:GC_Root 'Plugins'

    if (-not (Test-Path $pluginsPath)) {
        return @()
    }

    $cargados = @()
    $archivos = Get-ChildItem -Path $pluginsPath -Filter '*.psm1' -ErrorAction SilentlyContinue

    foreach ($archivo in $archivos) {
        try {
            Import-Module $archivo.FullName -Force -Global -ErrorAction Stop
            $nombre = $archivo.BaseName
            $cargados += $nombre
            Write-GC -Message ('Plugin cargado: ' + $nombre) -Level 'Info'
        } catch {
            Write-GC -Message ('No se pudo cargar el plugin ' + $archivo.Name + ': ' + $_.Exception.Message) -Level 'Warning'
        }
    }

    return $cargados
}


# ==============================================================================
# Invoke-GCPlugins
# ==============================================================================
# Ejecuta los plugins indicados en el perfil (seccion "plugins"), llamando a
# Invoke-<NombrePlugin> de cada uno. Si el perfil no define la seccion, no se
# ejecuta ningun plugin (comportamiento explicito, no "todos por defecto").
# ==============================================================================

function Invoke-GCPlugins {
    $habilitado = Get-ProfileValue -Section 'plugins' -Key 'enabled' -Default $false
    if (-not $habilitado) { return }

    $lista = Get-ProfileValue -Section 'plugins' -Key 'list' -Default @()

    foreach ($nombrePlugin in $lista) {
        $funcion = 'Invoke-' + $nombrePlugin
        if (Get-Command $funcion -ErrorAction SilentlyContinue) {
            [void](Invoke-WithProgress -OperationName ('Plugin: ' + $nombrePlugin) -ScriptBlock ([scriptblock]::Create($funcion)))
        } else {
            Write-GC -Message ('Plugin "' + $nombrePlugin + '" listado en el perfil pero no encontrado (¿esta en Plugins\?).') -Level 'Warning'
        }
    }
}


# ==============================================================================
# Invoke-Profile
# ==============================================================================
# Ejecuta todas las acciones definidas en un perfil JSON de forma automatica,
# sin menu interactivo. Cada seccion del JSON puede estar habilitada o no.
#
# FLUJO:
#   1. Carga el perfil con Load-GCProfile
#   2. Muestra un resumen de lo que va a hacer
#   3. Ejecuta cada modulo si su seccion "enabled" es true en el JSON
#   4. Los modulos leen $global:GC_Config para saber exactamente que hacer
#      (que servicios, que tareas, que dominios...)
#
# PARAMETROS:
#   $ProfileName : nombre del perfil (Safe, Balanced, Aggressive o custom)
# ==============================================================================

function Invoke-Profile {
    param(
        [Parameter(Mandatory = $true)] [string]$ProfileName,
        # Lista opcional de modulos a ejecutar, p.ej. -Modules Privacy,Security.
        # Si se omite (o es null/vacia) se ejecutan todos los que el perfil
        # tenga habilitados, que es el comportamiento de siempre.
        [string[]]$Modules,
        [switch]$SkipRestorePoint
    )

    # Cargamos el JSON y lo guardamos en $global:GC_Config
    Load-GCProfile -ProfileName $ProfileName

    Write-Host ''
    Write-Host ('========================================') -ForegroundColor DarkCyan
    Write-Host ('  Ejecutando perfil: ' + $ProfileName)    -ForegroundColor Cyan
    if ($global:GC_DryRun) {
        Write-Host ('  *** MODO SIMULACION (DryRun): no se aplicara ningun cambio real ***') -ForegroundColor Yellow
    }
    Write-Host ('========================================') -ForegroundColor DarkCyan
    Write-Host ''

    # Mostramos un resumen antes de actuar para que el usuario sepa que pasara
    Write-GC -Message ('Descripcion: ' + $global:GC_Config._description) -Level 'Info'

    # Aviso de dominio/GPO: informativo, no bloquea la ejecucion. El equipo
    # puede estar en dominio y aun asi querer aplicar el perfil; solo avisamos
    # de que una politica de grupo podria revertir el cambio mas adelante.
    if (Test-GCDomainJoined) {
        Write-GC -Message 'Este equipo pertenece a un dominio de Active Directory.' -Level 'Warning'
        Write-GC -Message 'Si hay GPOs aplicadas sobre telemetria/Defender/tareas, podrian sobreescribir estos cambios en el siguiente "gpupdate".' -Level 'Warning'
    }

    Write-Host ''

    # Red de seguridad antes de tocar nada: backup del estado real del equipo
    # y punto de restauracion del sistema (salvo que el usuario los desactive).
    Backup-GCSystemState
    if (-not $SkipRestorePoint) {
        [void](New-GCRestorePoint -Description ('GhostCleaner - antes de perfil ' + $ProfileName))
    } else {
        Write-GC -Message 'Punto de restauracion omitido (-SkipRestorePoint).' -Level 'Warning'
    }
    Write-Host ''

    # Mapa de seccion del JSON -> nombre de modulo, para poder filtrar con -Modules
    # sin repetir esta logica seis veces.
    $mapaModulos = @{
        'privacy'   = 'Privacy'
        'services'  = 'Services'
        'tasks'     = 'Tasks'
        'hosts'     = 'Hosts'
        'optimizer' = 'Optimizer'
        'security'  = 'Security'
        'apps'      = 'Apps'
        'browsers'  = 'Browsers'
    }

    foreach ($seccion in $mapaModulos.Keys) {
        $nombreModulo = $mapaModulos[$seccion]

        # Si se paso -Modules, solo ejecutamos los modulos de esa lista.
        if ($Modules -and $Modules.Count -gt 0 -and ($Modules -notcontains $nombreModulo)) {
            continue
        }

        if (Get-ProfileValue -Section $seccion -Key 'enabled') {
            $funcion = 'Invoke-' + $nombreModulo
            [void](Invoke-WithProgress -OperationName $nombreModulo -ScriptBlock ([scriptblock]::Create($funcion)))
        }
    }

    # Plugins: se ejecutan al final, despues de los modulos del nucleo.
    if (-not $Modules -or $Modules.Count -eq 0 -or ($Modules -contains 'Plugins')) {
        Invoke-GCPlugins
    }

    Write-Host ''
    Write-GC -Message ('Perfil ' + $ProfileName + ' completado.') -Level 'Action'

    # Informe final: util tanto para revisar en tu propio PC como para
    # adjuntar a documentacion interna si esto se usa en una empresa.
    [void](Export-GCReport -Format 'HTML')

    if (-not $global:GC_Silent) {
        Write-Host ''
        Write-Host 'Pulsa cualquier tecla para salir...' -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}


# ==============================================================================
# Show-MainMenu
# ==============================================================================
# Menu interactivo. Se usa cuando no se pasa -Profile al launcher.
# Cada opcion del menu sigue ignorando los perfiles y ejecuta el modulo
# completo con su configuracion por defecto (lista hardcodeada en cada .psm1).
# Para usar perfiles, lanza el script con -Profile desde PowerShell.
# ==============================================================================

function Show-MainMenu {
    while ($true) {
        Clear-Host

        Write-Host '╔══════════════════════════════════════╗' -ForegroundColor DarkCyan
        Write-Host '║             GhostCleaner              ║' -ForegroundColor Cyan
        Write-Host '║   Telemetria · Publicidad · Rendimiento ║' -ForegroundColor Gray
        Write-Host '╚══════════════════════════════════════╝' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Host ' github.com/byjone/GhostCleaner' -ForegroundColor DarkYellow
        Write-Host ' Issues, releases y contribuciones en el repo.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ' Que hace GhostCleaner?' -ForegroundColor DarkGray
        Write-Host ' Windows recopila datos sobre tu uso del sistema (telemetria),' -ForegroundColor DarkGray
        Write-Host ' muestra publicidad personalizada y ejecuta tareas en segundo' -ForegroundColor DarkGray
        Write-Host ' plano que consumen recursos. Este script permite desactivarlo.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ' TIP: tambien puedes ejecutar un perfil directamente sin menu:' -ForegroundColor DarkGray
        Write-Host '   .\GhostCleaner.ps1 -Profile Safe' -ForegroundColor DarkGray
        Write-Host '   .\GhostCleaner.ps1 -Profile Balanced' -ForegroundColor DarkGray
        Write-Host '   .\GhostCleaner.ps1 -Profile Aggressive' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ' ADVERTENCIA: algunos cambios afectan al funcionamiento del sistema.' -ForegroundColor Yellow
        Write-Host ' Usa [6] Restore para deshacer si algo no va bien.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '----------------------------------------' -ForegroundColor DarkCyan

        Write-Host ''
        Write-Host ' [1] PRIVACY  -  Privacidad y telemetria' -ForegroundColor White
        Write-Host '     * Desactiva el envio de datos de uso a Microsoft' -ForegroundColor DarkGray
        Write-Host '       (AllowTelemetry = 0 en el Registro de Windows)' -ForegroundColor DarkGray
        Write-Host '     * Deshabilita el Advertising ID: el identificador' -ForegroundColor DarkGray
        Write-Host '       que Windows usa para mostrarte anuncios personalizados' -ForegroundColor DarkGray
        Write-Host '     Afecta: Registro de Windows (HKLM y HKCU)' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [2] SERVICES  -  Servicios de telemetria en segundo plano' -ForegroundColor White
        Write-Host '     * DiagTrack: recopila y envia diagnosticos a Microsoft' -ForegroundColor DarkGray
        Write-Host '     * dmwappushservice: servicio de mensajeria WAP (telemetria movil)' -ForegroundColor DarkGray
        Write-Host '     * SysMain (Superfetch): precarga apps en RAM; util en HDDs,' -ForegroundColor DarkGray
        Write-Host '       innecesario y a veces perjudicial en SSDs' -ForegroundColor DarkGray
        Write-Host '     Afecta: servicios de Windows (se detienen y se deshabilitan)' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [3] TASKS  -  Tareas programadas de telemetria' -ForegroundColor White
        Write-Host '     * Compatibility Appraiser: analiza tu PC para Windows Update' -ForegroundColor DarkGray
        Write-Host '     * ProgramDataUpdater: actualiza datos de compatibilidad' -ForegroundColor DarkGray
        Write-Host '     * Consolidator/UsbCeip/KernelCeipTask: recopilan datos' -ForegroundColor DarkGray
        Write-Host '       del Programa de Mejora de la Experiencia del Cliente' -ForegroundColor DarkGray
        Write-Host '     * Proxy (Autochk): comprueba discos al inicio' -ForegroundColor DarkGray
        Write-Host '     * DiskDiagnosticDataCollector: envia datos de disco a MS' -ForegroundColor DarkGray
        Write-Host '     Afecta: Programador de tareas de Windows' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [4] OPTIMIZER  -  Limpieza y optimizacion rapida' -ForegroundColor White
        Write-Host '     * Vacia las carpetas de archivos temporales (%TEMP% y' -ForegroundColor DarkGray
        Write-Host '       C:\Windows\Temp): archivos que ya no se necesitan' -ForegroundColor DarkGray
        Write-Host '     * Ejecuta "ipconfig /flushdns": borra la cache DNS local' -ForegroundColor DarkGray
        Write-Host '       (util si algunas webs no cargan o dan error de conexion)' -ForegroundColor DarkGray
        Write-Host '     Afecta: archivos temporales y cache de red (reversible)' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [5] SECURITY  -  Seguridad basica del sistema' -ForegroundColor White
        Write-Host '     * Activa el Firewall de Windows en los tres perfiles:' -ForegroundColor DarkGray
        Write-Host '       Dominio (redes corporativas), Privado (casa) y Publico' -ForegroundColor DarkGray
        Write-Host '       (cafeterias, aeropuertos). Bloquea conexiones no autorizadas.' -ForegroundColor DarkGray
        Write-Host '     * Reactiva la Proteccion en tiempo real de Windows Defender' -ForegroundColor DarkGray
        Write-Host '       por si habia sido desactivada por otro software' -ForegroundColor DarkGray
        Write-Host '     Afecta: configuracion de Firewall y Defender' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [6] RESTORE  -  Deshacer cambios aplicados' -ForegroundColor White
        Write-Host '     * Reactiva los servicios DiagTrack y dmwappushservice' -ForegroundColor DarkGray
        Write-Host '       (vuelven a inicio Manual, no Automatico)' -ForegroundColor DarkGray
        Write-Host '     * Limpia las entradas anadidas al archivo hosts' -ForegroundColor DarkGray
        Write-Host '       (elimina los bloqueos de dominios de telemetria)' -ForegroundColor DarkGray
        Write-Host '     * Quita las reglas de Firewall y las politicas de Edge/Chrome' -ForegroundColor DarkGray
        Write-Host '       que haya aplicado GhostCleaner' -ForegroundColor DarkGray
        Write-Host '     NOTA: no revierte cambios de Registro de telemetria ni tareas.' -ForegroundColor Yellow
        Write-Host '     Afecta: servicios, hosts, Firewall y politicas de navegador' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [7] AUDIT  -  Ver el estado actual sin cambiar nada' -ForegroundColor White
        Write-Host '     * Revisa telemetria, servicios, hosts, Firewall y Defender' -ForegroundColor DarkGray
        Write-Host '     Afecta: nada. Solo lectura.' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [8] INFORME  -  Exportar lo que se hizo en esta sesion' -ForegroundColor White
        Write-Host '     * Genera un HTML en Logs\ con cada operacion y su resultado' -ForegroundColor DarkGray
        Write-Host '     Afecta: nada. Solo genera un archivo.' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [9] APPS  -  Quitar apps preinstaladas (Xbox, Cortana...)' -ForegroundColor White
        Write-Host '     * Desinstala apps Appx/UWP de la lista por defecto o del perfil' -ForegroundColor DarkGray
        Write-Host '     Afecta: apps instaladas para el usuario actual (y aprovisionamiento)' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host ' [10] BROWSERS  -  Privacidad de Edge y Chrome (opcional)' -ForegroundColor White
        Write-Host '     * Desactiva informes de uso/caidas y "Do Not Track" en Edge' -ForegroundColor DarkGray
        Write-Host '     * Desactiva metricas y reporte extendido de Safe Browsing en Chrome' -ForegroundColor DarkGray
        Write-Host '     * Solo se aplica al navegador que tengas instalado' -ForegroundColor DarkGray
        Write-Host '     NOTA: usa [6] Restore para revertir estas politicas.' -ForegroundColor DarkGray
        Write-Host '     Afecta: Registro (HKLM, politicas de Edge/Chrome)' -ForegroundColor DarkGray

        Write-Host ''
        Write-Host '----------------------------------------' -ForegroundColor DarkCyan
        Write-Host ' [0] EXIT  -  Cerrar GhostCleaner' -ForegroundColor Yellow
        Write-Host ''

        $c = Read-Host 'Selecciona una opcion (0-10)'

        switch ($c) {
            '1' {
                Write-GC -Message 'Ejecutando opcion [1]: Privacy.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Aplicando Privacy' -ScriptBlock { Invoke-Privacy })
                Pause-ForContinue
            }
            '2' {
                Write-GC -Message 'Ejecutando opcion [2]: Services.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Deshabilitando Services' -ScriptBlock { Invoke-Services })
                Pause-ForContinue
            }
            '3' {
                Write-GC -Message 'Ejecutando opcion [3]: Tasks.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Deshabilitando Tasks' -ScriptBlock { Invoke-Tasks })
                Pause-ForContinue
            }
            '4' {
                Write-GC -Message 'Ejecutando opcion [4]: Optimizer.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Optimizando sistema' -ScriptBlock { Invoke-Optimizer })
                Pause-ForContinue
            }
            '5' {
                Write-GC -Message 'Ejecutando opcion [5]: Security.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Aplicando Security' -ScriptBlock { Invoke-Security })
                Pause-ForContinue
            }
            '6' {
                Write-GC -Message 'Ejecutando opcion [6]: Restore.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Restaurando (parcial)' -ScriptBlock { Invoke-Restore })
                Pause-ForContinue
            }
            '7' {
                Write-GC -Message 'Ejecutando opcion [7]: Audit.' -Level 'Action'
                [void](Invoke-Audit)
                Pause-ForContinue
            }
            '8' {
                Write-GC -Message 'Ejecutando opcion [8]: exportando informe.' -Level 'Action'
                [void](Export-GCReport -Format 'HTML')
                Pause-ForContinue
            }
            '9' {
                Write-GC -Message 'Ejecutando opcion [9]: Apps.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Quitando apps preinstaladas' -ScriptBlock { Invoke-Apps })
                Pause-ForContinue
            }
            '10' {
                Write-GC -Message 'Ejecutando opcion [10]: Browsers.' -Level 'Action'
                [void](Invoke-WithProgress -OperationName 'Privacidad de Edge/Chrome' -ScriptBlock { Invoke-Browsers })
                Pause-ForContinue
            }
            '0' {
                Write-Host ''
                Write-Host ' Hasta luego.' -ForegroundColor Cyan
                Write-Host ''
                return
            }
            default {
                Write-GC -Message 'Opcion no valida. Escribe un numero del 0 al 10.' -Level 'Warning'
                Pause-ForContinue
            }
        }
    }
}
