# GhostCleaner

Script de PowerShell para reducir la telemetría y la publicidad de Windows, y dejar el equipo un poco más ligero sin tener que andar tocando el registro a mano cada vez que reinstalas.

Nació de hacer lo mismo en cada PC nuevo que configuraba: desactivar DiagTrack, quitar el Advertising ID, deshabilitar un puñado de tareas programadas de "Customer Experience Improvement Program"... Al final lo junté todo en un script con perfiles, para no tener que recordar la lista cada vez.

Versión actual: **1.3.1**. Ver [CHANGELOG.md](CHANGELOG.md) para el historial completo.

## Qué hace y qué no hace

GhostCleaner toca registro, servicios, tareas programadas, el archivo hosts, reglas de Firewall de salida, apps preinstaladas (Appx) y un par de ajustes de seguridad. No es un "optimizador milagroso" ni promete duplicar el rendimiento: lo que hace es desactivar procesos de recogida de datos y dejar el Firewall/Defender en un estado conocido. La parte de limpieza de temporales es la típica, nada del otro mundo.

No gestiona configuración de navegadores de forma obligatoria: eso vive en un módulo aparte (`Browsers.psm1`) que está **desactivado por defecto** en todos los perfiles, porque toca algo más personal que un servicio de telemetría de Windows — lo activas tú si quieres.

## Cómo está montado

```
GhostCleaner.ps1        <- lanzador. Carga los modulos y decide que hacer
Modules\
  Core.psm1             <- helpers comunes: logging, menu, perfiles, plugins
  Compat.psm1           <- comprobacion de version de Windows/PowerShell al arrancar
  Privacy.psm1          <- telemetria y advertising ID (Registro)
  Services.psm1         <- DiagTrack, dmwappushservice, SysMain...
  Tasks.psm1            <- tareas programadas de CEIP y compatibilidad
  Hosts.psm1            <- bloqueo de dominios de telemetria via hosts
  Optimizer.psm1        <- temporales y flush de DNS
  Security.psm1         <- Firewall, Defender y bloqueo de telemetria por IP
  Apps.psm1             <- desinstala apps preinstaladas (Appx/UWP)
  Browsers.psm1         <- privacidad de Edge/Chrome (opcional, via Registro)
  Restore.psm1          <- deshace servicios, hosts, Firewall y politicas de navegador
  Audit.psm1            <- solo lee el estado actual, no cambia nada
  Update.psm1           <- avisa si hay una version nueva en GitHub Releases
Profiles\
  Safe.json             <- solo lo que no afecta al funcionamiento normal
  Balanced.json         <- el que uso yo por defecto
  Aggressive.json       <- todo lo anterior + Superfetch, mas tareas y bloqueo por IP
Plugins\                <- opcional. Modulos propios que quieras anadir (ver mas abajo)
Backup\                 <- se crea sola. Estado del sistema antes de cada cambio
Logs\                   <- se crea sola. Logs de sesion e informes HTML
```

Cada módulo expone una función `Invoke-<Nombre>` (`Invoke-Privacy`, `Invoke-Apps`...) que `Core.psm1` llama según lo que diga el perfil cargado. Los perfiles son JSON con una sección por módulo: `enabled` y, si aplica, la lista de servicios/tareas/dominios/apps concretos. Si quitas una clave del JSON, el módulo simplemente no se ejecuta para esa sección — no hace falta que el JSON esté completo.

## Cómo se usa

### Menú interactivo

```
.\GhostCleaner.ps1
```

Te deja elegir módulo por módulo, incluyendo Audit, Apps y Browsers. Pensado para la primera vez, cuando quieres ver qué hace cada cosa antes de aplicarla.

### Por perfil, sin menú

```powershell
.\GhostCleaner.ps1 -Profile Safe
.\GhostCleaner.ps1 -Profile Balanced
.\GhostCleaner.ps1 -Profile Aggressive
```

