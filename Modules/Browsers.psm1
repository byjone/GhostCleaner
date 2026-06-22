#Requires -Version 2.0
# ==============================================================================
# Browsers.psm1  -  Privacidad de Edge y Chrome (opcional)
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   Ajusta un puñado de opciones de privacidad de Microsoft Edge y Google
#   Chrome mediante politicas de Registro, igual que hace una empresa para
#   gestionar sus equipos. Es opcional y esta desactivado por defecto en
#   todos los perfiles: toca la configuracion del navegador, que es algo
#   mas personal que un servicio de telemetria de Windows.
#
# QUE ES UNA "POLITICA" DE NAVEGADOR (Registry Policy):
#   Tanto Edge como Chrome leen, al arrancar, unas claves de Registro bajo
#   HKLM:\SOFTWARE\Policies\... pensadas originalmente para que un
#   administrador de empresa controle el navegador de sus empleados via GPO.
#   No son ajustes "ocultos": son las mismas claves que usaria una empresa,
#   documentadas oficialmente por Microsoft y Google. La diferencia con
#   cambiarlo desde dentro del navegador es que esto se aplica de una vez
#   para todos los perfiles de usuario de Chrome/Edge en este equipo.
#
# POR QUE HKLM Y NO HKCU:
#   Las politicas de navegador se leen de HKLM (maquina), no de HKCU
#   (usuario). Por eso, igual que el resto de GhostCleaner, este modulo
#   necesita permisos de Administrador.
#
# QUE SE TOCA Y QUE NO:
#   [SI] Informes de diagnostico/metricas que el navegador envia al fabricante
#   [SI] "Do Not Track" (pedir a las webs que no rastreen, no es una garantia
#        pero es el estandar que existe)
#   [SI] Telemetria de "uso y rendimiento" anonima
#   [NO] No se toca el motor de Safe Browsing/anti-phishing: sigue protegiendo
#        contra sitios maliciosos, solo se desactiva el envio de estadisticas
#        EXTENDIDAS de navegacion (la base de Safe Browsing sigue activa)
#   [NO] No se desactiva sincronizacion de cuenta, autorelleno ni contraseñas:
#        eso es comodidad del usuario, no recoleccion de datos para el fabricante
#
# DETECCION DE NAVEGADOR INSTALADO:
#   Antes de escribir nada comprobamos si el ejecutable existe en las rutas
#   habituales. Si el navegador no esta instalado, no tiene sentido crear la
#   politica (y evitamos "ensuciar" el Registro de un equipo que no lo usa).
#
# REVERSION:
#   La opcion [6] Restore SI revierte estos cambios: llama a
#   Undo-GCBrowserPolicies (definida mas abajo), que borra unicamente los
#   valores que este modulo escribio, sin tocar otras politicas que pueda
#   tener configuradas una empresa bajo la misma ruta.
# ==============================================================================


# ==============================================================================
# Test-GCBrowserInstalled
# ==============================================================================
# Comprueba si el ejecutable de un navegador existe en alguna de las rutas
# tipicas de instalacion (64 bits, 32 bits, o instalacion solo para el
# usuario actual, habitual en Chrome).
# ==============================================================================

function Test-GCBrowserInstalled {
    param(
        [Parameter(Mandatory = $true)] [string[]]$PosiblesRutas
    )

    foreach ($ruta in $PosiblesRutas) {
        # [Environment]::ExpandEnvironmentVariables resuelve %LOCALAPPDATA% etc.
        # antes de comprobar Test-Path, porque Test-Path no expande variables
        # de entorno por si solo en todas las versiones de PowerShell.
        $rutaExpandida = [Environment]::ExpandEnvironmentVariables($ruta)
        if (Test-Path $rutaExpandida) {
            return $true
        }
    }

    return $false
}


# ==============================================================================
# Set-GCBrowserPolicy
# ==============================================================================
# Helper generico: escribe un DWORD de politica bajo una ruta de Registro.
# Lo usan tanto Edge como Chrome para no repetir el mismo try/catch seis veces.
#
# PARAMETROS:
#   $Path  : ruta completa de la clave de politica
#   $Name  : nombre del valor (p.ej. "MetricsReportingEnabled")
#   $Value : 0 o 1 normalmente. Los navegadores basados en politicas de
#            Chromium usan practicamente siempre DWORD 0/1 para booleanos.
# ==============================================================================

function Set-GCBrowserPolicy {
    param(
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $true)] [string]$Name,
        [Parameter(Mandatory = $true)] [int]$Value
    )

    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -ErrorAction Stop
        Write-GC -Message ('  ' + $Name + ' = ' + $Value) -Level 'Info'
    } catch {
        Write-GC -Message ('No se pudo escribir ' + $Name + ' en ' + $Path + ': ' + $_.Exception.Message) -Level 'Warning'
        # No relanzamos: una clave que falle no debe tirar todo el modulo abajo,
        # las demas politicas pueden seguir aplicandose sin problema.
    }
}


