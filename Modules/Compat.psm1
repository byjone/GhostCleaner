#Requires -Version 2.0
# ==============================================================================
# Compat.psm1  -  Comprobacion de compatibilidad al arrancar
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Detecta la version de Windows y de PowerShell del equipo donde se ejecuta
#   GhostCleaner, y avisa de antemano si alguna funcion no va a estar
#   disponible. Asi el aviso aparece al principio, no a mitad de un perfil
#   cuando ya se han aplicado otros cambios.
#
# QUE ES $PSVersionTable:
#   Una variable automatica que PowerShell define siempre, con informacion
#   sobre si mismo: $PSVersionTable.PSVersion es la version instalada.
#
# QUE ES [System.Environment]::OSVersion:
#   Devuelve la version interna de Windows (numero de build), no el nombre
#   comercial ("Windows 11"). Por eso comparamos numeros de build en vez de
#   nombres: Microsoft no expone el nombre comercial de forma fiable via .NET.
# ==============================================================================


# ==============================================================================
# Test-GCCompatibility
# ==============================================================================
# Comprueba version de PowerShell y de Windows, y devuelve advertencias sobre
# que cmdlets podrian no funcionar en este entorno. No bloquea la ejecucion:
# solo informa, porque muchas funciones tienen su propio try/catch y fallback.
# ==============================================================================

function Test-GCCompatibility {
    Write-GC -Message 'Comprobando compatibilidad del entorno...' -Level 'Action'

    $psVersion = $PSVersionTable.PSVersion
    Write-GC -Message ('PowerShell detectado: ' + $psVersion.ToString()) -Level 'Info'

    if ($psVersion.Major -lt 3) {
        Write-GC -Message 'PowerShell 2.0: ConvertFrom-Json no existe, se usara el fallback con JavaScriptSerializer.' -Level 'Warning'
    }

    # Build de Windows. Algunos cortes de referencia utiles:
    #   7600/7601 -> Windows 7
    #   9200      -> Windows 8
    #   9600      -> Windows 8.1
    #   10240+    -> Windows 10
    #   22000+    -> Windows 11
    $build = [System.Environment]::OSVersion.Version.Build
    Write-GC -Message ('Build de Windows detectado: ' + $build) -Level 'Info'

    if ($build -lt 9200) {
        # Windows 7: sin Appx, sin algunos cmdlets de NetSecurity modernos.
        Write-GC -Message 'Windows 7 detectado: el modulo Apps (Appx) no aplica, no existen apps UWP en este sistema.' -Level 'Warning'
        Write-GC -Message 'El bloqueo de telemetria por Firewall puede depender de netsh en lugar de cmdlets modernos.' -Level 'Warning'
    }

    if (-not (Get-Command 'Set-MpPreference' -ErrorAction SilentlyContinue)) {
        Write-GC -Message 'Set-MpPreference no disponible: el modulo Security no podra reactivar Defender en este equipo.' -Level 'Warning'
    }

    if (-not (Get-Command 'New-NetFirewallRule' -ErrorAction SilentlyContinue)) {
        Write-GC -Message 'New-NetFirewallRule no disponible: el bloqueo de telemetria por Firewall se omitira si se solicita.' -Level 'Warning'
    }

    Write-GC -Message 'Comprobacion de compatibilidad completada.' -Level 'Info'
}
