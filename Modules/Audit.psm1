#Requires -Version 2.0
# ==============================================================================
# Audit.psm1  -  Diagnostico de solo lectura
# ==============================================================================
#
# QUE ES ESTE ARCHIVO:
#   A diferencia del resto de modulos, este NO cambia nada en el sistema.
#   Solo lee el estado actual de cada ajuste que los demas modulos podrian
#   tocar y lo muestra en pantalla. Sirve para responder a "¿que tengo ya
#   aplicado?" antes de decidir que perfil usar, o para verificar en remoto
#   que un equipo de empresa sigue cumpliendo la configuracion esperada.
#
# QUE ES UN PSCustomObject:
#   Es un objeto generico de PowerShell al que le vas anadiendo propiedades
#   con la sintaxis @{ Propiedad = Valor }. Lo usamos aqui para construir
#   una "fila" de resultado por cada ajuste comprobado (Nombre, Estado,
#   Esperado) y poder imprimirlas todas juntas con Format-Table al final.
# ==============================================================================


# ==============================================================================
# Invoke-Audit
# ==============================================================================
# Recorre los ajustes principales de Privacy, Services, Tasks y Hosts y
# muestra su estado ACTUAL, sin modificar nada. Devuelve tambien la lista
# de resultados por si se quiere volcar a un informe con Export-GCReport.
# ==============================================================================

function Invoke-Audit {
    Write-GC -Message 'Modo auditoria: solo lectura, no se cambia nada.' -Level 'Action'
    Write-Host ''

    # Usamos una lista generica en lugar de un array normal porque vamos a ir
    # anadiendo elementos uno a uno con .Add() (mas eficiente que "+=" sobre
    # un array, que internamente crea un array nuevo en cada vuelta).
    $resultados = New-Object System.Collections.Generic.List[Object]

    # ── Registro: telemetria y advertising ID ─────────────────────────────────
    $rutaTelemetria = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    $valorTelemetria = $null
    if (Test-Path $rutaTelemetria) {
        $valorTelemetria = (Get-ItemProperty -Path $rutaTelemetria -ErrorAction SilentlyContinue).AllowTelemetry
    }
    $resultados.Add([PSCustomObject]@{
        Ajuste   = 'Telemetria (AllowTelemetry)'
        Actual   = $(if ($null -eq $valorTelemetria) { 'No configurado' } else { $valorTelemetria })
        Esperado = '0 (desactivada)'
    })

    $rutaAdvId = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
    $valorAdvId = $null
    if (Test-Path $rutaAdvId) {
        $valorAdvId = (Get-ItemProperty -Path $rutaAdvId -ErrorAction SilentlyContinue).Enabled
    }
    $resultados.Add([PSCustomObject]@{
        Ajuste   = 'Advertising ID'
        Actual   = $(if ($null -eq $valorAdvId) { 'No configurado' } else { $valorAdvId })
        Esperado = '0 (desactivado)'
    })

    # ── Servicios ──────────────────────────────────────────────────────────────
    foreach ($nombreServicio in @('DiagTrack', 'dmwappushservice', 'SysMain')) {
        $svc = Get-Service -Name $nombreServicio -ErrorAction SilentlyContinue
        $estadoTexto = if ($svc) { $svc.Status.ToString() + ' / ' + $svc.StartType.ToString() } else { 'No existe en este equipo' }
        $resultados.Add([PSCustomObject]@{
            Ajuste   = ('Servicio: ' + $nombreServicio)
            Actual   = $estadoTexto
            Esperado = 'Stopped / Disabled'
        })
    }

    # ── Archivo hosts ───────────────────────────────────────────────────────────
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $lineasBloqueadas = 0
    if (Test-Path $hostsPath) {
        $lineasBloqueadas = (Get-Content -Path $hostsPath | Where-Object { $_ -match '^0\.0\.0\.0\s+' }).Count
    }
    $resultados.Add([PSCustomObject]@{
        Ajuste   = 'Dominios bloqueados en hosts'
        Actual   = $lineasBloqueadas
        Esperado = 'Mayor que 0 si se aplico Hosts'
    })

    # ── Firewall y Defender ─────────────────────────────────────────────────────
    try {
        $perfilesFw = Get-NetFirewallProfile -ErrorAction Stop
        $fwActivo = ($perfilesFw | Where-Object { -not $_.Enabled }).Count -eq 0
        $resultados.Add([PSCustomObject]@{
            Ajuste   = 'Firewall (los 3 perfiles)'
            Actual   = $(if ($fwActivo) { 'Activado' } else { 'Algun perfil desactivado' })
            Esperado = 'Activado'
        })
    } catch {
        $resultados.Add([PSCustomObject]@{ Ajuste = 'Firewall'; Actual = 'No se pudo consultar (cmdlet no disponible)'; Esperado = 'Activado' })
    }

    try {
        $defender = Get-MpComputerStatus -ErrorAction Stop
        $resultados.Add([PSCustomObject]@{
            Ajuste   = 'Defender (proteccion en tiempo real)'
            Actual   = $(if ($defender.RealTimeProtectionEnabled) { 'Activada' } else { 'Desactivada' })
            Esperado = 'Activada'
        })
    } catch {
        $resultados.Add([PSCustomObject]@{ Ajuste = 'Defender'; Actual = 'No se pudo consultar (cmdlet no disponible)'; Esperado = 'Activada' })
    }

    # Mostramos la tabla en pantalla. Format-Table -AutoSize calcula el ancho
    # de cada columna segun el contenido mas largo, para que no quede cortado.
    $resultados | Format-Table -AutoSize | Out-String | Write-Host

    Write-GC -Message ('Auditoria completada: ' + $resultados.Count + ' ajustes revisados.') -Level 'Info'

    return $resultados
}
