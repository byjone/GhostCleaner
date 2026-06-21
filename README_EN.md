# GhostCleaner

PowerShell script to reduce Windows telemetry and advertising, and make the system a bit leaner without manually tweaking the registry every time you reinstall.

It started from doing the same tweaks on every new PC I set up: disabling DiagTrack, removing the Advertising ID, turning off a handful of "Customer Experience Improvement Program" scheduled tasks... Eventually I bundled everything into a profile-based script so I wouldn't have to remember the whole checklist every time.

## What it does — and what it doesn't

GhostCleaner modifies the registry, services, scheduled tasks, the hosts file, and a few security settings. It is **not** a "magic optimizer" and it doesn't claim to double your performance: its goal is to disable data collection components and leave Firewall/Defender in a known state. The temporary file cleanup is the usual housekeeping stuff, nothing fancy.

It does not remove built-in apps (Xbox, Cortana, etc.), add IP-level Firewall rules, or manage browser settings. If any of that gets added in the future, it will live in a separate module under `Modules\`.

## Project structure

```text
GhostCleaner.ps1        <- entry point. Loads modules and decides what to run
Modules\
  Core.psm1             <- shared helpers: logging, menu, profile loading
  Privacy.psm1          <- telemetry and Advertising ID (Registry)
  Services.psm1         <- DiagTrack, dmwappushservice, SysMain...
  Tasks.psm1            <- CEIP and compatibility scheduled tasks
  Hosts.psm1            <- telemetry domain blocking via hosts file
  Optimizer.psm1        <- temp cleanup and DNS flush
  Security.psm1         <- Firewall and Defender
  Restore.psm1          <- restores services and hosts changes (partial)
  Audit.psm1            <- read-only status checks
Profiles\
  Safe.json             <- only changes that don't affect normal operation
  Balanced.json         <- my default profile
  Aggressive.json       <- everything above plus Superfetch and more tasks
Backup\                 <- created automatically. System state snapshots
Logs\                   <- created automatically. Session logs and HTML reports
```

Each module exposes an `Invoke-<Name>` function (`Invoke-Privacy`, `Invoke-Services`, etc.), which `Core.psm1` calls depending on the loaded profile. If you want to add your own module, just follow the same pattern and add it to the launcher's `$modules` list.

Profiles are JSON files with one section per module. Each section contains an `enabled` flag and, when applicable, a list of specific services, tasks, or domains. If you remove a key from the JSON, the module simply skips that section — the profile doesn't need to be fully populated.

## Usage

### Interactive menu

```powershell
.\GhostCleaner.ps1
```

Lets you choose modules one by one. Intended for first-time use, when you want to see what each module does before applying changes.

### Apply a profile without the menu

```powershell
.\GhostCleaner.ps1 -Profile Safe
.\GhostCleaner.ps1 -Profile Balanced
.\GhostCleaner.ps1 -Profile Aggressive
```

Applies everything marked as `enabled` in the selected profile. Before making any changes, the script creates a System Restore Point and stores a snapshot of the current state in `Backup\` (services, registry values, original hosts file).

### Run only specific modules

```powershell
.\GhostCleaner.ps1 -Profile Balanced -Modules Privacy,Security
```

Useful if you've already applied everything else and only want to adjust a couple of areas.

### Simulation mode (no real changes)

```powershell
.\GhostCleaner.ps1 -Profile Aggressive -DryRun
```

Walks through the profile and reports what it would do, without actually changing anything. Handy for reviewing custom profiles before running them on a real machine.

### Unattended mode (GPO / SCCM / provisioning)

```powershell
.\GhostCleaner.ps1 -Profile Safe -Silent
```

No keyboard pauses or prompts. File logging remains fully enabled; only console output is minimized.

### Audit only

```powershell
.\GhostCleaner.ps1 -Audit
```

Reads the current state of telemetry, services, hosts, Firewall, and Defender, then displays the results in a table. No changes are made. Useful to verify whether a machine is already configured or to remotely check compliance.

## Custom profiles

You can copy any `.json` file from `Profiles\`, rename it, and tweak it as needed.

Before execution, `Invoke-Profile` validates that all known sections contain a boolean `enabled` property and warns about invalid entries instead of failing halfway through execution with an obscure error.

## Domain / Group Policy considerations

If the script detects that the machine is joined to an Active Directory domain, it displays a warning before applying the profile.

In corporate environments, Group Policies often manage telemetry, Defender settings, or scheduled tasks, and may revert these changes during the next `gpupdate`. The warning is informational only and does not block execution — the choice is yours.

## Logs and reports

Each session writes a timestamped log file to `Logs\`, and older logs are rotated automatically (the latest 20 are kept by default).

After a profile finishes, an HTML report is also generated showing what ran successfully, what failed, and what was skipped. This is useful if the script is used across multiple machines and the results need to be attached to tickets or internal documentation.

## Restoring changes

There are three levels of rollback, from least to most invasive:

1. **Restore.psm1** (menu option `[6]` or `Invoke-Restore`): sets DiagTrack and dmwappushservice back to Manual startup and removes `0.0.0.0` entries from the hosts file. Registry values and scheduled tasks are not restored.
2. **State backups** in `Backup\SystemState_*.json`: an exact snapshot of the machine before the profile was applied. Useful for comparison or manual restoration.
3. **System Restore Point**: if something goes seriously wrong, Windows System Restore can revert the entire machine to its previous state. Created automatically unless `-SkipRestorePoint` is used.

## Requirements

* Windows 7 through Windows 11 (some modules rely on cmdlets that may not exist on every edition — for example, `Checkpoint-Computer` may be unavailable on Server editions. If a feature is missing, the script warns and continues).
* PowerShell 2.0 or later. The code avoids modern-only syntax where possible; when PowerShell 3.0+ features such as `ConvertFrom-Json` are required, a fallback implementation is used.
* Administrator privileges. Without them, most changes will fail silently or not be applied.

## Contributing

Issues and pull requests are welcome.

If you add a new module, follow the `Invoke-<Name>` pattern and make sure comments explain **why** something is being done, not just **what** it does. The codebase is intended to be understandable even for people with limited PowerShell experience.

Ideas currently on the backlog:

* Removing built-in apps via `Get-AppxPackage`
* Outbound Firewall rules targeting telemetry IP ranges (more resilient than hosts-based blocking if Microsoft changes domains)

If you'd like to work on one of these, opening an issue first is appreciated to avoid duplicated effort.
