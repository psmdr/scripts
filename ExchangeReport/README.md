# ExchangeReport

A PowerShell script that collects health and capacity information about an
on-premises Exchange Server environment (mailbox counts, database status,
replication, disk space, message queues, certificates, critical services)
and sends a summarized HTML report by mail. A copy of the report can
optionally be saved to disk.

The script is environment agnostic: all environment specific values, all
thresholds, and every optional check are controlled through an external JSON
config file, so the same script file can be reused across multiple Exchange
organizations without any code changes.

## Contents

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Configuration reference](#configuration-reference)
- [Command line reference](#command-line-reference)
- [Running as a Scheduled Task](#running-as-a-scheduled-task)
- [Permissions and authentication](#permissions-and-authentication)
- [Connecting through SSL / restricted WinRM](#connecting-through-ssl--restricted-winrm)
- [What gets checked](#what-gets-checked)
- [Troubleshooting](#troubleshooting)
- [Version history](#version-history)

## Requirements

- Windows PowerShell 5.1 (Exchange Management Shell environment)
- Exchange Server 2016 or later (tested against Exchange 2016; the
  ContentIndexState field, which was removed from database copy status
  in Exchange 2019, is not used)
- The Exchange Management Shell snapin
  (`Microsoft.Exchange.Management.PowerShell.SnapIn`) available on the
  machine the script runs on
- An account with at least read access to the environment (Exchange RBAC
  role such as `View-Only Organization Management`, plus local access to the
  target servers for CIM/service queries) - see
  [Permissions and authentication](#permissions-and-authentication)
- `ScheduledTasks` PowerShell module (built into Windows) if you use
  `-RegisterTask`

The script does not manage or store any credentials for the report run
itself. It always runs in the security context of the account that starts
it (interactive user, Scheduled Task account, or `NT AUTHORITY\SYSTEM`).

## Quick start

```powershell
# 1. Generate a starting configuration file
.\ExchangeReport.ps1 -GenerateSampleConfig

# 2. Copy the sample to config.json and fill in the values for your environment
Copy-Item .\config.sample.json .\config.json
notepad .\config.json

# 3. Run the report once, interactively, to verify it works
.\ExchangeReport.ps1

# 4. Register it as a daily Scheduled Task
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00"
```

## Configuration reference

All environment specific settings live in a JSON file, by default
`config.json` next to the script (override with `-ConfigPath`). Run
`.\ExchangeReport.ps1 -GenerateSampleConfig` to create
`config.sample.json` with all fields and inline explanations printed to the
console; copy it to `config.json` and adjust.

`EnvironmentName`, `SmtpServer`, `MailFrom` and `MailTo` are required. Every
other field has a default and can be omitted from the file.

### General

| Field | Type | Default | Description |
|---|---|---|---|
| `EnvironmentName` | string | *(required)* | Free text label, used as the report title and mail subject, for example `"Contoso Production"`. |
| `ServerNamePattern` | string | `""` | Wildcard for `Get-ExchangeServer`, for example `"EXCH*"`. Leave empty to auto discover all Exchange servers. |
| `DagName` | string | `""` | Name of the Database Availability Group to check. Leave empty to auto discover it. If more than one DAG is found, the first one is used and a warning is logged. |
| `ExpectedPamServer` | string | `""` | Server name expected to be the Primary Active Manager. Leave empty to skip this check (the current PAM is still shown in the report). |
| `SmtpServer` | string | *(required)* | SMTP relay used to send the report mail. |
| `MailFrom` | string | *(required)* | Sender address of the report mail. |
| `MailTo` | array of strings | *(required)* | One or more recipient addresses. |

### Drives, backups, logs

| Field | Type | Default | Description |
|---|---|---|---|
| `DriveFreePercentWarning` | number (0-100) | `12` | Free space percentage below which a drive is flagged. |
| `BackupMaxAgeDays` | number | `1` | Maximum allowed age, in days, of a database's last full backup. |
| `LogDaysToKeep` | number | `30` | Days to keep old script log files before automatic cleanup. |
| `LogRootPath` | string | `"logs"` | Folder for log files. Relative paths are resolved against the script's own folder. |

### Saved HTML report copy

| Field | Type | Default | Description |
|---|---|---|---|
| `SaveHtmlReport` | bool | `true` | If true, a copy of the HTML report is saved to disk in addition to being mailed. |
| `HtmlReportPath` | string | `"Reports"` | Folder for saved reports. Relative paths are resolved against the script's own folder. |
| `HtmlReportDaysToKeep` | number | `30` | Days to keep saved HTML reports before automatic cleanup (independent of `LogDaysToKeep`). |

### CIM connection (drives and services)

| Field | Type | Default | Description |
|---|---|---|---|
| `CimConnectionMode` | `"Default"` or `"SSL"` | `"Default"` | How the script connects to each Exchange server for drive and service checks. `"Default"` uses plain `Get-CimInstance -ComputerName` (classic WinRM). `"SSL"` opens a CIM session over HTTPS - use this where plain WinRM CIM access is restricted. |
| `CimSkipCaCheck` | bool | `true` | Only relevant for `"SSL"`. Skip CA trust validation of the server certificate. |
| `CimSkipCnCheck` | bool | `true` | Only relevant for `"SSL"`. Skip common name validation of the server certificate. |
| `CimSkipRevocationCheck` | bool | `true` | Only relevant for `"SSL"`. Skip certificate revocation checking. |

See [Connecting through SSL / restricted WinRM](#connecting-through-ssl--restricted-winrm)
for details.

### Message queue check

| Field | Type | Default | Description |
|---|---|---|---|
| `EnableQueueCheck` | bool | `true` | Enable or disable this check entirely. |
| `QueueLengthWarning` | number | `100` | Message count above which a queue is flagged. |
| `PoisonQueueAlwaysWarn` | bool | `true` | If true, any message in the poison queue is always flagged, regardless of `QueueLengthWarning`. If false, the poison queue is only flagged once it also exceeds `QueueLengthWarning`. |

### Certificate check

| Field | Type | Default | Description |
|---|---|---|---|
| `EnableCertificateCheck` | bool | `true` | Enable or disable this check entirely. |
| `CertExpiryWarningDays` | number | `30` | Days before expiry at which a certificate is flagged. Already expired certificates are always flagged as critical. Only certificates actually bound to an Exchange service (`Services` not `None`) are checked - certificates sitting unused in the store are ignored. |

### Service check

| Field | Type | Default | Description |
|---|---|---|---|
| `EnableServiceCheck` | bool | `true` | Enable or disable this check entirely. By default, checks every `MSExchange*` service with start type Automatic and flags any that is not running. |
| `ServiceCheckExclude` | array of strings | `[]` | Service names to ignore, even if they would otherwise be checked. Takes precedence over `ServiceCheckInclude`. |
| `ServiceCheckInclude` | array of strings | `[]` | Additional service names to check, even if they do not match `MSExchange*` or are not set to Automatic start. |

### Replication check

| Field | Type | Default | Description |
|---|---|---|---|
| `EnableReplicationCheck` | bool | `true` | Enable or disable replication queue length warnings. The database copy status table itself is always shown regardless of this setting. |
| `CopyQueueLengthWarning` | number | `5` | `CopyQueueLength` above which a database copy is flagged. |
| `ReplayQueueLengthWarning` | number | `5` | `ReplayQueueLength` above which a database copy is flagged. |

### Example

```json
{
  "EnvironmentName": "Contoso Production",
  "ServerNamePattern": "",
  "DagName": "",
  "ExpectedPamServer": "",
  "SmtpServer": "smtp.contoso.local",
  "MailFrom": "exchangereport@contoso.local",
  "MailTo": ["exchange-admins@contoso.local"],

  "DriveFreePercentWarning": 12,
  "BackupMaxAgeDays": 1,
  "LogDaysToKeep": 30,
  "LogRootPath": "logs",

  "CimConnectionMode": "Default",
  "CimSkipCaCheck": true,
  "CimSkipCnCheck": true,
  "CimSkipRevocationCheck": true,

  "SaveHtmlReport": true,
  "HtmlReportPath": "Reports",
  "HtmlReportDaysToKeep": 30,

  "EnableQueueCheck": true,
  "QueueLengthWarning": 100,
  "PoisonQueueAlwaysWarn": true,

  "EnableCertificateCheck": true,
  "CertExpiryWarningDays": 30,

  "EnableServiceCheck": true,
  "ServiceCheckExclude": [],
  "ServiceCheckInclude": [],

  "EnableReplicationCheck": true,
  "CopyQueueLengthWarning": 5,
  "ReplayQueueLengthWarning": 5
}
```

All config values are validated before any Exchange access happens
(email address format, numeric ranges, writable log/report paths). If
several values are wrong, all problems are reported together instead of
stopping at the first one.

## Command line reference

| Parameter | Description |
|---|---|
| `-ConfigPath <path>` | Path to the JSON config file. Default: `config.json` next to the script. |
| `-GenerateSampleConfig` | Writes a sample config file and exits. Combine with `-SampleConfigPath` to change the target file. |
| `-SampleConfigPath <path>` | Target path for `-GenerateSampleConfig`. Default: `config.sample.json` next to the script. |
| `-RegisterTask` | Registers the script as a Windows Scheduled Task and exits. See [Running as a Scheduled Task](#running-as-a-scheduled-task). |
| `-TaskInterval Daily\|Weekly` | Schedule type for `-RegisterTask`. Default: `Daily`. |
| `-TaskTime <"HH:mm"[]>` | One or more times of day, for example `"06:00"` or `"06:00","14:00","20:00"` to run several times a day. Default: `"06:00"`. |
| `-TaskDayOfWeek <day>` | Day of week for a `Weekly` schedule. Default: `Monday`. Ignored for `Daily`. |
| `-TaskName <name>` | Name of the Scheduled Task. Default: `ExchangeReport`. |
| `-TaskCredential <PSCredential>` | Account the task should run as, supplied as a credential object instead of an interactive prompt. Cannot be combined with `-RunAsSystem`. |
| `-RunAsSystem` | Registers the task to run as `NT AUTHORITY\SYSTEM` instead of a named account. Cannot be combined with `-TaskCredential`. See [Permissions and authentication](#permissions-and-authentication). |
| `-EnableDebugTranscript` | Starts a PowerShell transcript for the run, saved under the configured log folder. For troubleshooting only, off by default. |

Running the script with no switches performs a normal report run using
`config.json`.

## Running as a Scheduled Task

```powershell
# Once a day at 06:00, prompting for the account to run as
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00"

# Three times a day
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00","14:00","20:00"

# Weekly, every Monday at 07:30
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Weekly -TaskDayOfWeek Monday -TaskTime "07:30"

# Non-interactive, with a pre-built credential
$cred = Get-Credential
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00" -TaskCredential $cred

# Running as NT AUTHORITY\SYSTEM (see Permissions and authentication)
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00" -RunAsSystem
```

The registered task calls `powershell.exe -NoProfile -ExecutionPolicy Bypass
-File "<script path>" -ConfigPath "<config path>"`, so it always uses the
config file path that was active at registration time. Registering again
with the same `-TaskName` overwrites the existing task.

The script itself does not store or manage the Scheduled Task account's
credentials; Windows Task Scheduler handles that.

## Permissions and authentication

The account running the report (interactive user, Scheduled Task account, or
`NT AUTHORITY\SYSTEM`) needs:

- An Exchange RBAC role with read access, for example
  `View-Only Organization Management`
- The ability to reach the Exchange servers over CIM/WinRM (or WinRM over
  SSL, see below) for drive and service checks

### "Double hop" failures for cross-server calls

If the script runs on a separate admin/management server (not on an
Exchange server itself) and connects to Exchange through a remote
PowerShell session, some cmdlets that themselves reach out to a *different*
server internally - notably `Get-MailboxStatistics` against a database
mounted on another Mailbox server - can fail with an error such as:

```
Exchange Information Store on server 'mbx02.contoso.local' is inaccessible.
Make sure that the network is connected and that the Exchange Information
Store is running.
```

This is a classic Kerberos "double hop" problem: the account's credentials
are used for the first hop (admin server to Exchange server) but are not
delegated for the second hop (Exchange server to the target Mailbox
server's Information Store). Simpler cmdlets that only need a single hop
(`Get-ExchangeServer`, `Get-DatabaseAvailabilityGroup`, and so on) keep
working, which is a good sign this is the cause.

Ways to resolve it, roughly in order of how commonly they are used:

1. **Run the script directly on an Exchange server.** Exchange servers
   already trust each other for the necessary Kerberos delegation through
   their computer accounts (part of standard Exchange setup). Combine this
   with `-RunAsSystem` when registering the Scheduled Task: a task running
   as `NT AUTHORITY\SYSTEM` on an Exchange server authenticates as that
   server's computer account, which is already part of the trusted delegation
   path - this is usually the simplest fix and avoids managing a password
   for a dedicated service account.
2. **Set up Kerberos Constrained Delegation** for a dedicated service
   account, allowing it to delegate to the Exchange (Mailbox) servers. More
   setup effort, but keeps the account's privileges narrower than
   `NT AUTHORITY\SYSTEM`.
3. **Enable CredSSP** between the admin server and the Exchange servers.
   Works, but sends credentials in a way that is generally considered less
   clean than Kerberos delegation, so weigh this against your security
   requirements.

## Connecting through SSL / restricted WinRM

Some environments restrict plain WinRM CIM access. Set
`CimConnectionMode` to `"SSL"` in the config to have the script open a CIM
session over HTTPS for drive and service checks instead, equivalent to:

```powershell
$o = New-CimSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -UseSsl
$s = New-CimSession -ComputerName $server.Fqdn -SessionOption $o
Get-CimInstance -CimSession $s -ClassName Win32_Volume
```

The three `CimSkip*CheckCheck` config values map directly to the
`New-CimSessionOption` switches of the same purpose, and can be set to
`false` individually if your environment has valid, trusted certificates
and you don't want to skip those checks. One CIM connection is opened per
server and reused for both the drive and the service check, then closed.

`CimConnectionMode` only affects drive and service checks. Message queues,
certificates, mailbox/database queries, and the health report use the
Exchange Management Shell's own cmdlets and transport, and are not affected
by this setting.

## What gets checked

| Area | Cmdlet(s) | Notes |
|---|---|---|
| Mailbox counts | `Get-ADUser` | User, shared and resource mailboxes homed on the discovered servers. |
| Databases | `Get-MailboxDatabase`, `Get-MailboxStatistics` | Flags databases not mounted on their preferred server, or with a missing/too old full backup. |
| Database copies | `Get-MailboxDatabaseCopyStatus` | Flags copies with a status other than Healthy/Mounted, or with `CopyQueueLength`/`ReplayQueueLength` above their thresholds. |
| Primary Active Manager | `Get-DatabaseAvailabilityGroup` | Flags a mismatch against `ExpectedPamServer`, if configured. |
| Drives | `Get-CimInstance Win32_Volume` | Flags drives below `DriveFreePercentWarning` free space. |
| Message queues | `Get-Queue` | Flags queues above `QueueLengthWarning`; the poison queue has its own always-warn rule. |
| Certificates | `Get-ExchangeCertificate` | Only certificates actually bound to a service; flags expired or soon-to-expire certificates. |
| Services | `Get-CimInstance Win32_Service` | Flags `MSExchange*` services set to Automatic start that are not running, plus any explicitly included services. |
| Server health | `Get-HealthReport` | Any managed health set not reporting Healthy. |

Every warning table in the report includes an `Issue` column with a plain
text explanation of why that row was flagged.

If the script aborts before it can finish (for example because the Exchange
shell could not be loaded, or config validation failed), it attempts to send
a short emergency mail describing the failure, using the same SMTP settings
as the regular report.

## Troubleshooting

- **`Join-Path : Cannot bind argument to parameter 'Path' because it is an
  empty string`** at script start: this was a startup issue with how
  `$PSScriptRoot` is evaluated in parameter defaults, fixed in v4.4 and
  later. Make sure you are running the current version of the script.
- **Report is missing database information, log shows
  `MailboxStatistics for database ... failed: ... Information Store on
  server '...' is inaccessible`**: see
  [Permissions and authentication](#permissions-and-authentication) above -
  this is a Kerberos double hop issue, not a script bug.
- **SMTP warnings in the log but the mail still arrives**: the SMTP
  reachability check is intentionally a soft check (logged only) since a
  blocked test connection does not always mean the real send will fail.
- Use `-EnableDebugTranscript` for a full PowerShell transcript of a run
  when diagnosing an issue; it is saved under the configured `LogRootPath`.

## Version history

See the comment-based help at the top of `ExchangeReport.ps1`
(`Get-Help .\ExchangeReport.ps1 -Full`) for the detailed, per-version
change log. Summary:

| Version | Highlights |
|---|---|
| 4.5 | Multiple `-TaskTime` values per day, `-RunAsSystem` for Scheduled Tasks |
| 4.4 | Fixed `$PSScriptRoot` empty-string startup error under `-File` invocation |
| 4.3 | `-TaskCredential` for non-interactive Scheduled Task registration |
| 4.2 | `CimConnectionMode` (SSL CIM sessions), FQDN based remote calls |
| 4.1 | `ServiceCheckInclude` |
| 4.0 | Config validation, warning "Issue" text, queue/certificate/service/replication checks, saved HTML report copy, removed ContentIndexState |
| 3.0 | External JSON config file, `-GenerateSampleConfig`, `-RegisterTask`, auto discovery of servers/DAG |
| 2.0 | Removed credential handling, CIM instead of WMI, pre-flight Exchange shell check, various bug fixes, new HTML report layout |
| 1.4 | Original script |
