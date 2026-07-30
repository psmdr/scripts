# LogCleanup.ps1

A PowerShell script for automated cleanup of outdated log files on Windows Server environments. Supports IIS logs, Exchange IMAP4 and POP3 logs, and any number of custom log paths. Multiple log types can be combined in a single run. The script can also register itself as a Windows Scheduled Task.

## Features

- Clean IIS, Exchange IMAP4, Exchange POP3, and custom log directories in one run
- Configurable retention period via `-DaysToKeep` (global, default: 30 days)
- Safe testing with `-WhatIf` before any files are deleted
- Register, list, and remove Scheduled Tasks directly from the script
- Multiple independent Scheduled Tasks supported (e.g. different log types at different times)
- Exchange installation path detected automatically from the registry (Exchange 2010, 2013, 2016, 2019)
- All log type paths are overridable via explicit path parameters
- Administrator privilege check before any task management operation
- Collision detection on task creation with optional `-Force` override

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Windows Server 2012 R2 / Windows 8.1 or later (for the `ScheduledTasks` module)
- Administrator privileges for Scheduled Task management (`-InstallTask`, `-RemoveTask`)
- Exchange Server (on-premises) for `-IMAP` and `-POP` (only required on Exchange servers)

## Parameters

| Parameter      | Type     | Default | Description                                                         |
| -------------- | -------- | ------- | ------------------------------------------------------------------- |
| `-IIS`         | Switch   | —       | Clean IIS log files                                                 |
| `-IMAP`        | Switch   | —       | Clean Exchange IMAP4 log files                                      |
| `-POP`         | Switch   | —       | Clean Exchange POP3 log files                                       |
| `-CustomPath`  | String[] | —       | One or more additional log directories                              |
| `-IISPath`     | String   | Auto    | Override default IIS log path                                       |
| `-ImapPath`    | String   | Auto    | Override auto-detected IMAP4 log path                               |
| `-PopPath`     | String   | Auto    | Override auto-detected POP3 log path                                |
| `-DaysToKeep`  | Int      | 30      | Retention period in days (applies to all log types)                 |
| `-InstallTask` | Switch   | —       | Register a Scheduled Task for the current parameter set             |
| `-TaskName`    | String   | Auto    | Name of the Scheduled Task (auto-derived from log types if omitted) |
| `-TaskTime`    | String   | `03:00` | Daily run time for the Scheduled Task (format: `HH:mm`)             |
| `-TaskUser`    | String   | SYSTEM  | Optional service account for the Scheduled Task                     |
| `-Force`       | Switch   | —       | Overwrite an existing task with the same name without prompting     |
| `-ListTasks`   | Switch   | —       | List all tasks created by this script                               |
| `-RemoveTask`  | String   | —       | Remove the named Scheduled Task                                     |

## Usage

### Dry run (WhatIf)

```powershell
.\LogCleanup.ps1 -IIS -DaysToKeep 14 -WhatIf
```

Shows which IIS logs older than 14 days would be deleted, without removing anything.

### Clean multiple log types in one run

```powershell
.\LogCleanup.ps1 -IIS -IMAP -POP -DaysToKeep 30
```

### Clean custom directories

```powershell
.\LogCleanup.ps1 -CustomPath "D:\Logs\AppX","E:\Logs\AppY" -DaysToKeep 7
```

### Install a Scheduled Task (runs as SYSTEM)

```powershell
.\LogCleanup.ps1 -InstallTask -IIS -IMAP -DaysToKeep 30 -TaskTime "03:00"
```

Creates a daily task named `LogCleanup_IIS_IMAP` in the `\LogCleanup\` task folder, running at 03:00 as SYSTEM.

### Install a second independent task under a service account

```powershell
.\LogCleanup.ps1 -InstallTask -POP -DaysToKeep 14 -TaskTime "04:30" -TaskName "POP_Nightly" -TaskUser "DOMAIN\svc-logcleanup"
```

The account password is prompted interactively and never stored in the script or task definition.

### List all tasks created by this script

```powershell
.\LogCleanup.ps1 -ListTasks
```

### Remove a task

```powershell
.\LogCleanup.ps1 -RemoveTask "POP_Nightly"
```

### Override log paths

```powershell
.\LogCleanup.ps1 -IIS -IISPath "D:\CustomIISLogs" -DaysToKeep 30
```

## Scheduled Task notes

> **Important:** The Scheduled Task stores the exact file path of the script at the time `-InstallTask` is called. Place the script in a permanent location (e.g. `C:\Scripts\LogCleanup.ps1`) **before** creating any tasks. If the file is later moved or deleted, the scheduled run will fail silently. The script warns if it detects it is being run from a temporary or download directory.

All tasks are stored in the `\LogCleanup\` folder in Task Scheduler, making them easy to identify and manage both via this script and the Task Scheduler GUI.

## Output

The script prints a summary table after each run:

```
Cleanup started. DaysToKeep = 30

Name   Path                                    Found Deleted Errors Skipped Message
----   ----                                    ----- ------- ------ ------- -------
IIS    C:\inetpub\logs\LogFiles              12    12      0      False
IMAP   C:\Exchange\Logging\Imap4             3     3       0      False
POP    C:\Exchange\Logging\Pop3              0     0       0      False

Total: 15 found, 15 deleted, 0 errors.
```

## Notes

- Originally based on an IIS-only cleanup script by Paul Cunningham
- Exchange installation path is read from the registry (`HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup` for Exchange 2013/2016/2019, `v14` for Exchange 2010).
- The script is saved as **UTF-8 with BOM** to ensure correct handling of special characters in Windows PowerShell 5.1.
