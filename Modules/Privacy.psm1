#Requires -Version 2.0
# ==============================================================================
# Privacy.psm1  -  Telemetria y publicidad
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Aplica dos ajustes de privacidad en el Registro de Windows:
#   1. Desactiva el envio de datos de uso (telemetria) a Microsoft.
#   2. Deshabilita el Advertising ID (identificador de publicidad).
#
# INTEGRACION CON PERFILES:
#   Invoke-Privacy comprueba $global:GC_Config (cargado desde el JSON del
#   perfil) para saber que ajustes aplicar. Si no hay perfil activo (menu
#   interactivo), aplica todos los ajustes por defecto.
#
#   Claves del perfil que lee este modulo:
#     privacy.disableTelemetry    -> true/false
#     privacy.disableAdvertisingId -> true/false
#
# QUE ES EL REGISTRO DE WINDOWS:
#   Base de datos central de configuracion del sistema. Se organiza en ramas:
#   HKLM (afecta a todos los usuarios) y HKCU (solo el usuario actual).
#
# ADVERTENCIA:
#   La opcion [6] Restore NO revierte cambios de Registro. Para deshacerlos
#   manualmente abre regedit.exe y navega a las rutas indicadas en cada funcion.
#
# ==============================================================================


# ==============================================================================
# Set-TelemetryPolicy
# ==============================================================================
# Escribe AllowTelemetry = 0 en la politica de Windows.
#
# RUTA: HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection
# VALOR: AllowTelemetry = 0 (DWORD)
#
# NIVELES: 0=Seguridad(minimo), 1=Basico, 2=Mejorado, 3=Completo(defecto)
# ==============================================================================

function Set-TelemetryPolicy {
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'

    Write-GC -Message 'Creando clave de politica de telemetria en el Registro...' -Level 'Action'

    try {
        New-Item -Path $path -Force | Out-Null
    } catch {
        Write-GC -Message ('No se pudo crear la clave: ' + $_.Exception.Message) -Level 'Error'
        throw
    }

    Write-GC -Message 'Escribiendo AllowTelemetry = 0 (telemetria desactivada)...' -Level 'Action'

    try {
        Set-ItemProperty -Path $path -Name 'AllowTelemetry' -Value 0 -Type DWord -ErrorAction Stop
        Write-GC -Message 'Politica de telemetria aplicada.' -Level 'Info'
    } catch {
        Write-GC -Message ('No se pudo escribir AllowTelemetry: ' + $_.Exception.Message) -Level 'Error'
        throw
    }
}


# ==============================================================================
# Disable-AdvertisingID
# ==============================================================================
# Desactiva el identificador unico de publicidad de Windows.
#
# RUTA: HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo
# VALOR: Enabled = 0
# ==============================================================================

function Disable-AdvertisingID {
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'

    Write-GC -Message 'Deshabilitando Advertising ID...' -Level 'Action'

    try {
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name 'Enabled' -Value 0 -ErrorAction Stop
            Write-GC -Message 'Advertising ID deshabilitado.' -Level 'Info'
        } else {
            Write-GC -Message 'Clave AdvertisingInfo no encontrada; ya estaba desactivado o no aplica.' -Level 'Warning'
        }
    } catch {
        Write-GC -Message ('Fallo al deshabilitar Advertising ID: ' + $_.Exception.Message) -Level 'Error'
        throw
    }
}


# ==============================================================================
# Invoke-Privacy
# ==============================================================================
# Punto de entrada del modulo. Lee el perfil activo (si existe) para saber
# que ajustes aplicar. Sin perfil, aplica todo por defecto.
# ==============================================================================

function Invoke-Privacy {
    Write-GC -Message 'Iniciando Privacy...' -Level 'Action'

    # Leemos las preferencias del perfil. Get-ProfileValue devuelve $true
    # si no hay perfil activo (modo menu = comportamiento completo por defecto).
    $doTelemetry    = Get-ProfileValue -Section 'privacy' -Key 'disableTelemetry'    -Default $true
    $doAdvertising  = Get-ProfileValue -Section 'privacy' -Key 'disableAdvertisingId' -Default $true

    if ($doTelemetry) {
        Invoke-WithProgress -OperationName 'Politica de telemetria' -ScriptBlock { Set-TelemetryPolicy }
    } else {
        Write-GC -Message 'Telemetria: omitida segun perfil.' -Level 'Info'
    }

    if ($doAdvertising) {
        Invoke-WithProgress -OperationName 'Advertising ID' -ScriptBlock { Disable-AdvertisingID }
    } else {
        Write-GC -Message 'Advertising ID: omitido segun perfil.' -Level 'Info'
    }

    Write-GC -Message 'Privacy completado.' -Level 'Info'
}
