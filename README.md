# GhostCleaner

PowerShell script to reduce Windows telemetry and advertising, and make the system a bit leaner without having to manually tweak the registry every time you reinstall.

It started from doing the same things on every new PC I set up: disabling DiagTrack, removing the Advertising ID, disabling a handful of "Customer Experience Improvement Program" scheduled tasks... Eventually, I bundled everything into a script with profiles so I wouldn't have to remember the full checklist every time.

## What It Does (and Doesn't Do)

GhostCleaner modifies the registry, services, scheduled tasks, the hosts file, outbound firewall rules, preinstalled apps (Appx), and a few security settings. It is **not** a "miracle optimizer" and does not claim to double your performance: its purpose is to disable data collection processes and leave Firewall/Defender in a known state. The temporary file cleanup is standard housekeeping, nothing extraordinary.

It does not enforce browser configuration changes by default: that functionality lives in a separate module (`Browsers.psm1`) which is **disabled by default** in all profiles because it affects more personal preferences than a Windows telemetry service. You can enable it if you want.

## Project Structure

```text
GhostCleaner.ps1        <- launcher. Loads modules and decides what to run
Modules\
  Core.psm1             <- shared helpers: logging, menu, profiles, plugins
  Compat.psm1           <- Windows/PowerShell version checks at startup
  Privacy.psm1          <- telemetry and Advertising ID (Registry)
  Services.psm1         <- DiagTrack, dmwappushservice, SysMain...
  Tasks.psm1            <- CEIP and compatibility scheduled tasks
  Hosts.psm1            <- telemetry domain blocking via hosts
  Optimizer.psm1        <- temporary files and DNS flush
  Security.psm1         <- Firewall, Defender, and telemetry IP blocking
  Apps.psm1             <- removes preinstalled apps (Appx/UWP)
  Browsers.psm1         <- Edge/Chrome privacy settings (optional, via Registry)
  Restore.psm1          <- restores services, hosts, firewall, and browser policies
  Audit.psm1            <- read-only status audit, no changes
  Update.psm1           <- notifies about new GitHub Releases versions
Profiles\
  Safe.json             <- only changes that do not affect normal operation
  Balanced.json         <- my default profile
  Aggressive.json       <- everything above + Superfetch, more tasks, and IP blocking
Plugins\                <- optional. Your own custom modules (see below)
Backup\                 <- created automatically. System state before each change
Logs\                   <- created automatically. Session logs and HTML reports
```

Each module exposes an `Invoke-<Name>` function (`Invoke-Privacy`, `Invoke-Apps`, etc.) which `Core.psm1` calls according to the loaded profile. Profiles are JSON files with one section per module: `enabled` plus, where applicable, a list of services, tasks, domains, or apps. If you remove a key from the JSON, the corresponding module simply does not run for that section—there is no need for a complete JSON file.

## Usage

### Interactive Menu

```powershell
.\GhostCleaner.ps1
```

Lets you choose modules one by one, including Audit, Apps, and Browsers. Intended for first-time use when you want to see exactly what each component does before applying changes.

### Profile Mode (No Menu)

```powershell
.\GhostCleaner.ps1 -Profile Safe
.\GhostCleaner.ps1 -Profile Balanced
.\GhostCleaner.ps1 -Profile Aggressive
```

