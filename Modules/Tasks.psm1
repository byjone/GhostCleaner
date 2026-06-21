#Requires -Version 2.0
# ==============================================================================
# Tasks.psm1  -  Deshabilita tareas programadas de telemetria
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Gestiona las "Tareas Programadas" de Windows: procesos que el sistema
#   ejecuta automaticamente en segundo plano segun un horario o un evento
#   (inicio de sesion, conexion a internet, etc.).
#
# QUE ES UNA TAREA PROGRAMADA:
#   Similar a un cronjob en Linux. Windows las guarda en una estructura de
#   carpetas (TaskPath) con un nombre (TaskName). Por ejemplo:
#     TaskPath: \Microsoft\Windows\Application Experience\
#     TaskName: Microsoft Compatibility Appraiser
#   Se pueden ver en: Inicio -> "Programador de tareas"
#
# ESTRATEGIA DE COMPATIBILIDAD (Windows 7 a 11):
#   - Metodo primario:  schtasks.exe
#       Herramienta de linea de comandos incluida en Windows desde XP.
#       Funciona en todas las versiones sin depender de PowerShell moderno.
#   - Fallback:         Get-ScheduledTask (cmdlet de PowerShell)
#       Solo disponible en PS 3.0+ / Windows 8+. Se usa si schtasks falla.
#
# ==============================================================================


# ==============================================================================
# Disable-TaskSafe
# ==============================================================================
# Deshabilita una tarea programada de forma segura, con dos metodos y
# control de errores en cada paso.
#
# PARAMETROS:
#   $TaskPath : carpeta donde esta la tarea  (ej: \Microsoft\Windows\Autochk\)
#   $TaskName : nombre de la tarea           (ej: Proxy)
#
# NORMALIZACION DE RUTA:
#   Windows exige que la ruta empiece y acabe en '\'. Esta funcion lo corrige
#   automaticamente aunque el llamador lo omita, para evitar errores tontos.
#   Nota: no usamos $string[-1] porque esa sintaxis no existe en PS 2.0;
#   en su lugar calculamos la ultima posicion con $string.Length - 1.
# ==============================================================================

