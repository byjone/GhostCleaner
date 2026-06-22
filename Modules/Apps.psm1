#Requires -Version 2.0
# ==============================================================================
# Apps.psm1  -  Desinstalar apps preinstaladas (Appx)
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Quita apps que Windows trae instaladas de fabrica y que mucha gente no usa
#   nunca: Xbox, Cortana, apps del fabricante del portatil, etc. Es opcional
#   y la lista de que se quita la decide el perfil, no este modulo.
#
# QUE ES UNA "Appx" / UWP:
#   Desde Windows 8, ademas de los programas de toda la vida (.exe que
#   instalas con un instalador), existe un formato de aplicacion empaquetada
#   llamado APPX/MSIX. Se gestionan distinto: no tienen un "Desinstalar.exe",
#   se quitan con los cmdlets Get-AppxPackage / Remove-AppxPackage.
#
# POR QUE ES "POR USUARIO" Y POR QUE A VECES NO BASTA:
#   Get-AppxPackage sin mas solo ve las apps instaladas para EL USUARIO QUE
#   ejecuta el script. Algunas apps tambien quedan registradas a nivel de
#   "aprovisionamiento" (se instalan automaticamente para cualquier cuenta
#   nueva que se cree en el equipo). Por eso tambien usamos
#   Get-AppxProvisionedPackage, que requiere el modulo Dism y existe desde
#   Windows 8; en Windows 7 simplemente no aplica (no hay Appx).
#
# QUE PASA SI UNA APP NO EXISTE EN ESTE EQUIPO:
#   Get-AppxPackage devuelve $null sin avisar, no es un error. Por eso no usamos
#   try/catch alrededor de la busqueda, solo alrededor de Remove-AppxPackage.
# ==============================================================================


# ==============================================================================
# Remove-GCAppxPackage
# ==============================================================================
# Quita una app por su nombre (o un trozo del nombre) tanto para el usuario
# actual como del aprovisionamiento, si esta disponible.
#
# PARAMETROS:
#   $Name : nombre o fragmento del PackageFullName/Name de la app.
#           Ejemplo: "Microsoft.XboxApp" quita "Microsoft.XboxApp_24.55...".
#           Usamos -like con comodines ("*$Name*") para no depender de la
#           version exacta del paquete, que cambia con cada actualizacion.
# ==============================================================================

function Remove-GCAppxPackage {
    param(
        [Parameter(Mandatory = $true)] [string]$Name
    )

    $patron = '*' + $Name + '*'

    # --- Para el usuario actual --------------------------------------------
    $paquetes = Get-AppxPackage -Name $patron -ErrorAction SilentlyContinue

    if (-not $paquetes) {
        Write-GC -Message ('No instalada (usuario actual): ' + $Name) -Level 'Info'
    } else {
        foreach ($paquete in $paquetes) {
            try {
                Remove-AppxPackage -Package $paquete.PackageFullName -ErrorAction Stop
                Write-GC -Message ('Desinstalada: ' + $paquete.Name) -Level 'Action'
            } catch {
                Write-GC -Message ('No se pudo desinstalar ' + $paquete.Name + ': ' + $_.Exception.Message) -Level 'Warning'
                # No hacemos throw: una app que no se deja quitar (a veces el
                # sistema la protege) no debe parar el resto de la lista.
            }
        }
    }

    # --- Aprovisionamiento: evita que se reinstale para cuentas nuevas ------
    $cmdProvisioned = Get-Command 'Get-AppxProvisionedPackage' -ErrorAction SilentlyContinue
    if ($cmdProvisioned) {
        $provisionados = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like $patron }

        foreach ($p in $provisionados) {
            try {
                $null = Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop
                Write-GC -Message ('Quitada del aprovisionamiento: ' + $p.PackageName) -Level 'Action'
            } catch {
                Write-GC -Message ('No se pudo quitar del aprovisionamiento ' + $p.PackageName + ': ' + $_.Exception.Message) -Level 'Warning'
            }
        }
    }
}


# ==============================================================================
# Invoke-Apps
# ==============================================================================
# Punto de entrada que llama el menu/perfil. Lee la lista de apps a quitar
# desde el perfil activo (apps.list en el JSON). Si no hay perfil cargado,
# usa una lista por defecto conservadora (solo lo que casi nadie usa).
#
# IMPORTANTE: OneDrive NO esta en la lista por defecto a proposito porque
# mucha gente si lo usa para sincronizar archivos; el perfil Aggressive lo
# incluye explicitamente si se quiere.
# ==============================================================================

function Invoke-Apps {
    $listaPorDefecto = @(
        'Microsoft.XboxApp',
        'Microsoft.XboxGamingOverlay',
        'Microsoft.Xbox.TCUI',
        'Microsoft.GamingApp',
        'Microsoft.549981C3F5F10'    # Cortana
    )

    $apps = Get-ProfileValue -Section 'apps' -Key 'list' -Default $listaPorDefecto

    if (-not $apps -or $apps.Count -eq 0) {
        Write-GC -Message 'Apps: no hay ninguna en la lista, no se quita nada.' -Level 'Info'
        return
    }

    Write-GC -Message ('Iniciando desinstalacion de apps preinstaladas (' + $apps.Count + ' en la lista)...') -Level 'Action'

    foreach ($nombreApp in $apps) {
        Remove-GCAppxPackage -Name $nombreApp
    }

    Write-GC -Message 'Apps preinstaladas: proceso completado.' -Level 'Info'
}
