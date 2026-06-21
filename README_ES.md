# GhostCleaner

Script de PowerShell para reducir la telemetría y la publicidad de Windows, y dejar el equipo un poco más ligero sin tener que andar tocando el registro a mano cada vez que reinstalas.

Nació de hacer lo mismo en cada PC nuevo que configuraba: desactivar DiagTrack, quitar el Advertising ID, deshabilitar un puñado de tareas programadas de "Customer Experience Improvement Program"... Al final lo junté todo en un script con perfiles, para no tener que recordar la lista cada vez.

## Qué hace y qué no hace

GhostCleaner toca registro, servicios, tareas programadas, el archivo hosts y un par de ajustes de seguridad. No es un "optimizador milagroso" ni promete duplicar el rendimiento: lo que hace es desactivar procesos de recogida de datos y dejar el Firewall/Defender en un estado conocido. La parte de limpieza de temporales es la típica, nada del otro mundo.

No toca apps preinstaladas (Xbox, Cortana, etc.), no añade reglas de Firewall a nivel de IP ni gestiona configuración de navegadores. Si en algún momento se añade, irá en un módulo nuevo dentro de `Modules\`.

## Cómo está montado

```
GhostCleaner.ps1        <- lanzador. Carga los modulos y decide que hacer
Modules\
  Core.psm1             <- helpers comunes: logging, menu, carga de perfiles
  Privacy.psm1          <- telemetria y advertising ID (Registro)
  Services.psm1         <- DiagTrack, dmwappushservice, SysMain...
  Tasks.psm1            <- tareas programadas de CEIP y compatibilidad
  Hosts.psm1            <- bloqueo de dominios de telemetria via hosts
  Optimizer.psm1        <- temporales y flush de DNS
  Security.psm1         <- Firewall y Defender
  Restore.psm1          <- deshace servicios y hosts (parcial)
  Audit.psm1            <- solo lee el estado actual, no cambia nada
Profiles\
  Safe.json             <- solo lo que no afecta al funcionamiento normal
  Balanced.json          <- el que uso yo por defecto
  Aggressive.json       <- todo lo anterior + Superfetch y mas tareas