# ==============================================================================
# Set-EdgePrivacyPolicy
# ==============================================================================
# Aplica las politicas de privacidad de Microsoft Edge.
#
# RUTA: HKLM:\SOFTWARE\Policies\Microsoft\Edge
#
# QUE DESACTIVA:
#   PersonalizationReportingEnabled = 0  : sugerencias personalizadas basadas
#     en tu actividad de navegacion
#   MetricsReportingEnabled = 0          : envio de estadisticas de uso y
#     caidas a Microsoft
#   ConfigureDoNotTrack = 1              : activa la cabecera "Do Not Track"
#     en cada peticion web
#   SearchSuggestEnabled = 0             : la "busqueda predictiva" envia a
#     Microsoft cada caracter que escribes en la barra de direcciones antes
#     de que termines de teclear, para poder sugerirte resultados
#   ConfigureDoNotTrack aparte, AlternateErrorPagesEnabled = 0 : evita que
#     Edge consulte un servicio externo para "embellecer" paginas de error
#     (tambien implica enviar la URL que fallo a un tercero)
# ==============================================================================

function Set-EdgePrivacyPolicy {
    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

    Write-GC -Message 'Aplicando politicas de privacidad de Microsoft Edge...' -Level 'Action'

    Set-GCBrowserPolicy -Path $path -Name 'PersonalizationReportingEnabled' -Value 0
    Set-GCBrowserPolicy -Path $path -Name 'MetricsReportingEnabled'        -Value 0
    Set-GCBrowserPolicy -Path $path -Name 'ConfigureDoNotTrack'            -Value 1
    Set-GCBrowserPolicy -Path $path -Name 'SearchSuggestEnabled'           -Value 0
    Set-GCBrowserPolicy -Path $path -Name 'AlternateErrorPagesEnabled'     -Value 0

    Write-GC -Message 'Edge: politicas de privacidad aplicadas.' -Level 'Info'
}


# ==============================================================================
# Set-ChromePrivacyPolicy
# ==============================================================================
# Aplica las politicas de privacidad de Google Chrome.
#
# RUTA: HKLM:\SOFTWARE\Policies\Google\Chrome
#
# QUE DESACTIVA:
#   MetricsReportingEnabled = 0                    : estadisticas de uso y
#     caidas enviadas a Google ("Usage statistics and crash reports")
#   UrlKeyedAnonymizedDataCollectionEnabled = 0     : el "Make searches and
#     browsing better" que vincula tu navegacion a sugerencias
#   SafeBrowsingExtendedReportingEnabled = 0        : informes EXTENDIDOS de
#     Safe Browsing. El propio Safe Browsing (bloqueo de phishing/malware)
#     sigue funcionando: esto solo apaga el envio de datos adicionales
#   SearchSuggestEnabled = 0                        : igual que en Edge, la
#     busqueda predictiva manda a Google lo que escribes en la barra antes
#     de pulsar Enter
#   SpellCheckUseSpellingService = 0                : el corrector ortografico
#     "mejorado" envia el texto que escribes a los servidores de Google para
#     revisarlo; desactivado, Chrome usa solo el diccionario local
# ==============================================================================

function Set-ChromePrivacyPolicy {
    $path = 'HKLM:\SOFTWARE\Policies\Google\Chrome'

    Write-GC -Message 'Aplicando politicas de privacidad de Google Chrome...' -Level 'Action'

    Set-GCBrowserPolicy -Path $path -Name 'MetricsReportingEnabled'                    -Value 0
    Set-GCBrowserPolicy -Path $path -Name 'UrlKeyedAnonymizedDataCollectionEnabled'    -Value 0
    Set-GCBrowserPolicy -Path $path -Name 'SafeBrowsingExtendedReportingEnabled'       -Value 0
    Set-GCBrowserPolicy -Path $path -Name 'SearchSuggestEnabled'                       -Value 0
    Set-GCBrowserPolicy -Path $path -Name 'SpellCheckUseSpellingService'               -Value 0

    Write-GC -Message 'Chrome: politicas de privacidad aplicadas.' -Level 'Info'
}


# ==============================================================================
# Invoke-Browsers
# ==============================================================================
# Punto de entrada del modulo. Comprueba que navegadores estan instalados y
# aplica las politicas correspondientes segun lo que diga el perfil activo.
#
# CLAVES DEL PERFIL:
#   browsers.enabled : activa/desactiva todo el modulo (false por defecto
#                      en los perfiles incluidos, es opcional a proposito)
#   browsers.edge    : true/false, aplicar o no las politicas de Edge
#   browsers.chrome  : true/false, aplicar o no las politicas de Chrome
#
# SI NO HAY PERFIL ACTIVO (menu interactivo, opcion suelta):
#   Se intenta aplicar a ambos navegadores, cada uno solo si esta instalado.
# ==============================================================================