function Disable-TaskSafe {
    param(
        [Parameter(Mandatory = $true)] [string]$TaskPath,
        [Parameter(Mandatory = $true)] [string]$TaskName
    )

    # ── Normalizacion de ruta ─────────────────────────────────────────────────
    # [string]::IsNullOrEmpty comprueba si la cadena es null o vacia ("").
    # .Trim() elimina espacios al inicio y al final antes de comparar con ''.
    if ([string]::IsNullOrEmpty($TaskPath) -or $TaskPath.Trim() -eq '') {
        $TaskPath = $null
    } else {
        # Reemplazamos barras '/' por '\' por si el llamador uso estilo Unix
        $TaskPath = $TaskPath -replace '/', '\'

        # Aseguramos que empieza con '\'
        if ($TaskPath.Length -gt 0 -and $TaskPath[0] -ne '\') {
            $TaskPath = '\' + $TaskPath
        }

        # Aseguramos que acaba con '\' (sin usar [-1], incompatible con PS 2.0)
        if ($TaskPath[$TaskPath.Length - 1] -ne '\') {
            $TaskPath = $TaskPath + '\'
        }
    }

    Write-GC -Message ('Procesando tarea: ' + $TaskPath + ' -> ' + $TaskName) -Level 'Action'

    # ── Construir nombre completo ─────────────────────────────────────────────
    # schtasks.exe espera la ruta y el nombre unidos, sin barra final:
    # "\Microsoft\Windows\Autochk\Proxy"
    $tnFull = if ($TaskPath) {
        $TaskPath.TrimEnd('\') + '\' + $TaskName
    } else {
        '\' + $TaskName
    }

    # ── Metodo primario: schtasks.exe ─────────────────────────────────────────
    # Lanzamos schtasks.exe como proceso hijo y capturamos su salida.
    # ProcessStartInfo nos da control total sobre como se lanza el proceso:
    #   UseShellExecute = $false      : no abrir ventana nueva
    #   RedirectStandardOutput = $true: capturar lo que imprime en pantalla
    #   RedirectStandardError  = $true: capturar los mensajes de error
    try {
        $psi                        = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = 'schtasks.exe'
        $psi.Arguments              = '/Change /TN "' + $tnFull + '" /Disable'
        $psi.UseShellExecute        = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true

        $p           = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()   # [void] descarta el valor de retorno (true/false)

        # Leemos stdout y stderr ANTES de WaitForExit para evitar deadlocks
        # (el proceso podria bloquearse esperando que leamos su buffer)
        $stdOut = $p.StandardOutput.ReadToEnd()
        $stdErr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()   # Esperamos a que schtasks termine

        # $LASTEXITCODE / $p.ExitCode = 0 significa exito en convencion Unix/Windows
        if ($p.ExitCode -eq 0) {
            Write-GC -Message ('Tarea deshabilitada: ' + $TaskName) -Level 'Action'
            return $true
        }

        Write-GC -Message ('schtasks no encontro la tarea, intentando cmdlet...') -Level 'Warning'
    } catch {
        Write-GC -Message ('Error ejecutando schtasks: ' + $_.Exception.Message) -Level 'Warning'
    }

    # ── Fallback: Get-ScheduledTask (PS 3.0+ / Win 8+) ───────────────────────
    # Antes de llamar al cmdlet comprobamos si existe en este sistema.
    # Get-Command devuelve $null si no encuentra el comando; con -ErrorAction
    # SilentlyContinue evitamos que eso genere un error ruidoso.
    $cmdlet = Get-Command 'Get-ScheduledTask' -ErrorAction SilentlyContinue
    if (-not $cmdlet) {
        Write-GC -Message ('Get-ScheduledTask no disponible y schtasks fallo: ' + $TaskName) -Level 'Error'
        return $false
    }

    try {
        $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue

        # Busqueda por coincidencia exacta de ruta y nombre
        $task = $null
        if ($TaskPath) {
            foreach ($t in $allTasks) {
                if ($t.TaskName -eq $TaskName -and $t.TaskPath -eq $TaskPath) {
                    $task = $t
                    break   # Encontrada: salimos del bucle inmediatamente
                }
            }
        }

        # Si no hubo coincidencia exacta, buscamos por prefijo de ruta
        if (-not $task) {
            $candidates = @()   # @() crea un array vacio
            foreach ($t in $allTasks) {
                if ($t.TaskName -ne $TaskName) { continue }   # 'continue' salta a la siguiente iteracion
                if ($TaskPath -and $t.TaskPath -notlike ($TaskPath + '*')) { continue }
                $candidates += $t   # += anade un elemento al array
            }

            if ($candidates.Count -gt 1) {
                # Si hay varias candidatas, elegimos la de ruta mas larga (mas especifica).
                # No usamos Sort-Object { scriptblock } porque falla en PS 2.0;
                # en su lugar recorremos el array manualmente comparando longitudes.
                $best = $candidates[0]
                for ($i = 1; $i -lt $candidates.Count; $i++) {
                    if ($candidates[$i].TaskPath.Length -gt $best.TaskPath.Length) {
                        $best = $candidates[$i]
                    }
                }
                $task = $best
            } elseif ($candidates.Count -eq 1) {
                $task = $candidates[0]
            }
        }

        if ($task) {
            Disable-ScheduledTask -InputObject $task -ErrorAction Stop
            Write-GC -Message ('Tarea deshabilitada (cmdlet): ' + $TaskName) -Level 'Action'
            return $true
        }

        Write-GC -Message ('No encontrada: ' + $TaskName) -Level 'Warning'
        return $false
    } catch {
        Write-GC -Message ('Error en cmdlet: ' + $TaskName + ' -> ' + $_.Exception.Message) -Level 'Error'
        return $false
    }
}


# ==============================================================================
# Invoke-Tasks
# ==============================================================================
# Punto de entrada que llama el menu. Lee la lista de tareas a deshabilitar
# desde el perfil activo (tasks.list en el JSON, un array de objetos con
# las propiedades Path y Name). Si no hay perfil cargado (modo menu
# interactivo), usa la lista por defecto de toda la vida.
#
# POR QUE HASHTABLES EN LUGAR DE UN ARRAY PLANO:
#   La version anterior usaba un array como:
#     @('\ruta1', 'Nombre1', '\ruta2', 'Nombre2', ...)
#   y accedia con $tasks[$i] y $tasks[$i+1], lo que es fragil: si falta un
#   elemento, todos los indices quedan desplazados y los datos se mezclan.
#
#   Con hashtables cada par ruta+nombre es un objeto independiente:
#     @{ Path = '\ruta'; Name = 'Nombre' }
#   y se accede con $tasks[$i].Path y $tasks[$i].Name. Mucho mas claro y
#   facil de ampliar sin riesgo de errores de indices.
#
#   Los objetos que vienen de un perfil JSON (tasks.list) tienen exactamente
#   esta misma forma -> { "Path": "...", "Name": "..." } -> y se leen con
#   .Path / .Name igual que las hashtables, asi que el bucle de abajo
#   funciona sin cambios sea cual sea el origen de los datos.
# ==============================================================================

function Invoke-Tasks {
    Write-GC -Message 'Iniciando deshabilitacion de Tasks...' -Level 'Action'

    # Lista por defecto: se usa en modo menu o si el perfil no define 'list'.
    $defaultTasks = @(
        # Analiza el PC para informes de compatibilidad con Windows Update
        @{ Path = '\Microsoft\Windows\Application Experience'
           Name = 'Microsoft Compatibility Appraiser' }

        # Actualiza base de datos de compatibilidad de programas
        @{ Path = '\Microsoft\Windows\Application Experience'
           Name = 'ProgramDataUpdater' }

        # Recopila datos para el Programa de Mejora de la Experiencia (CEIP)
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program'
           Name = 'Consolidator' }

        # Recopila datos de uso de dispositivos USB para Microsoft
        @{ Path = '\Microsoft\Windows\Customer Experience Improvement Program'
           Name = 'UsbCeip' }
    )

    # Get-ProfileValue (Core.psm1) devuelve $defaultTasks si no hay perfil
    # cargado, o el array 'tasks.list' del JSON si lo hay.
    $tasks = Get-ProfileValue -Section 'tasks' -Key 'list' -Default $defaultTasks

    $total = $tasks.Count

    for ($i = 0; $i -lt $total; $i++) {
        $num  = $i + 1
        $path = $tasks[$i].Path
        $name = $tasks[$i].Name

        Write-GC -Message ('[' + $num + '/' + $total + '] ' + $path + ' -> ' + $name) -Level 'Info'
        [void](Disable-TaskSafe -TaskPath $path -TaskName $name)
    }

    Write-GC -Message 'Tasks procesadas.' -Level 'Info'
}