Aplica todo lo que el perfil tenga marcado como `enabled` sin pasar por el menú. Antes de aplicar nada crea un punto de restauración del sistema y guarda en `Backup\` una foto del estado previo (servicios, claves de registro, hosts original).

### Parámetros del lanzador

| Parámetro | Qué hace |
|---|---|
| `-Profile <nombre>` | Aplica el perfil indicado (`Safe`, `Balanced`, `Aggressive` o uno personalizado) sin pasar por el menú. |
| `-Modules <lista>` | Limita la ejecución a esos módulos del perfil, p.ej. `-Modules Privacy,Security`. |
| `-DryRun` | Simula la ejecución: muestra qué haría sin cambiar nada real. |
| `-Silent` | Modo desatendido: sin pausas de teclado ni prompts (pensado para GPO/SCCM). |
| `-Audit` | Solo lee el estado actual del sistema. Ignora `-Profile` si se indican los dos. |
| `-SkipRestorePoint` | Omite la creación del punto de restauración del sistema antes de aplicar el perfil. |

Ejemplos:

```powershell
.\GhostCleaner.ps1 -Profile Aggressive -DryRun
.\GhostCleaner.ps1 -Profile Balanced -Modules Privacy,Security
.\GhostCleaner.ps1 -Profile Safe -Silent
.\GhostCleaner.ps1 -Audit
```

## Módulos: Apps, bloqueo por Firewall, Compat, Update y Browsers

- **Apps** (`apps` en el JSON): desinstala apps preinstaladas vía `Get-AppxPackage`/`Remove-AppxPackage`, tanto para el usuario actual como del aprovisionamiento (para que no se reinstalen en cuentas nuevas). La lista por defecto solo quita Xbox y Cortana; OneDrive no se toca a menos que lo añadas tú mismo a la lista, porque mucha gente lo usa de verdad.
- **Bloqueo de telemetría por Firewall** (`firewallBlock` en el JSON, dentro de `Security.psm1`): además del archivo hosts, crea una regla de salida contra las IPs resueltas de los dominios de telemetría. Más robusto si Microsoft cambia un dominio o si algo se conecta directo a una IP sin pasar por DNS. Las reglas llevan el prefijo `GhostCleaner-` y se limpian solas con la opción `[6] Restore`.
- **Compat** (`Compat.psm1`): al arrancar, detecta la versión de Windows y de PowerShell y avisa de qué funciones no van a estar disponibles en ese entorno (por ejemplo, Appx en Windows 7). Es informativo, no bloquea nada.
- **Update** (`Update.psm1`): consulta la API pública de GitHub Releases al arrancar y avisa si hay una versión más reciente. Si no hay conexión o GitHub no responde, falla en silencio — nunca interrumpe el resto del script.
- **Browsers** (`browsers` en el JSON, desactivado por defecto): ajusta privacidad de Edge y Chrome vía las mismas claves de política de Registro (`HKLM:\SOFTWARE\Policies\...`) que usaría una empresa para gestionar el navegador de sus equipos. Desactiva informes de uso/caídas, búsqueda predictiva y personalización basada en navegación; activa "Do Not Track" en Edge; desactiva el reporte extendido de Safe Browsing y el corrector ortográfico "en la nube" en Chrome — el bloqueo de phishing/malware en sí sigue activo, solo se apaga el envío de datos adicionales. No toca sincronización de cuenta, autorelleno ni contraseñas guardadas. Solo se aplica al navegador que detecte instalado, y `[6] Restore` revierte exactamente los valores que escribió (no toca otras políticas que pueda tener configuradas una empresa en la misma ruta).

## Perfiles personalizados

Puedes copiar cualquier `.json` de `Profiles\`, renombrarlo y ajustarlo a tu gusto. Antes de ejecutarlo, `Test-GCProfile`/`Invoke-Profile` valida que las secciones conocidas (incluyendo `apps`, `browsers`, `firewallBlock` y `plugins`) tengan un `enabled` booleano y avisa si algo no encaja, en vez de fallar a mitad de la ejecución sin explicación.

## Plugins: añadir tu propio módulo sin tocar el núcleo

Si quieres un módulo muy específico de tu caso (limpiar una app de empresa, una clave de registro concreta...), no hace falta tocar `GhostCleaner.ps1` ni mandar un pull request para algo tan tuyo:

1. Crea `Plugins\TuPlugin.psm1` con una función `Invoke-TuPlugin`. Dentro puedes usar `Write-GC`, `Get-ProfileValue` y el resto de helpers de `Core.psm1` con normalidad.
2. En tu perfil JSON, añade:
   ```json
   "plugins": {
     "enabled": true,
     "list": ["TuPlugin"]
   }
   ```
3. Listo. `GhostCleaner.ps1` carga todo lo que haya en `Plugins\` automáticamente y `Invoke-Profile` lo ejecuta al final, después de los módulos del núcleo.

## Sobre el dominio / GPO

Si el script detecta que el equipo está unido a un dominio de Active Directory, avisa antes de aplicar el perfil: en redes de empresa es habitual que una política de grupo gestione telemetría, Defender o tareas programadas, y puede revertir estos cambios en el siguiente `gpupdate`. El aviso es informativo, no bloquea la ejecución — la decisión es tuya.

## Logs e informes

Cada sesión escribe un log con marca de tiempo en `Logs\`, y se rotan automáticamente los más antiguos (se conservan los últimos 20 por defecto). Al terminar de aplicar un perfil se genera también un informe HTML con qué se ejecutó, qué falló y qué se omitió — pensado para poder adjuntarlo a un ticket o a documentación interna si esto se usa en varios equipos.

## Cómo deshacer cambios

Hay tres niveles, de menos a más invasivo:

1. **Restore.psm1** (opción `[6]` del menú o `Invoke-Restore`): reactiva DiagTrack/dmwappushservice a Manual, limpia las líneas `0.0.0.0` del hosts, quita las reglas de Firewall `GhostCleaner-*` y revierte las políticas de privacidad de Edge/Chrome. No toca registro de telemetría, tareas ni apps desinstaladas.
2. **Backup de estado** en `Backup\SystemState_*.json`: la foto exacta de cómo estaba el equipo antes de aplicar el perfil. Útil para comparar o restaurar manualmente clave por clave.
3. **Punto de restauración del sistema**: si algo va realmente mal, "Restaurar sistema" de Windows devuelve el equipo entero al estado anterior. Se crea automáticamente salvo que uses `-SkipRestorePoint`.

## Requisitos

- Windows 7 a 11 (algunos módulos usan cmdlets que no existen en todas las ediciones — por ejemplo `Checkpoint-Computer` puede no estar disponible en Server, o Appx no existe en Windows 7; si falla, el script avisa y sigue).
- PowerShell 2.0 en adelante. El código evita sintaxis exclusiva de versiones modernas; donde hace falta algo de PS 3.0+ (como `ConvertFrom-Json`), hay un fallback para 2.0.
- Ejecutar como Administrador. Sin eso, la mayoría de cambios fallan sin aplicar nada.

## Contribuir

Issues y pull requests en [github.com/byjone/GhostCleaner](https://github.com/byjone/GhostCleaner). Si añades un módulo nuevo al núcleo, que siga el patrón `Invoke-<Nombre>` y que los comentarios expliquen el porqué, no solo el qué. Si es algo muy específico de tu caso, mejor como plugin (ver más arriba) que como módulo del núcleo.
