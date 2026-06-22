#Requires -Version 2.0
# ==============================================================================
# Restore.psm1  -  Restauracion parcial de cambios aplicados
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Deshace parcialmente los cambios que GhostCleaner aplica. Se llama
#   "parcial" porque NO puede deshacer todo: algunos cambios (como los del
#   Registro o las tareas programadas) requieren hacerlos manualmente.
#
# QUE SE RESTAURA:
#   [SI] Servicios : DiagTrack y dmwappushservice vuelven a inicio "Manual"
#                    (no "Automatico"; para eso usa el panel de Servicios)
#   [SI] Hosts     : se eliminan todas las lineas "0.0.0.0 ..." del archivo hosts
#   [SI] Firewall  : se quitan las reglas "GhostCleaner-*" (bloqueo de
#                    telemetria por IP creado en Security.psm1)
#   [SI] Browsers  : se quitan las politicas de privacidad de Edge/Chrome
#                    aplicadas por Browsers.psm1 (Undo-GCBrowserPolicies)
#
# QUE NO SE RESTAURA (debes hacerlo manualmente si lo necesitas):
#   [NO] Registro  : AllowTelemetry y AdvertisingID
#                    -> abre regedit.exe y navega a las rutas de Privacy.psm1
#   [NO] Tareas    : las tareas deshabilitadas en Tasks.psm1
#                    -> abre "Programador de tareas" y reactivalas una a una
#   [NO] Apps      : las apps desinstaladas en Apps.psm1 no se reinstalan solas
#                    -> usa Microsoft Store para volver a instalarlas
#   [NO] Defender/Firewall (activacion) : estos se reactivan con la opcion [5] Security
#
# ==============================================================================


# ==============================================================================
# Invoke-Restore
# ==============================================================================
# Unica funcion del modulo. Ejecuta ambas restauraciones en secuencia.
#
# RESTAURACION DE SERVICIOS:
#   Set-Service -StartupType Manual devuelve el servicio a inicio bajo demanda.
#   Usamos SilentlyContinue en lugar de Stop para que, si un servicio no existe
#   (puede no estar en todas las versiones de Windows), la restauracion continue
#   con los demas sin interrumpirse.
#
# RESTAURACION DEL ARCHIVO HOSTS:
#   Leemos el archivo completo con Get-Content (devuelve un array de lineas).
#   Filtramos con Where-Object: descartamos las lineas que coincidan con el
#   patron '^0\.0\.0\.0\s+' (cualquier linea que empiece por "0.0.0.0 ").
#     ^ : inicio de linea
#     \. : punto literal (en regex, el punto sin escapar = cualquier caracter)
#     \s+: uno o mas espacios o tabuladores
#   Escribimos el resultado filtrado de vuelta con Set-Content (sobreescribe).
#
# NOTA SOBRE Where-Object:
#   -notmatch usa expresiones regulares (regex), que son patrones de busqueda
#   mas potentes que simples textos. El patron '^0\.0\.0\.0\s+' significa:
#   "lineas que EMPIEZAN por 0.0.0.0 seguido de espacio(s)".
# ==============================================================================

function Invoke-Restore {
    Write-GC -Message 'Iniciando Restore (restauracion parcial)...' -Level 'Action'
    Write-GC -Message 'NOTA: solo se restauran servicios y archivo hosts.' -Level 'Warning'
    Write-GC -Message 'El Registro y las Tareas deben restaurarse manualmente.' -Level 'Warning'

    # ── Reactivar servicios ───────────────────────────────────────────────────
    Write-GC -Message 'Devolviendo servicios a inicio Manual...' -Level 'Action'

    $servicesToEnable = @(
        'DiagTrack',          # Telemetria de Microsoft
        'dmwappushservice'    # WAP Push (soporte a telemetria)
    )

    foreach ($s in $servicesToEnable) {
        Write-GC -Message ('Reactivando: ' + $s) -Level 'Info'
        try {
            # Manual = el servicio no se inicia solo, solo si otra app lo pide.
            # Usamos SilentlyContinue para no romper el bucle si uno falla.
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
            Write-GC -Message ('Servicio en Manual: ' + $s) -Level 'Info'
        } catch {
            Write-GC -Message ('No se pudo reactivar ' + $s + ': ' + $_.Exception.Message) -Level 'Warning'
            # No hacemos 'throw' aqui: seguimos con el siguiente servicio
        }
    }

    # ── Restaurar archivo hosts ───────────────────────────────────────────────
    Write-GC -Message 'Eliminando entradas 0.0.0.0 del archivo hosts...' -Level 'Action'

    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'

    try {
        if (Test-Path $hostsPath) {
            # Get-Content lee el archivo y devuelve cada linea como un elemento del array
            $content = Get-Content -Path $hostsPath -ErrorAction Stop

            # Where-Object filtra el array. $_ es cada linea.
            # -notmatch: mantiene las lineas que NO coincidan con el patron.
            $filtered = $content | Where-Object { $_ -notmatch '^0\.0\.0\.0\s+' }

            # Set-Content sobreescribe el archivo con el contenido filtrado
            Set-Content -Path $hostsPath -Value $filtered -ErrorAction Stop

            Write-GC -Message 'Archivo hosts restaurado: entradas 0.0.0.0 eliminadas.' -Level 'Info'
        } else {
            Write-GC -Message 'Archivo hosts no encontrado; se omite.' -Level 'Warning'
        }
    } catch {
        Write-GC -Message ('Fallo al restaurar hosts: ' + $_.Exception.Message) -Level 'Error'
        throw
    }

    # ── Quitar reglas de Firewall creadas por Block-GCTelemetryFirewall ───────
    Write-GC -Message 'Eliminando reglas de Firewall de telemetria (si existen)...' -Level 'Action'

    try {
        $reglas = Get-NetFirewallRule -DisplayName 'GhostCleaner-*' -ErrorAction SilentlyContinue
        if ($reglas) {
            $reglas | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            Write-GC -Message ('Reglas de Firewall eliminadas: ' + $reglas.Count) -Level 'Info'
        } else {
            Write-GC -Message 'No habia reglas de Firewall de GhostCleaner que quitar.' -Level 'Info'
        }
    } catch {
        Write-GC -Message ('No se pudieron consultar/quitar reglas de Firewall: ' + $_.Exception.Message) -Level 'Warning'
        # No relanzamos: esto es un extra de limpieza, no algo critico para el Restore.
    }

    # ── Revertir politicas de privacidad de Edge/Chrome ───────────────────────
    # Undo-GCBrowserPolicies vive en Browsers.psm1, cargado junto al resto de
    # modulos con -Global, asi que esta disponible aqui sin tener que importarlo
    # de nuevo. Si el modulo Browsers nunca llego a aplicar nada (el usuario no
    # lo activo en su perfil), esta funcion simplemente no encuentra valores que
    # quitar y lo dice por consola, sin marcarlo como error.
    if (Get-Command 'Undo-GCBrowserPolicies' -ErrorAction SilentlyContinue) {
        Undo-GCBrowserPolicies
    }

    Write-GC -Message 'Restore completado (parcial).' -Level 'Info'
}
