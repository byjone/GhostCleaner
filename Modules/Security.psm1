#Requires -Version 2.0
# ==============================================================================
# Security.psm1  -  Firewall y Windows Defender
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Reactiva dos elementos de seguridad basicos que a veces quedan desactivados
#   tras instalar cierto software o aplicar tweaks de rendimiento:
#   1. El Firewall de Windows en sus tres perfiles.
#   2. La proteccion en tiempo real de Windows Defender.
#
# QUE ES EL FIREWALL DE WINDOWS:
#   Controla que conexiones de red se permiten entrar y salir del equipo.
#   Windows lo divide en tres "perfiles" segun el tipo de red detectada:
#     Dominio  : redes corporativas con controlador de dominio (trabajo/empresa)
#     Privado  : redes de confianza (casa, casa de un amigo)
#     Publico  : redes desconocidas (cafeteria, aeropuerto, hotel)
#   Cada perfil puede tener reglas distintas. Lo normal es que el perfil
#   Publico sea el mas restrictivo.
#
# QUE ES WINDOWS DEFENDER:
#   El antivirus integrado de Windows. Su "proteccion en tiempo real" analiza
#   archivos y procesos continuamente mientras el sistema esta en uso.
#   Algunos programas (optimizadores, antivirus de terceros) lo desactivan
#   sin avisar. Este modulo lo reactiva.
#
# COMPATIBILIDAD DEL FIREWALL (por que hay dos metodos):
#   El cmdlet Set-NetFirewallProfile usa un tipo interno llamado GpoBoolean
#   que en ciertas versiones/builds de Windows no acepta $true/$false directos.
#   Usamos netsh.exe como metodo primario porque es universal (Win XP -> Win 11)
#   y no depende de tipos .NET del modulo NetSecurity.
#
# ==============================================================================


# ==============================================================================
# Enable-Firewall
# ==============================================================================
# Activa el Firewall en los tres perfiles usando netsh como metodo primario.
#
# METODO PRIMARIO: netsh advfirewall
#   Herramienta de red de linea de comandos incluida en Windows desde XP.
#   Sintaxis: netsh advfirewall set <perfil>profile state on
#   $LASTEXITCODE recoge el codigo de salida del ultimo ejecutable externo:
#     0 = exito,  distinto de 0 = fallo
#
# FALLBACK: Set-NetFirewallProfile
#   Solo si netsh falla. Resolvemos GpoBoolean en tiempo de ejecucion con
#   System.Type.GetType() y Enum.ToObject() para evitar el error de conversion.
#   Si el tipo no existe en el entorno actual, usamos $true como ultimo intento.
# ==============================================================================

function Enable-Firewall {
    Write-GC -Message 'Activando Firewall en los tres perfiles (Domain/Private/Public)...' -Level 'Action'

    $profiles = @('domain', 'private', 'public')
    $allOk    = $true

    foreach ($prof in $profiles) {
        try {
            # 2>&1 redirige stderr a stdout para capturar todos los mensajes en $out
            $out = netsh advfirewall set ($prof + 'profile') state on 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-GC -Message ('netsh fallo en perfil ' + $prof + ': ' + $out) -Level 'Warning'
                $allOk = $false
            } else {
                Write-GC -Message ('Perfil ' + $prof + ': activado.') -Level 'Info'
            }
        } catch {
            Write-GC -Message ('Error en netsh para perfil ' + $prof + ': ' + $_.Exception.Message) -Level 'Warning'
            $allOk = $false
        }
    }

    if ($allOk) {
        Write-GC -Message 'Firewall habilitado en todos los perfiles (netsh).' -Level 'Action'
        return
    }

    # ── Fallback: cmdlet Set-NetFirewallProfile ───────────────────────────────
    Write-GC -Message 'netsh fallo en algun perfil; intentando con cmdlet...' -Level 'Warning'

    $cmdlet = Get-Command 'Set-NetFirewallProfile' -ErrorAction SilentlyContinue
    if (-not $cmdlet) {
        Write-GC -Message 'Set-NetFirewallProfile no disponible en este sistema.' -Level 'Error'
        throw 'No se pudo habilitar el Firewall: netsh fallo y el cmdlet no esta disponible.'
    }

    try {
        # Resolvemos el tipo GpoBoolean en tiempo de ejecucion.
        # GetType() devuelve $null si el tipo no existe (en lugar de lanzar error).
        # Enum.ToObject() convierte el entero 1 al valor enum equivalente a "True".
        $gpoBoolType = [System.Type]::GetType(
            'Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean'
        )
        $enabled = if ($gpoBoolType) {
            [System.Enum]::ToObject($gpoBoolType, 1)
        } else {
            $true   # Ultimo recurso si el tipo tampoco se puede resolver
        }

        Set-NetFirewallProfile -Profile 'Domain','Public','Private' -Enabled $enabled -ErrorAction Stop
        Write-GC -Message 'Firewall habilitado (cmdlet).' -Level 'Action'
    } catch {
        Write-GC -Message ('Fallo al habilitar Firewall (cmdlet): ' + $_.Exception.Message) -Level 'Error'
        throw
    }
}


# ==============================================================================
# Enable-Defender
# ==============================================================================
# Reactiva la proteccion en tiempo real de Windows Defender.
#
# Set-MpPreference modifica la configuracion de Windows Defender (Mp = MpEngine,
# el motor del antivirus). El parametro -DisableRealtimeMonitoring acepta
# $true (desactivar) o $false (activar). Lo ponemos en $false para activarlo.
#
# Este cmdlet puede no estar disponible en:
#   - Windows 7 / 8 (usa Microsoft Security Essentials, distinto motor)
#   - Sistemas donde Defender fue reemplazado por un antivirus de terceros
#   Si falla, el catch lo reporta y propaga para que el menu lo muestre.
# ==============================================================================

function Enable-Defender {
    Write-GC -Message 'Reactivando proteccion en tiempo real de Windows Defender...' -Level 'Action'

    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Write-GC -Message 'Windows Defender: proteccion en tiempo real activada.' -Level 'Info'
    } catch {
        Write-GC -Message ('Fallo al configurar Defender: ' + $_.Exception.Message) -Level 'Error'
        throw
    }
}


# ==============================================================================
# Invoke-Security
# ==============================================================================
# Punto de entrada que llama el menu. Lee del perfil activo que pasos aplicar:
#   security.enableFirewall -> activar el Firewall en los tres perfiles
#   security.enableDefender -> reactivar la proteccion en tiempo real
# Si no hay perfil cargado (modo menu interactivo), se hacen ambos pasos.
# ==============================================================================

function Invoke-Security {
    Write-GC -Message 'Iniciando Security...' -Level 'Action'

    $doFirewall = Get-ProfileValue -Section 'security' -Key 'enableFirewall' -Default $true
    $doDefender = Get-ProfileValue -Section 'security' -Key 'enableDefender' -Default $true

    if ($doFirewall) {
        Invoke-WithProgress -OperationName 'Firewall' -ScriptBlock { Enable-Firewall }
    } else {
        Write-GC -Message 'Firewall: omitido segun perfil.' -Level 'Info'
    }

    if ($doDefender) {
        Invoke-WithProgress -OperationName 'Defender' -ScriptBlock { Enable-Defender }
    } else {
        Write-GC -Message 'Defender: omitido segun perfil.' -Level 'Info'
    }

    Write-GC -Message 'Security aplicado.' -Level 'Info'
}
