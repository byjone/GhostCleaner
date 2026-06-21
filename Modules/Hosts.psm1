#Requires -Version 2.0
# ==============================================================================
# Hosts.psm1  -  Bloqueo de dominios de telemetria via archivo hosts
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Anade entradas al archivo "hosts" del sistema para bloquear conexiones
#   salientes hacia servidores de telemetria de Microsoft.
#
# QUE ES EL ARCHIVO HOSTS:
#   Es un archivo de texto plano que Windows consulta ANTES de hacer una
#   peticion DNS. Si un dominio aparece en hosts apuntando a 0.0.0.0 (o
#   127.0.0.1), Windows lo considera "ya resuelto" y nunca llega a contactar
#   con el servidor real. Es el metodo de bloqueo mas basico y efectivo.
#
#   Ubicacion: C:\Windows\System32\drivers\etc\hosts
#   (necesita permisos de Administrador para modificarse)
#
# FORMATO DE LAS ENTRADAS QUE SE ANADEN:
#   0.0.0.0 telemetry.microsoft.com
#   0.0.0.0 watson.telemetry.microsoft.com
#   ...
#   0.0.0.0 es una direccion "nula": ninguna conexion puede llegar ahi.
#
# LA OPCION [6] RESTORE elimina todas las lineas que empiecen por "0.0.0.0"
# del archivo hosts, deshaciendo exactamente lo que hace este modulo.
#
# ==============================================================================


# ==============================================================================
# Add-HostsBlock
# ==============================================================================
# Para cada dominio de la lista:
#   1. Comprueba si ya existe una entrada para ese dominio (evita duplicados).
#   2. Si no existe, anade la linea "0.0.0.0 dominio".
#
# PARAMETROS:
#   $Domains : array de strings con los dominios a bloquear
#
# Select-String es el equivalente de 'grep' en PowerShell.
#   -Pattern  : patron de busqueda (usamos [regex]::Escape para que puntos
#               y otros caracteres especiales de regex no causen confusion)
#   -Quiet    : devuelve $true/$false en lugar del objeto con la coincidencia
#
# Add-Content anade texto al final del archivo sin sobreescribirlo.
# ==============================================================================

function Add-HostsBlock {
    param(
        [Parameter(Mandatory = $true)] [string[]]$Domains
    )

    # Construimos la ruta con variables de entorno para compatibilidad maxima.
    # $env:SystemRoot suele ser C:\Windows, pero puede variar en instalaciones custom.
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'

    foreach ($d in $Domains) {
        Write-GC -Message ('Comprobando si ya esta bloqueado: ' + $d) -Level 'Info'

        $alreadyPresent = $false

        try {
            # Buscamos el dominio en el archivo hosts.
            # [regex]::Escape convierte "telemetry.microsoft.com" en un patron
            # seguro: "telemetry\.microsoft\.com" (el punto en regex significa
            # "cualquier caracter"; escaparlo lo convierte en un punto literal).
            if (Select-String -Path $hostsPath -Pattern ([regex]::Escape($d)) -Quiet -ErrorAction Stop) {
                $alreadyPresent = $true
            }
        } catch {
            Write-GC -Message ('No se pudo leer hosts al comprobar ' + $d + ': ' + $_.Exception.Message) -Level 'Warning'
        }

        if ($alreadyPresent) {
            Write-GC -Message ('Ya estaba bloqueado (se omite): ' + $d) -Level 'Info'
            continue   # 'continue' salta al siguiente dominio del bucle foreach
        }

        try {
            Add-Content -Path $hostsPath -Value ('0.0.0.0 ' + $d) -ErrorAction Stop
            Write-GC -Message ('Dominio bloqueado: ' + $d) -Level 'Action'
        } catch {
            Write-GC -Message ('Fallo al bloquear ' + $d + ': ' + $_.Exception.Message) -Level 'Error'
            throw
        }
    }
}


# ==============================================================================
# Invoke-Hosts
# ==============================================================================
# Punto de entrada que llama el menu. Lee la lista de dominios a bloquear
# desde el perfil activo (hosts.domains en el JSON). Si no hay perfil cargado
# (modo menu interactivo), usa la lista por defecto de toda la vida.
#
# DOMINIOS QUE SE PUEDEN BLOQUEAR (segun el perfil elegido):
#   telemetry.microsoft.com         : endpoint principal de telemetria
#   watson.telemetry.microsoft.com  : informes de errores (Dr. Watson)
#   vortex.data.microsoft.com       : pipeline de datos de telemetria
#   settings-win.data.microsoft.com : configuracion remota de telemetria
#   (el perfil Aggressive anade varios mas; revisa Profiles\Aggressive.json)
# ==============================================================================

function Invoke-Hosts {
    # Lista por defecto: se usa en modo menu o si el perfil no define 'domains'.
    $defaultDomains = @(
        'telemetry.microsoft.com',
        'watson.telemetry.microsoft.com',
        'vortex.data.microsoft.com',
        'settings-win.data.microsoft.com'
    )

    # Get-ProfileValue (Core.psm1) devuelve $defaultDomains si no hay perfil
    # cargado, o el array 'hosts.domains' del JSON si lo hay.
    $domains = Get-ProfileValue -Section 'hosts' -Key 'domains' -Default $defaultDomains

    Write-GC -Message 'Iniciando bloqueo de dominios en archivo hosts...' -Level 'Action'
    Add-HostsBlock -Domains $domains
    Write-GC -Message 'Bloqueo de hosts completado.' -Level 'Info'
}
