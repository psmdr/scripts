# Get-ProtocolLogonStats.ps1

Analyzes Exchange on-premises IMAP4 and/or POP3 protocol logs across one or more servers and
aggregates unique **Server + Protocol + IP + User** combinations, together with an access
count per combination. Optionally also produces a consolidated **User + access count** view
per protocol, across all servers.

Rewrite of an earlier single-server, single-protocol script; see [History](#history) below
for what changed.

## Requirements

- PowerShell 5.1 or later (fully 5.1-compatible, no PowerShell 7-only syntax)
- Network/registry access to the target Exchange servers for automatic log path resolution
  (see [Log Path Resolution](#log-path-resolution)), unless `-LogPath` or `-ServerLogPath`
  is used instead
- Optional: a loaded Exchange Management Shell for the most accurate log path resolution and
  for `-Server (Get-ExchangeServer)`

## What It Does

1. Determines the log directory for each requested server and protocol (see
   [Log Path Resolution](#log-path-resolution)).
2. Selects log files from that directory:
   - Only files within the last `-Days` days (based on `LastWriteTime`)
   - **Frontend logs only by default** (`IMAP4*.LOG` / `POP3*.LOG`, excluding files starting
     with `IMAP4BE` / `POP3BE`); use `-IncludeBackend` to also process Backend logs
3. Parses each log file line by line:
   - Column positions for IP and User are detected dynamically from the file's `#Fields:`
     header (see [Field Detection Caveat](#field-detection-caveat))
   - Applies default and custom exclusions (see [Default Exclusions](#default-exclusions))
   - Aggregates matching lines into unique Server+Protocol+(Role+)IP+User combinations with
     an access count, using an in-memory dictionary (fast, no repeated array growth)
4. Writes one CSV file per protocol (IMAP and/or POP), and optionally a second, consolidated
   User-summary CSV per protocol (see `-IncludeUserSummary`).
5. Prints progress (server X of Y, file i of n) and a final summary (files processed, lines
   read/parsed, errors) to the console.

## Log Path Resolution

For each server/protocol combination, the log path is resolved in this order:

1. **`-ServerLogPath`** override, if the server is listed in the hashtable
2. **Exchange Management Shell** (`Get-ImapSettings` / `Get-PopSettings`), if the cmdlets are
   loaded in the current session — gives the actually configured path
3. **Remote registry fallback** — reads the Exchange install path (`MsiInstallPath`) from
   `HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup` (Exchange 2013/2016/2019) or `\v14\Setup`
   (Exchange 2010) on the target server, then appends the standard log subfolder
   (`Logging\Imap4` / `Logging\Pop3`)

If none of the three succeeds, the server/protocol combination is skipped with a warning; the
run continues for all other servers/protocols. Skipped combinations are listed again in the
summary at the end.

## Default Exclusions

To keep the results focused on real client logons, a few exclusions are applied by default.
Each can be switched off individually:

| Exclusion | Default | Switch to disable | Additional custom values |
|---|---|---|---|
| IP `127.0.0.1` | On | `-IncludeLoopback` | `-ExcludeIP <string[]>` (exact match) |
| User `HealthMailbox*` | On | `-IncludeHealthMailbox` | `-ExcludeUser <string[]>` (wildcard match) |
| Log lines without a user value | Always dropped | *(not configurable)* | — |

Custom `-ExcludeIP` / `-ExcludeUser` values are applied **in addition to** the defaults, not
instead of them — use the `-Include...` switches to turn off a specific default.

## Frontend vs. Backend Logs

On each server, IMAP4/POP3 Frontend and Backend services write their logs into the same
directory, distinguished only by filename:

| Protocol | Frontend | Backend |
|---|---|---|
| IMAP | `IMAP4<date>-<n>.LOG` | `IMAP4BE<date>-<n>.LOG` |
| POP | `POP3<date>-<n>.LOG` | `POP3BE<date>-<n>.LOG` |

By default, only **Frontend** logs are processed. Pass `-IncludeBackend` to also include
Backend logs — in that case, the result and CSV output gain an extra `Role` column
(`Frontend`/`Backend`) so both can be told apart or filtered afterwards. Without
`-IncludeBackend`, the `Role` column is omitted entirely (it would always read `Frontend`).

## Field Detection Caveat

The IP and User column positions are determined by matching field names in each log file's
`#Fields:` header (e.g. names containing `remote`/`source` + `ip`/`endpoint` for the IP
column, and `user` for the User column). Exchange protocol log schemas can vary slightly
between versions. If no matching field name is found, the script falls back to the original
fixed column indices (4 = IP, 5 = User) and logs a warning.

**Recommendation:** before relying on the results for reporting purposes, verify the detected
columns against a sample log file in your environment.

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Server` | `string[]` / objects | — | One or more server names, and/or objects such as `Get-ExchangeServer` results. Required unless `-LogPath` is used. |
| `-LogPath` | `string` | — | A single, manually specified log directory instead of automatic per-server resolution. |
| `-ServerLogPath` | `hashtable` | — | Per-server path overrides, e.g. `@{ "EX01" = "\\EX01\Logs\Imap4" }`. |
| `-IMAP` | `switch` | — | Process IMAP4 logs. Combinable with `-POP`. |
| `-POP` | `switch` | — | Process POP3 logs. Combinable with `-IMAP`. |
| `-ExcludeIP` | `string[]` | — | Additional exact-match IP exclusions. |
| `-IncludeLoopback` | `switch` | Off | Disables the default `127.0.0.1` exclusion. |
| `-ExcludeUser` | `string[]` | — | Additional wildcard user exclusions (e.g. `"svc-*"`). |
| `-IncludeHealthMailbox` | `switch` | Off | Disables the default `HealthMailbox*` exclusion. |
| `-IncludeBackend` | `switch` | Off | Also processes Backend logs; adds a `Role` column. |
| `-IncludeUserSummary` | `switch` | Off | Also writes a consolidated per-protocol User+Count CSV. See [User Summary](#user-summary). |
| `-Days` | `int` | `30` | How many days back to look, based on file `LastWriteTime`. |
| `-OutputPath` | `string` | `.` | Directory for the resulting CSV file(s). |
| `-PassThru` | `switch` | Off | Also returns the result objects to the pipeline. |

At least one of `-IMAP` / `-POP`, and either `-Server` or `-LogPath`, must be specified.

## Output

For each processed protocol, one detail CSV is written:

```
ProtocolLogonStats_<Protocol>_<yyyyMMdd_HHmmss>.csv
```

Columns: `Server, Protocol, [Role,] IP, User, Count` (`Role` only present with
`-IncludeBackend`). UTF-8 with BOM.

### User Summary

With `-IncludeUserSummary`, an additional CSV is written per protocol:

```
ProtocolLogonStats_UserSummary_<Protocol>_<yyyyMMdd_HHmmss>.csv
```

This is a pure post-aggregation of the detail results — grouped by `Protocol` + `User` only
(no `Server`/`IP`/`Role`), with `Count` summed across all servers (and Frontend+Backend, if
`-IncludeBackend` was used). Sorted by `Count` descending. It does not change how the log
files themselves are parsed.

## Examples

```powershell
# IMAP and POP, last 14 days, two servers, output to C:\Reports
.\Get-ProtocolLogonStats.ps1 -Server EX01,EX02 -IMAP -POP -Days 14 -OutputPath C:\Reports

# Exclude two additional IP addresses
.\Get-ProtocolLogonStats.ps1 -Server EX01 -IMAP -ExcludeIP "10.0.0.5","10.0.0.6"

# Manual path override for one server
.\Get-ProtocolLogonStats.ps1 -Server EX01 -POP -ServerLogPath @{ "EX01" = "\\EX01\Logs\Pop3" }

# Manual/local log folder, also return objects to the pipeline
.\Get-ProtocolLogonStats.ps1 -LogPath "D:\Exports\Imap4" -IMAP -PassThru

# All servers known to the loaded Exchange Management Shell
.\Get-ProtocolLogonStats.ps1 -Server (Get-ExchangeServer) -IMAP -POP

# Include Backend logs (adds a Role column)
.\Get-ProtocolLogonStats.ps1 -Server EX01 -IMAP -IncludeBackend

# Additional service-account exclusion, but keep loopback entries
.\Get-ProtocolLogonStats.ps1 -Server EX01 -IMAP -ExcludeUser "svc-*" -IncludeLoopback

# Also produce the consolidated per-user summary CSVs
.\Get-ProtocolLogonStats.ps1 -Server EX01,EX02 -IMAP -POP -IncludeUserSummary
```

## Converting the CSV Output to Excel

The CSV output files can be combined into a single, formatted Excel workbook (one worksheet
per file) using the [`ImportExcel`](https://github.com/dfinke/ImportExcel) module:

```powershell
Install-Module ImportExcel -Scope CurrentUser
```

```powershell
$folder    = "C:\Reports"                              # adjust to where your CSV files are
$excelPath = Join-Path $folder "ProtocolLogonStats.xlsx"

if (Test-Path $excelPath) { Remove-Item $excelPath }    # start clean

$sheets = [ordered]@{
    "IMAP"             = "ProtocolLogonStats_IMAP_*.csv"
    "IMAP_UserSummary" = "ProtocolLogonStats_UserSummary_IMAP_*.csv"
    "POP"              = "ProtocolLogonStats_POP_*.csv"
    "POP_UserSummary"  = "ProtocolLogonStats_UserSummary_POP_*.csv"
}

foreach ($sheetName in $sheets.Keys) {
    $file = Get-ChildItem -Path $folder -Filter $sheets[$sheetName] -File |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $file) {
        Write-Warning "No file found for pattern '$($sheets[$sheetName])' - skipping sheet '$sheetName'."
        continue
    }

    Import-Csv -Path $file.FullName |
        Export-Excel -Path $excelPath -WorksheetName $sheetName `
            -TableName $sheetName -TableStyle Medium7 -AutoSize -FreezeTopRow -BoldTopRow `
            -NoNumberConversion IP
}

Write-Host "Done: $excelPath"
```

Notes:
- `-TableName` + `-TableStyle Medium7` formats each sheet as a proper Excel table (which
  includes the header autofilter — no separate `-AutoFilter` switch needed, and it would
  conflict with `-TableName` anyway).
- `-NoNumberConversion IP` is required because `ImportExcel` otherwise tries to interpret
  IP-looking values as numbers (locale-dependent, e.g. under a German locale `10.0.0.5` would
  otherwise be misread as a number with `.` as a thousands separator and lose its dots). The
  parameter is silently ignored on the two UserSummary sheets, which have no `IP` column.

## History

- **Original version** (Max Droege): single-protocol, single-server, fixed column indices,
  a planned IP exclusion list that was never actually implemented, `+=`-based array growth
  (O(n²) for large result sets), ASCII output.
- **Rewrite**:
  - Combinable `-IMAP` / `-POP` switches, multiple servers per run
  - `-Server` accepts both plain names and `Get-ExchangeServer`-style objects
  - Dynamic field-header parsing instead of fixed column indices, with a documented fallback
  - Dictionary-based aggregation with access counts (fixes both the missing exclusion logic
    and the O(n²) growth issue)
  - Working `-ExcludeIP` (exact match) and `-ExcludeUser` (wildcard match)
  - Default exclusions for loopback IP and `HealthMailbox*` users, each individually
    overridable; lines without a user are always dropped
  - Frontend-only log selection by default, with optional `-IncludeBackend` (adds a `Role`
    column)
  - Optional `-IncludeUserSummary` for a consolidated per-protocol User+Count view
  - Layered log-path resolution (override → Exchange Shell → registry fallback)
  - Per-server/per-file error handling that does not abort the whole run; skipped
    combinations are reported in the final summary
  - Per-protocol CSV export, UTF-8 with BOM
  - Console progress output (server X of Y, file i of n) so long runs are traceable
