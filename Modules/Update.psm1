#Requires -Version 2.0
# ==============================================================================
# Update.psm1  -  Comprobacion de version contra GitHub Releases
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Mira si hay una version mas reciente de GhostCleaner publicada en GitHub
#   y avisa si la hay. No descarga ni instala nada por si solo, solo informa.
#
# QUE ES Invoke-RestMethod:
#   Cmdlet que hace una peticion HTTP y, si la respuesta es JSON (como la API
#   de GitHub), la convierte automaticamente en un objeto de PowerShell. Es
#   el equivalente a usar curl + ConvertFrom-Json en un solo paso.
#
# POR QUE TODO VA EN TRY/CATCH SIN RELANZAR EL ERROR:
#   Esto se ejecuta sin que el usuario lo haya pedido explicitamente (al
#   arrancar el script). Si no hay conexion a internet, o GitHub no responde,
#   o el equipo esta detras de un proxy raro de empresa, NO debe impedir que
#   el resto de GhostCleaner funcione. Por eso cualquier fallo aqui termina
#   en un aviso silencioso, nunca en un error que pare el script.
#
# VERSION ACTUAL DEL PROYECTO:
#   Se guarda como constante aqui. Cuando se publique una release nueva en
#   GitHub, actualiza $script:GC_CurrentVersion a juego con el tag del release.
# ==============================================================================

$script:GC_CurrentVersion = '1.0.0'


# ==============================================================================
# Test-GCUpdateAvailable
# ==============================================================================
# Consulta la API publica de GitHub (no requiere autenticacion para repos
# publicos) y compara el tag de la ultima release con la version actual.
#
# FORMATO ESPERADO DEL TAG: "v1.2.3" o "1.2.3". Quitamos una "v" inicial si
# existe antes de comparar, para no depender de que el mantenedor sea
# consistente con el prefijo.
# ==============================================================================

function Test-GCUpdateAvailable {
    param(
        [string]$RepoApiUrl = 'https://api.github.com/repos/byjone/GhostCleaner/releases/latest',
        [int]$TimeoutSeconds = 5
    )

    try {
        # -UseBasicParsing evita depender del motor de Internet Explorer que
        # Invoke-RestMethod usa por defecto en PS 5.1 y anteriores en algunos
        # sistemas; sin el, puede fallar en un Windows recien instalado donde
        # IE nunca se ha ejecutado una primera vez.
        $release = Invoke-RestMethod -Uri $RepoApiUrl -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop

        $tagRemoto = $release.tag_name -replace '^v', ''

        if ($tagRemoto -and ($tagRemoto -ne $script:GC_CurrentVersion)) {
            Write-GC -Message ('Hay una version nueva disponible: ' + $tagRemoto + ' (tienes ' + $script:GC_CurrentVersion + ').') -Level 'Warning'
            Write-GC -Message ('Descargala en: ' + $release.html_url) -Level 'Info'
            return $true
        }

        Write-GC -Message ('GhostCleaner esta actualizado (version ' + $script:GC_CurrentVersion + ').') -Level 'Info'
        return $false
    } catch {
        # Sin conexion, GitHub caido, proxy de empresa, etc. No es un error
        # del script, asi que solo lo dejamos como informacion de bajo nivel.
        Write-GC -Message ('No se pudo comprobar actualizaciones (sin conexion o GitHub no disponible).') -Level 'Info'
        return $false
    }
}