Backup\                 <- se crea sola. Estado del sistema antes de cada cambio
Logs\                   <- se crea sola. Logs de sesion e informes HTML
```

Cada módulo expone una función `Invoke-<Nombre>` (`Invoke-Privacy`, `Invoke-Services`...) que `Core.psm1` llama según lo que diga el perfil cargado. Si quieres añadir un módulo propio, basta con seguir ese patrón y añadirlo a la lista `$modules` del lanzador.

Los perfiles son JSON con una sección por módulo. Cada sección tiene `enabled` y, si aplica, la lista de servicios/tareas/dominios concretos. Si quitas una clave del JSON, el módulo simplemente no se ejecuta para esa sección — no hace falta que el JSON esté completo.

## Cómo se usa

### Menú interactivo

```
.\GhostCleaner.ps1
```

Te deja elegir módulo por módulo. Pensado para la primera vez, cuando quieres ver qué hace cada cosa antes de aplicarla.

### Por perfil, sin menú

```powershell
.\GhostCleaner.ps1 -Profile Safe
.\GhostCleaner.ps1 -Profile Balanced
.\GhostCleaner.ps1 -Profile Aggressive
```

Aplica todo lo que el perfil tenga marcado como `enabled` sin pasar por el menú. Antes de aplicar nada crea un punto de restauración del sistema y guarda en `Backup\` una foto del estado previo (servicios, claves de registro, hosts original).

### Solo algunos módulos del perfil

```powershell
.\GhostCleaner.ps1 -Profile Balanced -Modules Privacy,Security
```

Útil si ya tienes aplicado el resto y solo quieres tocar un par de cosas.

### Simulación, sin tocar nada real

```powershell
.\GhostCleaner.ps1 -Profile Aggressive -DryRun
```

Recorre el perfil y dice qué haría en cada paso, pero no llega a ejecutar ningún cambio. Lo uso para revisar un perfil personalizado antes de soltarlo en una máquina de verdad.

### Modo desatendido (GPO / SCCM / aprovisionamiento)

```powershell
.\GhostCleaner.ps1 -Profile Safe -Silent
```

Sin pausas de teclado ni prompts. El log a fichero sigue siendo completo, solo se silencia la consola.

### Solo diagnóstico

```powershell
.\GhostCleaner.ps1 -Audit
```

Lee el estado actual de telemetría, servicios, hosts, Firewall y Defender, y lo muestra en una tabla. No cambia nada. Sirve para comprobar si un equipo ya tiene aplicado algo o para verificar en remoto que sigue cumpliendo lo esperado.

## Perfiles personalizados

Puedes copiar cualquier `.json` de `Profiles\`, renombrarlo y ajustarlo a tu gusto. Antes de ejecutarlo, `Invoke-Profile` valida que las secciones conocidas tengan un `enabled` booleano y avisa si algo no encaja, en vez de fallar a mitad de la ejecución sin explicación.

## Sobre el dominio / GPO

Si el script detecta que el equipo está unido a un dominio de Active Directory, avisa antes de aplicar el perfil: en redes de empresa es habitual que una política de grupo gestione telemetría, Defender o tareas programadas, y puede revertir estos cambios en el siguiente `gpupdate`. El aviso es informativo, no bloquea la ejecución — la decisión es tuya.

## Logs e informes

Cada sesión escribe un log con marca de tiempo en `Logs\`, y se rotan automáticamente los más antiguos (se conservan los últimos 20 por defecto). Al terminar de aplicar un perfil se genera también un informe HTML con qué se ejecutó, qué falló y qué se omitió — pensado para poder adjuntarlo a un ticket o a documentación interna si esto se usa en varios equipos.

## Cómo deshacer cambios

Hay tres niveles, de menos a más invasivo:

1. **Restore.psm1** (opción `[6]` del menú o `Invoke-Restore`): reactiva DiagTrack/dmwappushservice a Manual y limpia las líneas `0.0.0.0` del hosts. No toca registro ni tareas.
2. **Backup de estado** en `Backup\SystemState_*.json`: la foto exacta de cómo estaba el equipo antes de aplicar el perfil. Útil para comparar o restaurar manualmente clave por clave.
3. **Punto de restauración del sistema**: si algo va realmente mal, "Restaurar sistema" de Windows devuelve el equipo entero al estado anterior. Se crea automáticamente salvo que uses `-SkipRestorePoint`.

## Requisitos

- Windows 7 a 11 (algunos módulos usan cmdlets que no existen en todas las ediciones — por ejemplo `Checkpoint-Computer` puede no estar disponible en Server; si falla, el script avisa y sigue).
- PowerShell 2.0 en adelante. El código evita sintaxis exclusiva de versiones modernas; donde hace falta algo de PS 3.0+ (como `ConvertFrom-Json`), hay un fallback para 2.0.
- Ejecutar como Administrador. Sin eso, la mayoría de cambios fallan sin aplicar nada.

## Contribuir

Issues y pull requests en [github.com/byjone/GhostCleaner](https://github.com/byjone/GhostCleaner). Si añades un módulo nuevo, que siga el patrón `Invoke-<Nombre>` y que los comentarios expliquen el porqué, no solo el qué — el código está pensado para que alguien sin experiencia en PowerShell pueda leerlo y entender qué está pasando.

Cosas que tengo en la cabeza para cuando haya tiempo: desinstalar apps preinstaladas vía `Get-AppxPackage`, reglas de Firewall de salida contra IPs de telemetría (más robusto que el hosts si Microsoft las cambia). Si te apetece adelantarte a alguna, mejor abrir un issue antes para no duplicar trabajo.
