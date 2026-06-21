#Requires -Version 2.0
# ==============================================================================
# Optimizer.psm1  -  Limpieza de temporales y cache DNS
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Realiza dos tareas de mantenimiento basico:
#   1. Elimina archivos temporales de las carpetas TEMP del sistema y del usuario.
#   2. Vacia la cache DNS local.
#
# QUE SON LOS ARCHIVOS TEMPORALES:
#   Cuando instalas programas, actualizas Windows o usas aplicaciones, se crean
#   archivos auxiliares en carpetas "Temp". En teoria se borran solos al terminar,
#   pero en la practica se acumulan y ocupan espacio (a veces varios GB).
#   Borrarlos es completamente seguro: ningun programa en uso los necesita.
#
#   Carpetas que se limpian:
#     %TEMP%           : C:\Users\TuUsuario\AppData\Local\Temp  (usuario actual)
#     C:\Windows\Temp  : temporales del sistema operativo
#
# QUE ES LA CACHE DNS:
#   Cuando visitas una web, Windows guarda la correspondencia "nombre -> IP"
#   durante un tiempo para no tener que volver a preguntarle al servidor DNS.
#   Si esa cache queda corrupta o desactualizada, algunas webs pueden no cargar
#   o dar errores de conexion. "flushdns" la vacia para que Windows las resuelva
#   de nuevo desde cero.
#
# ==============================================================================


# ==============================================================================
# Clear-Folder
# ==============================================================================
# Borra todo el CONTENIDO de una carpeta sin borrar la carpeta en si.
#
# PARAMETROS:
#   $Path : ruta de la carpeta a limpiar
#
# Get-ChildItem -Recurse lista todos los archivos y subcarpetas dentro de $Path.
# -Force incluye archivos ocultos y del sistema.
# -ErrorAction SilentlyContinue en Get-ChildItem: si algun archivo esta en uso
#   y no se puede leer su informacion, se omite sin interrumpir el listado.
# Remove-Item -Force -Recurse: elimina incluso si es de solo lectura o carpeta.
#   Tambien usa SilentlyContinue porque algunos archivos bloqueados por el
#   sistema no se pueden borrar; los saltamos sin error.
# ==============================================================================

function Clear-Folder {
    param(
        [Parameter(Mandatory = $true)] [string]$Path
    )

    Write-GC -Message ('Limpiando carpeta: ' + $Path) -Level 'Action'

    try {
        if (Test-Path -Path $Path) {
            Get-ChildItem -Path $Path -Force -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object {
                    # ForEach-Object procesa cada archivo/carpeta del listado.
                    # $_ es el "objeto actual" en cada iteracion del pipeline.
                    Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
                }
            Write-GC -Message ('Carpeta limpiada: ' + $Path) -Level 'Info'
        } else {
            # Es posible que la carpeta no exista en algunas versiones o configs
            Write-GC -Message ('Carpeta no encontrada (se omite): ' + $Path) -Level 'Warning'
        }
    } catch {
        Write-GC -Message ('Fallo al limpiar ' + $Path + ': ' + $_.Exception.Message) -Level 'Error'
        throw
    }
}


# ==============================================================================
# Invoke-Optimizer
# ==============================================================================
# Punto de entrada que llama el menu. Lee del perfil activo que pasos aplicar:
#   optimizer.cleanUserTemp   -> limpiar %TEMP% del usuario actual
#   optimizer.cleanSystemTemp -> limpiar C:\Windows\Temp
#   optimizer.flushDns        -> vaciar la cache DNS
# Si no hay perfil cargado (modo menu interactivo), se hacen los tres pasos.
#
# $env:TEMP    : variable de entorno que apunta a la carpeta Temp del usuario.
# $env:windir  : variable de entorno que apunta a C:\Windows (o donde este).
# Join-Path    : une partes de una ruta de forma segura (anade '\' donde toca).
#
# ipconfig /flushdns es un comando del sistema (no un cmdlet de PowerShell).
# Lo llamamos directamente; PowerShell puede ejecutar cualquier .exe del PATH.
# $null = ... descarta la salida del comando para no llenar la pantalla.
# ==============================================================================

function Invoke-Optimizer {
    Write-GC -Message 'Iniciando Optimizer...' -Level 'Action'

    $doUserTemp   = Get-ProfileValue -Section 'optimizer' -Key 'cleanUserTemp'   -Default $true
    $doSystemTemp = Get-ProfileValue -Section 'optimizer' -Key 'cleanSystemTemp' -Default $true
    $doFlushDns   = Get-ProfileValue -Section 'optimizer' -Key 'flushDns'        -Default $true

    if ($doUserTemp) {
        Clear-Folder -Path $env:TEMP
    } else {
        Write-GC -Message 'Limpieza de Temp de usuario: omitida segun perfil.' -Level 'Info'
    }

    if ($doSystemTemp) {
        Clear-Folder -Path (Join-Path $env:windir 'Temp')
    } else {
        Write-GC -Message 'Limpieza de Temp del sistema: omitida segun perfil.' -Level 'Info'
    }

    if ($doFlushDns) {
        Write-GC -Message 'Vaciando cache DNS con ipconfig /flushdns...' -Level 'Action'
        try {
            $null = ipconfig /flushdns
            Write-GC -Message 'Cache DNS vaciada correctamente.' -Level 'Info'
        } catch {
            Write-GC -Message ('Fallo en flushdns: ' + $_.Exception.Message) -Level 'Error'
            throw
        }
    } else {
        Write-GC -Message 'Vaciado de cache DNS: omitido segun perfil.' -Level 'Info'
    }

    Write-GC -Message 'Optimizacion completada.' -Level 'Info'
}