Applies everything marked as `enabled` in the selected profile without showing the menu. Before making any changes, it creates a System Restore Point and saves a snapshot of the current state in `Backup\` (services, registry keys, original hosts file).

### Launcher Parameters

| Parameter           | Description                                                                                                     |
| ------------------- | --------------------------------------------------------------------------------------------------------------- |
| `-Profile <name>`   | Applies the specified profile (`Safe`, `Balanced`, `Aggressive`, or a custom profile) without showing the menu. |
| `-Modules <list>`   | Restricts execution to specific modules from the profile, e.g. `-Modules Privacy,Security`.                     |
| `-DryRun`           | Simulates execution and shows what would happen without making any changes.                                     |
| `-Silent`           | Unattended mode: no keyboard pauses or prompts (intended for GPO/SCCM deployment).                              |
| `-Audit`            | Only reads the current system state. Overrides `-Profile` if both are specified.                                |
| `-SkipRestorePoint` | Skips creation of a System Restore Point before applying a profile.                                             |

Examples:

```powershell
.\GhostCleaner.ps1 -Profile Aggressive -DryRun
.\GhostCleaner.ps1 -Profile Balanced -Modules Privacy,Security
.\GhostCleaner.ps1 -Profile Safe -Silent
.\GhostCleaner.ps1 -Audit
```

## Modules: Apps, Firewall Blocking, Compat, Update, and Browsers

* **Apps** (`apps` in JSON): removes preinstalled apps using `Get-AppxPackage` / `Remove-AppxPackage`, both for the current user and from provisioning packages (so they do not return for new users). The default list only removes Xbox and Cortana. OneDrive is left untouched unless you explicitly add it because many people actually use it.
* **Telemetry Blocking via Firewall** (`firewallBlock` in JSON, inside `Security.psm1`): in addition to the hosts file, creates outbound firewall rules against the resolved IP addresses of telemetry domains. More resilient if Microsoft changes a domain name or if something connects directly by IP without DNS. Rules use the `GhostCleaner-` prefix and are automatically removed by the `[6] Restore` option.
* **Compat** (`Compat.psm1`): detects the Windows and PowerShell version at startup and reports which features are unavailable in the current environment (for example, Appx on Windows 7). Informational only—it never blocks execution.
* **Update** (`Update.psm1`): checks the public GitHub Releases API at startup and notifies if a newer version is available. If GitHub is unavailable or there is no internet connection, it fails silently and never interrupts the rest of the script.
* **Browsers** (`browsers` in JSON, disabled by default): adjusts Edge and Chrome privacy settings using the same Registry policy keys (`HKLM:\SOFTWARE\Policies\...`) that enterprises use to manage browsers. Disables usage/crash reporting, predictive search, and browsing-based personalization; enables "Do Not Track" in Edge; disables Chrome's extended Safe Browsing reporting and cloud spell checker. Phishing and malware protection itself remains enabled—only additional data reporting is disabled. It does not modify account sync, autofill, or saved passwords. Changes are only applied to detected browsers, and `[6] Restore` reverts exactly the values written by GhostCleaner without touching any unrelated policies managed by an organization.

## Custom Profiles

You can copy any `.json` file from `Profiles\`, rename it, and customize it as needed. Before execution, `Test-GCProfile` / `Invoke-Profile` validates that known sections (including `apps`, `browsers`, `firewallBlock`, and `plugins`) contain a valid boolean `enabled` field and warns if something looks wrong, rather than failing halfway through execution without explanation.

## Plugins: Add Your Own Module Without Modifying the Core

If you need a highly specific module for your own use case (removing a company application, changing a specific registry key, etc.), there is no need to modify `GhostCleaner.ps1` or submit a pull request for something that only applies to your environment:

1. Create `Plugins\YourPlugin.psm1` with an `Invoke-YourPlugin` function. Inside it, you can use `Write-GC`, `Get-ProfileValue`, and all other helpers from `Core.psm1`.
2. Add the following to your profile JSON:

```json
"plugins": {
  "enabled": true,
  "list": ["YourPlugin"]
}
```

3. That's it. `GhostCleaner.ps1` automatically loads everything inside `Plugins\` and `Invoke-Profile` executes plugins at the end, after the built-in modules.

## Domain / GPO Considerations

If the script detects that the machine is joined to an Active Directory domain, it displays a warning before applying a profile. In enterprise environments, Group Policy often manages telemetry, Defender, or scheduled tasks and may revert these changes during the next `gpupdate`.

The warning is informational only and does not block execution—the decision is yours.

## Logs and Reports

Each session writes a timestamped log file to `Logs\`, and older logs are automatically rotated (the latest 20 are kept by default).

After a profile is applied, an HTML report is also generated showing what was executed, what failed, and what was skipped. This is intended for attaching to support tickets or internal documentation when the script is used across multiple machines.

## Reverting Changes

There are three levels of recovery, from least to most invasive:

1. **Restore.psm1** (menu option `[6]` or `Invoke-Restore`): sets DiagTrack and dmwappushservice back to Manual, removes `0.0.0.0` entries from the hosts file, deletes `GhostCleaner-*` firewall rules, and restores Edge/Chrome privacy policies. It does not restore telemetry registry settings, scheduled tasks, or removed apps.
2. **State Backup** in `Backup\SystemState_*.json`: an exact snapshot of the system before the profile was applied. Useful for comparison or manual restoration of individual settings.
3. **System Restore Point**: if something goes seriously wrong, Windows System Restore can return the entire system to its previous state. A restore point is created automatically unless `-SkipRestorePoint` is used.

## Requirements

* Windows 7 through Windows 11 (some modules rely on cmdlets unavailable in all editions—for example, `Checkpoint-Computer` may not exist on some Server editions, and Appx is not available on Windows 7. If something is unavailable, the script warns and continues).
* PowerShell 2.0 or later. The code avoids syntax exclusive to modern versions; where PowerShell 3.0+ features are required (such as `ConvertFrom-Json`), a PowerShell 2.0 fallback is provided.
* Must be run as Administrator. Without elevated privileges, most changes will fail and nothing will be applied.

## Contributing

Issues and pull requests are welcome at https://github.com/byjone/GhostCleaner.

If you add a new core module, follow the `Invoke-<Name>` pattern and make sure comments explain **why** something is being done, not just **what** it does.

If the functionality is highly specific to your own environment, consider implementing it as a plugin (see above) rather than adding it to the core project.
