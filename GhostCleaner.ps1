#Requires -Version 2.0
# ==============================================================================
# GhostCleaner.ps1  -  Punto de entrada principal
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Es el primer script que debes ejecutar. Su unico trabajo es preparar el
#   entorno y mostrar el menu principal. No hace cambios en el sistema por
#   si solo; delega todo el trabajo a los modulos de la carpeta Modules\.
#
# COMO EJECUTARLO:
#   1. Haz clic derecho sobre este archivo.
#   2. Selecciona "Ejecutar con PowerShell".
#   Si aparece un error de permisos, abre PowerShell como Administrador y
#   arrastra este archivo a la ventana, luego pulsa Enter.
#
# ESTRUCTURA DEL PROYECTO:
#   GhostCleaner.ps1        <- este archivo (lanzador)
#   Modules\
#     Core.psm1             <- funciones comunes: menu, logging, helpers
#     Privacy.psm1          <- telemetria y publicidad
#     Services.psm1         <- servicios de Windows
#     Tasks.psm1            <- tareas programadas
#     Hosts.psm1            <- bloqueo de dominios via archivo hosts
#     Optimizer.psm1        <- limpieza de temporales y DNS
#     Security.psm1         <- Firewall y Defender
#     Restore.psm1          <- deshacer cambios aplicados
#   Backup\                 <- carpeta donde se guardan copias de seguridad
#   Profiles\               <- perfiles de configuracion (Safe/Balanced/Aggressive)
#
# POR QUE SE NECESITA SER ADMINISTRADOR:
#   La mayoria de los cambios (registro del sistema, servicios, firewall) solo
#   pueden hacerse con privilegios elevados. Windows llama a esto "Administrador".
#   Sin esos permisos, los comandos simplemente fallan sin efecto.
#
# QUE ES $ErrorActionPreference = 'Stop':
#   Por defecto PowerShell muestra errores pero sigue ejecutando el codigo.
#   Con 'Stop' le decimos que DETENGA la ejecucion y salte al bloque catch{}
#   cuando algo falla. Asi podemos mostrar mensajes claros en lugar de que
#   el script continue silenciosamente con un estado incorrecto.
#
# ==============================================================================
#
# USO CON PERFILES (sin menu interactivo):
#   Puedes lanzar el script directamente con un perfil para que aplique todos
#   los cambios automaticamente, sin tener que navegar el menu:
#     .\GhostCleaner.ps1 -Profile Safe
#     .\GhostCleaner.ps1 -Profile Balanced
#     .\GhostCleaner.ps1 -Profile Aggressive
#   Si no se indica -Profile, se abre el menu interactivo de toda la vida.
#
# OTROS MODOS DE USO:
#   .\GhostCleaner.ps1 -Profile Aggressive -DryRun
#       Simula el perfil Aggressive: muestra que haria sin cambiar nada.
#   .\GhostCleaner.ps1 -Profile Balanced -Modules Privacy,Security
#       Aplica solo esos dos modulos del perfil, ignora el resto.
#   .\GhostCleaner.ps1 -Profile Safe -Silent
#       Modo desatendido para GPO/SCCM: sin pausas ni prompts en pantalla.
#   .\GhostCleaner.ps1 -Audit
#       Solo lee el estado actual del sistema, no cambia nada.
#
# QUE ES UN "param()" AL PRINCIPIO DE UN SCRIPT:
#   Declara los parametros que el script acepta desde la linea de comandos,
#   igual que una funcion. Tiene que ser literalmente la primera instruccion
#   del archivo (antes incluso de comentarios sueltos fuera del bloque #).
# ==============================================================================