function Invoke-Browsers {
    $aplicarEdge   = Get-ProfileValue -Section 'browsers' -Key 'edge'   -Default $true
    $aplicarChrome = Get-ProfileValue -Section 'browsers' -Key 'chrome' -Default $true

    $rutasEdge = @(
        (Join-Path $env:ProgramFiles       'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
    )

    $rutasChrome = @(
        (Join-Path $env:ProgramFiles        'Google\Chrome\Application\chrome.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
        '%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe'   # instalacion solo para el usuario actual
    )

    if ($aplicarEdge) {
        if (Test-GCBrowserInstalled -PosiblesRutas $rutasEdge) {
            Set-EdgePrivacyPolicy
        } else {
            Write-GC -Message 'Edge no parece estar instalado en este equipo; se omite.' -Level 'Info'
        }
    }

    if ($aplicarChrome) {
        if (Test-GCBrowserInstalled -PosiblesRutas $rutasChrome) {
            Set-ChromePrivacyPolicy
        } else {
            Write-GC -Message 'Chrome no parece estar instalado en este equipo; se omite.' -Level 'Info'
        }
    }

    if (-not $aplicarEdge -and -not $aplicarChrome) {
        Write-GC -Message 'Browsers: ni Edge ni Chrome estan marcados para ajustar en este perfil.' -Level 'Info'
    }
}


# ==============================================================================
# Undo-GCBrowserPolicies
# ==============================================================================
# Revierte lo que aplican Set-EdgePrivacyPolicy y Set-ChromePrivacyPolicy:
# borra unicamente los VALORES que GhostCleaner escribio (no toda la clave de
# politicas), por si en el futuro una empresa o el propio usuario gestiona
# otras politicas distintas bajo la misma ruta y no queremos llevarnoslas
# por delante.
#
# QUE HACE Remove-ItemProperty:
#   Borra un valor concreto dentro de una clave del Registro, sin tocar el
#   resto de valores que pueda tener esa misma clave. Es lo equivalente a
#   "click derecho -> eliminar" sobre una linea de regedit, no sobre la
#   carpeta completa.
#
# SI LA CLAVE QUEDA VACIA:
#   La dejamos como esta. Una clave de politicas vacia no tiene ningun efecto
#   en el navegador (Edge/Chrome simplemente no encuentran nada que leer ahi),
#   asi que no hace falta borrarla para que el revert sea efectivo.
#
# LLAMADA DESDE Restore.psm1:
#   Invoke-Restore llama a esta funcion como parte de la restauracion. Antes
#   de PowerShell cargar este modulo (Browsers.psm1) la funcion no existiria;
#   por eso el orden de carga en GhostCleaner.ps1 carga Browsers antes que
#   Restore, aunque al usar -Global en realidad no seria estrictamente
#   necesario el orden exacto.
# ==============================================================================

function Undo-GCBrowserPolicies {
    Write-GC -Message 'Revirtiendo politicas de privacidad de Edge/Chrome (si existen)...' -Level 'Action'

    $valoresEdge = @(
        'PersonalizationReportingEnabled',
        'MetricsReportingEnabled',
        'ConfigureDoNotTrack',
        'SearchSuggestEnabled',
        'AlternateErrorPagesEnabled'
    )

    $valoresChrome = @(
        'MetricsReportingEnabled',
        'UrlKeyedAnonymizedDataCollectionEnabled',
        'SafeBrowsingExtendedReportingEnabled',
        'SearchSuggestEnabled',
        'SpellCheckUseSpellingService'
    )

    $rutasYValores = @(
        @{ Ruta = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Valores = $valoresEdge;   Nombre = 'Edge' },
        @{ Ruta = 'HKLM:\SOFTWARE\Policies\Google\Chrome';  Valores = $valoresChrome; Nombre = 'Chrome' }
    )

    foreach ($entrada in $rutasYValores) {
        if (-not (Test-Path $entrada.Ruta)) {
            Write-GC -Message ($entrada.Nombre + ': no hay politicas de GhostCleaner que revertir.') -Level 'Info'
            continue
        }

        $quitados = 0
        foreach ($nombreValor in $entrada.Valores) {
            $existe = Get-ItemProperty -Path $entrada.Ruta -Name $nombreValor -ErrorAction SilentlyContinue
            if ($existe) {
                try {
                    Remove-ItemProperty -Path $entrada.Ruta -Name $nombreValor -ErrorAction Stop
                    $quitados++
                } catch {
                    Write-GC -Message ('No se pudo quitar ' + $nombreValor + ' de ' + $entrada.Nombre + ': ' + $_.Exception.Message) -Level 'Warning'
                }
            }
        }

        if ($quitados -gt 0) {
            Write-GC -Message ($entrada.Nombre + ': ' + $quitados + ' politica(s) revertida(s).') -Level 'Info'
        } else {
            Write-GC -Message ($entrada.Nombre + ': no habia ninguna politica de GhostCleaner aplicada.') -Level 'Info'
        }
    }
}
