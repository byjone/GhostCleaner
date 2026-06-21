#Requires -Version 2.0
# ==============================================================================
# Services.psm1  -  Desactivacion de servicios de telemetria
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Detiene y deshabilita servicios de Windows relacionados con telemetria
#   y funciones que consumen recursos en segundo plano.
#
# QUE ES UN SERVICIO DE WINDOWS:
#   Un programa que se ejecuta en segundo plano, normalmente sin que el usuario
#   lo vea, y que puede iniciarse automaticamente con Windows. Son similares a
#   los "daemons" en Linux. Se pueden ver en: Inicio -> "Servicios"
#   (o ejecuta services.msc en el cuadro de busqueda).
#
# TIPOS DE INICIO DE UN SERVICIO:
#   Automatico : se inicia solo al arrancar Windows
#   Manual     : solo se inicia si otra aplicacion lo solicita
#   Deshabilitado: no puede iniciarse de ninguna manera
#
#   Este script pone los servicios en "Deshabilitado". La opcion [6] Restore
#   los devuelve a "Manual" (no a "Automatico", para reducir el impacto).
#
# ==============================================================================


# ==============================================================================
# Disable-ServiceSafe
# ==============================================================================
# Detiene y deshabilita un servicio de forma segura.
#
# PARAMETROS:
#   $Name : nombre interno del servicio (no el nombre visible en la UI)
#
# FLUJO:
#   1. Comprueba si el servicio existe (puede no estar en todas las versiones).
#   2. Lo detiene con Stop-Service -Force (fuerza el cierre aunque tenga deps.).
#   3. Lo deshabilita con Set-Service -StartupType Disabled.
#
# POR QUE -ErrorAction Stop:
#   Por defecto, si Stop-Service falla (p.ej. sin permisos), PowerShell muestra
#   el error pero continua. Con Stop lanzamos una excepcion que el bloque
#   catch{} captura, permitiendosenos informar del fallo y propagarlo.
# ==============================================================================

function Disable-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)] [string]$Name
    )

    Write-GC -Message ('Procesando servicio: ' + $Name) -Level 'Action'

    try {
        # Get-Service devuelve $null si el servicio no existe (con SilentlyContinue)
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue

        if ($null -eq $svc) {
            Write-GC -Message ('Servicio no encontrado (se omite): ' + $Name) -Level 'Warning'
            return   # Salimos de la funcion sin error; no tener el servicio no es un fallo
        }

        Write-GC -Message ('Deteniendo: ' + $Name) -Level 'Info'
        Stop-Service -Name $Name -Force -ErrorAction Stop

        Write-GC -Message ('Deshabilitando inicio automatico: ' + $Name) -Level 'Info'
        Set-Service  -Name $Name -StartupType Disabled -ErrorAction Stop

        Write-GC -Message ('Servicio deshabilitado: ' + $Name) -Level 'Action'
    } catch {
        Write-GC -Message ('Fallo al procesar ' + $Name + ': ' + $_.Exception.Message) -Level 'Error'
        throw   # Propagamos para que Invoke-WithProgress lo registre como fallo
    }
}


# ==============================================================================
# Invoke-Services
# ==============================================================================
# Punto de entrada que llama el menu. Lee la lista de servicios a deshabilitar
# desde el perfil activo (services.list en el JSON). Si no hay perfil cargado
# (modo menu interactivo), usa la lista por defecto de toda la vida.
#
# SERVICIOS QUE SE PUEDEN DESHABILITAR:
#   DiagTrack          : "Experiencias del usuario conectado y telemetria"
#                        Recopila y envia datos de uso a Microsoft continuamente.
#
#   dmwappushservice   : "Servicio de enrutamiento de mensajes push WAP"
#                        Usado originalmente para MMS en dispositivos moviles.
#                        En PCs de escritorio solo sirve como apoyo a DiagTrack.
#
#   SysMain            : antiguo "Superfetch"
#                        Precarga en RAM los programas que usas con frecuencia
#                        para que abran mas rapido. Util en HDDs lentos.
#                        En SSDs es innecesario y puede causar picos de uso
#                        de disco en arranque y al volver de suspension.
#                        Solo el perfil Aggressive lo incluye por defecto.
# ==============================================================================

function Invoke-Services {
    Write-GC -Message 'Iniciando deshabilitacion de Services...' -Level 'Action'

    # Lista por defecto: se usa en modo menu o si el perfil no define 'list'.
    $defaultList = @(
        'DiagTrack',         # Telemetria continua a Microsoft
        'dmwappushservice'   # Soporte a telemetria (WAP Push)
    )

    # Get-ProfileValue (Core.psm1) devuelve $defaultList si no hay perfil
    # cargado, o el array 'services.list' del JSON si lo hay.
    $list = Get-ProfileValue -Section 'services' -Key 'list' -Default $defaultList

    $total = $list.Count
    $index = 0

    foreach ($s in $list) {
        $index = $index + 1
        Write-GC -Message ('[' + $index + '/' + $total + '] Servicio: ' + $s) -Level 'Info'
        Disable-ServiceSafe -Name $s
    }

    Write-GC -Message 'Servicios procesados.' -Level 'Info'
}