param(
    # Nombre de un perfil de la carpeta Profiles\ (sin la extension .json).
    # Si se omite, el script muestra el menu interactivo normal.
    [string]$Profile,

    # Ejecuta solo estos modulos del perfil, en vez de todos los habilitados.
    # Ejemplo: .\GhostCleaner.ps1 -Profile Balanced -Modules Privacy,Security
    [string[]]$Modules,

    # Simula la ejecucion: muestra que se haria pero no cambia nada real.
    # Sirve para revisar un perfil (sobre todo uno personalizado) antes de
    # aplicarlo de verdad.
    [switch]$DryRun,

    # Modo desatendido: sin pausas de teclado ni prompts. Pensado para GPO,
    # SCCM o scripts de aprovisionamiento que lanzan esto sin nadie delante.
    [switch]$Silent,

    # Modo auditoria: revisa el estado actual del sistema y lo muestra, sin
    # aplicar ningun cambio. Ignora -Profile si se indica a la vez.
    [switch]$Audit,

    # Por defecto se crea un punto de restauracion antes de aplicar un perfil.
    # Con este flag se omite (mas rapido, pero sin esa red de seguridad extra).
    [switch]$SkipRestorePoint
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot es una variable automatica de PowerShell que contiene la
# carpeta donde esta guardado este script. Usarla en lugar de rutas absolutas
# (como C:\Users\...) hace que el proyecto funcione en cualquier ubicacion.
$script:GhostCleanerRoot = $PSScriptRoot

# ==============================================================================
# CARGA DE MODULOS
# ==============================================================================
# Un modulo (.psm1) es un archivo que agrupa funciones relacionadas.
# Import-Module lo carga en memoria para que sus funciones esten disponibles.
#
# -Force    : recarga el modulo aunque ya estuviera cargado (util al editar).
# -Global   : IMPORTANTE. Sin esto, cada modulo vive en su propio "espacio"
#             aislado y las funciones de un modulo no pueden llamar a las de
#             otro. Con -Global, todas quedan registradas en la sesion completa
#             y pueden comunicarse entre si sin problema.
# ==============================================================================

$modules = @(
    'Core',       # Primero: contiene Write-GC y otros helpers que usan los demas
    'Privacy',
    'Services',
    'Tasks',
    'Hosts',
    'Optimizer',
    'Security',
    'Restore',
    'Audit'       # Diagnostico de solo lectura: no aplica cambios
)

foreach ($mod in $modules) {
    # Join-Path construye rutas de forma segura sin preocuparte por las barras
    $modPath = Join-Path $script:GhostCleanerRoot ('Modules\' + $mod + '.psm1')
    Import-Module $modPath -Force -Global
}

# ==============================================================================
# VALIDACION DE PRIVILEGIOS
# ==============================================================================
# EnsureAdmin esta definida en Core.psm1. Lanza un error si el usuario no es
# Administrador. Lo capturamos con try/catch para mostrar un mensaje claro.
# ==============================================================================

try {
    EnsureAdmin
} catch {
    Write-Host '[GhostCleaner] Necesitas ejecutar como Administrador.' -ForegroundColor Yellow
    Write-Host ('[GhostCleaner] Detalle: ' + $_.Exception.Message)     -ForegroundColor Red
    Write-Host ''
    Write-Host 'Pulsa cualquier tecla para salir...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    return   # 'return' termina el script sin lanzar un segundo error
}

# ==============================================================================
# INICIALIZACION
# ==============================================================================
# Initialize-GhostCleaner (en Core.psm1) crea la carpeta Backup\ si no existe
# y prepara variables globales que usan los demas modulos.
# ==============================================================================

try {
    # -RootPath es obligatorio en Core.psm1: le pasamos la carpeta del proyecto
    # que ya guardamos antes en $script:GhostCleanerRoot. -DryRun y -Silent
    # vienen directamente de los parametros que el usuario paso al lanzador.
    Initialize-GhostCleaner -RootPath $script:GhostCleanerRoot -DryRun:$DryRun -Silent:$Silent
} catch {
    Write-Host ('[GhostCleaner] Error inicializando: ' + $_.Exception.Message) -ForegroundColor Red
    throw   # 're-throw': vuelve a lanzar el error para que se vea el detalle completo
}

# ==============================================================================
# MENU PRINCIPAL  -  o  EJECUCION DIRECTA POR PERFIL
# ==============================================================================
# Si el usuario lanzo el script con -Profile NombreDelPerfil, lo ejecutamos
# directamente con Invoke-Profile (en Core.psm1) sin pasar por el menu.
# Si no, abrimos el menu interactivo de siempre con Show-MainMenu.
# ==============================================================================

if ($Audit) {
    try {
        Invoke-Audit | Out-Null
    } catch {
        Write-Host ('[GhostCleaner] Error durante la auditoria: ' + $_.Exception.Message) -ForegroundColor Red
        throw
    }
} elseif ($Profile) {
    try {
        Invoke-Profile -ProfileName $Profile -Modules $Modules -SkipRestorePoint:$SkipRestorePoint
    } catch {
        Write-Host ('[GhostCleaner] Error ejecutando el perfil "' + $Profile + '": ' + $_.Exception.Message) -ForegroundColor Red
        throw
    }
} else {
    try {
        Show-MainMenu
    } catch {
        Write-Host ('[GhostCleaner] Error inesperado: ' + $_.Exception.Message) -ForegroundColor Red
        throw
    }
}
