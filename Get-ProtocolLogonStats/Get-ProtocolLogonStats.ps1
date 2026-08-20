#Requires -Version 5.1
<#
.SYNOPSIS
Get-ProtocolLogonStats.ps1 - Analyzes Exchange IMAP4 / POP3 protocol logs for unique IP/user
logon combinations across one or more servers.

.DESCRIPTION
Parses Exchange on-premises IMAP4 and/or POP3 protocol log files (CSV-style logs with a
"#Fields:" header line) and aggregates unique combinations of Server + Protocol + IP + User,
together with an access count per combination. Results are exported to one CSV file per
protocol (IMAP and/or POP), covering all requested servers in that single file.

Log paths are resolved per server using the following priority:
  1. Explicit override via -ServerLogPath
  2. Exchange Management Shell cmdlets (Get-ImapSettings / Get-PopSettings), if loaded
  3. Remote registry lookup of the Exchange install path (fallback, standard log subfolder)

Only log files whose LastWriteTime falls within the last -Days days are processed. Field
positions (source IP, user) are determined dynamically from each file's "#Fields:" header
where possible, with a fixed-index fallback if no matching field name is found.

By default, only Frontend protocol logs are processed (IMAP4*.LOG / POP3*.LOG, excluding
files starting with IMAP4BE / POP3BE). A handful of default exclusions are applied to keep
the results focused on real client logons; each can be switched off individually:
  - IP 127.0.0.1 is excluded (see -IncludeLoopback)
  - Users matching "HealthMailbox*" are excluded (see -IncludeHealthMailbox, -ExcludeUser)
  - Log lines without a user value are always dropped (not configurable)

.PARAMETER Server
One or more Exchange servers to process. Required unless -LogPath is used instead. Accepts
plain server name strings, and/or server objects such as those returned by
Get-ExchangeServer (e.g. -Server (Get-ExchangeServer)). Object entries are resolved to a
name automatically (Name, falling back to Fqdn).

.PARAMETER LogPath
A single, manually specified log directory to use instead of automatic per-server path
resolution. Useful for local testing or non-standard setups. Mutually usable alongside
-Server purely as a label for the output (Server column).

.PARAMETER ServerLogPath
Optional hashtable of per-server path overrides, e.g. @{ "EX01" = "\\EX01\Logs\Imap4" }.
Takes precedence over Exchange Shell / registry auto-detection for the listed servers.

.PARAMETER IMAP
Switch. Processes IMAP4 protocol logs. Can be combined with -POP.

.PARAMETER POP
Switch. Processes POP3 protocol logs. Can be combined with -IMAP.

.PARAMETER ExcludeIP
One or more IP addresses to exclude from the results (exact match). Applied in addition to
the default 127.0.0.1 exclusion (see -IncludeLoopback).

.PARAMETER IncludeLoopback
Switch. Disables the default exclusion of 127.0.0.1, so loopback entries are included too.

.PARAMETER ExcludeUser
One or more user name patterns to exclude from the results (wildcard match, e.g. "svc-*").
Applied in addition to the default "HealthMailbox*" exclusion (see -IncludeHealthMailbox).

.PARAMETER IncludeHealthMailbox
Switch. Disables the default exclusion of users matching "HealthMailbox*".

.PARAMETER IncludeBackend
Switch. Also processes Backend protocol logs (IMAP4BE*.LOG / POP3BE*.LOG), in addition to
the Frontend logs that are always processed. When set, the result and CSV output gain a
"Role" column (Frontend/Backend) so both can be distinguished or filtered afterwards.

.PARAMETER IncludeUserSummary
Switch. In addition to the regular per-protocol detail CSV (Server/Protocol/IP/User/Count),
also writes a second, consolidated CSV per protocol containing just Protocol, User, and the
summed Count across all servers (and Frontend+Backend, if -IncludeBackend is set) - i.e. the
IP and Server columns are dropped and counts for the same user are summed up. Sorted by
Count descending. This is a pure post-aggregation over the existing detail results; it does
not change how the log files themselves are parsed.

.PARAMETER Days
Number of days to look back when selecting log files, based on LastWriteTime. Default: 30.

.PARAMETER OutputPath
Directory where the resulting CSV file(s) are written. Default: current directory.

.PARAMETER PassThru
Switch. In addition to writing the CSV file(s), also returns the result objects to the
pipeline (e.g. for -OutVariable, Format-Table, or further processing).

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -Server EX01,EX02 -IMAP -POP -Days 14 -OutputPath C:\Reports
Analyzes IMAP and POP logs from the last 14 days on EX01 and EX02, writes two CSV files
(one per protocol) into C:\Reports.

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -Server EX01 -IMAP -ExcludeIP "10.0.0.5","10.0.0.6"
Analyzes IMAP logs on EX01, excluding two known IP addresses from the result.

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -Server EX01 -POP -ServerLogPath @{ "EX01" = "\\EX01\Logs\Pop3" }
Analyzes POP logs on EX01 using a manually specified UNC path instead of auto-detection.

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -LogPath "D:\Exports\Imap4" -IMAP -PassThru
Analyzes a local/manual log folder and also returns the result objects to the pipeline.

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -Server (Get-ExchangeServer) -IMAP -POP
Analyzes IMAP and POP logs on all Exchange servers returned by Get-ExchangeServer
(requires the Exchange Management Shell to be loaded).

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -Server EX01 -IMAP -IncludeBackend
Analyzes both Frontend and Backend IMAP logs on EX01; the output includes a Role column.

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -Server EX01 -IMAP -ExcludeUser "svc-*" -IncludeLoopback
Analyzes IMAP logs on EX01, additionally excluding a service-account naming pattern, while
keeping 127.0.0.1 entries (which are excluded by default).

.EXAMPLE
.\Get-ProtocolLogonStats.ps1 -Server EX01,EX02 -IMAP -POP -IncludeUserSummary
In addition to the two detail CSVs (IMAP/POP), also writes two consolidated "who accessed
how often, across all servers" CSVs (Protocol, User, Count), sorted by Count descending.

.NOTES
History:
- Original version by Max Droege: single-protocol, single-server, fixed column indices,
  manual IP exclusion list never implemented, O(n^2) array growth, ASCII output.
- Rewrite: combinable -IMAP/-POP switches, multiple servers, dynamic field-header parsing,
  dictionary-based aggregation with access counts, working -ExcludeIP, per-protocol CSV
  export (UTF-8 with BOM), per-server error handling that does not abort the whole run,
  layered log-path resolution (override / Exchange Shell / registry fallback), -Server
  accepting Get-ExchangeServer objects, default exclusions for loopback IP and
  HealthMailbox users (overridable), lines without a user always dropped, Frontend-only
  log selection by default with optional -IncludeBackend (adds a Role column), optional
  -IncludeUserSummary for a consolidated per-protocol User+Count view (sorted by Count
  descending) as a second CSV, derived from the existing detail results.

IMPORTANT: The IP/User field detection relies on matching field names in each log file's
"#Fields:" header (e.g. names containing "remote"/"source" + "ip"/"endpoint" for the IP,
and "user" for the user name). Exchange protocol log schemas can vary slightly between
versions. If detection fails, the script falls back to the original fixed column indices
(4 = IP, 5 = User) and logs a warning. Verify the resolved column names against a sample
log file in your environment before relying on the results for reporting purposes.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    [object[]]$Server,

    [Parameter(Mandatory = $false)]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [hashtable]$ServerLogPath,

    [switch]$IMAP,
    [switch]$POP,

    [string[]]$ExcludeIP,
    [switch]$IncludeLoopback,

    [string[]]$ExcludeUser,
    [switch]$IncludeHealthMailbox,

    [switch]$IncludeBackend,

    [switch]$IncludeUserSummary,

    [int]$Days = 30,

    [string]$OutputPath = ".",

    [switch]$PassThru
)

#region Helper functions

function Get-UserSummary {
    param([object[]]$DetailResults)

    $summaryDict = [System.Collections.Generic.Dictionary[string, object]]::new()

    foreach ($item in $DetailResults) {
        $key = "$($item.Protocol)|$($item.User)"
        if ($summaryDict.ContainsKey($key)) {
            $summaryDict[$key].Count += $item.Count
        }
        else {
            $summaryDict[$key] = [PSCustomObject]@{
                Protocol = $item.Protocol
                User     = $item.User
                Count    = $item.Count
            }
        }
    }

    return $summaryDict.Values | Sort-Object Count -Descending
}

function Test-UserExcluded {
    param(
        [string]$User,
        [string[]]$Patterns
    )

    if (-not $Patterns) { return $false }

    foreach ($pattern in $Patterns) {
        if ($User -like $pattern) { return $true }
    }
    return $false
}

function Get-ProtocolLogFiles {
    param(
        [string]$Path,
        [ValidateSet("IMAP", "POP")]
        [string]$Protocol,
        [datetime]$StartDate,
        [switch]$IncludeBackend
    )

    $prefix   = if ($Protocol -eq "IMAP") { "IMAP4" } else { "POP3" }
    $bePrefix = "${prefix}BE"

    $candidates = Get-ChildItem -Path $Path -Filter "$prefix*.log" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $StartDate }

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($file in $candidates) {
        $isBackend = $file.Name.ToUpperInvariant().StartsWith($bePrefix.ToUpperInvariant())
        if ($isBackend -and -not $IncludeBackend) { continue }

        $results.Add([PSCustomObject]@{
            File = $file
            Role = if ($isBackend) { "Backend" } else { "Frontend" }
        })
    }

    return $results
}

function Resolve-ServerNames {
    param([object[]]$InputServers)

    $names = New-Object System.Collections.Generic.List[string]

    foreach ($item in $InputServers) {
        if ($null -eq $item) { continue }

        if ($item -is [string]) {
            $names.Add($item)
            continue
        }

        # Typically a Get-ExchangeServer result (or similar object): prefer .Name, then .Fqdn
        $nameProp = $item.PSObject.Properties['Name']
        $fqdnProp = $item.PSObject.Properties['Fqdn']

        if ($nameProp -and $nameProp.Value) {
            $names.Add([string]$nameProp.Value)
        }
        elseif ($fqdnProp -and $fqdnProp.Value) {
            $names.Add([string]$fqdnProp.Value)
        }
        else {
            $names.Add($item.ToString())
        }
    }

    return $names.ToArray()
}

function Test-ExchangeShellAvailable {
    return [bool](Get-Command -Name Get-ImapSettings -ErrorAction SilentlyContinue)
}

function ConvertTo-UncPath {
    param(
        [string]$ServerName,
        [string]$LocalPath
    )

    if ($LocalPath -match '^([A-Za-z]):\\(.*)$') {
        return "\\$ServerName\$($Matches[1])`$\$($Matches[2])"
    }
    return $LocalPath
}

function Get-RemoteExchangeInstallPath {
    param([string]$ServerName)

    # v15 = Exchange 2013/2016/2019, v14 = Exchange 2010
    $regSubPaths = @(
        "SOFTWARE\Microsoft\ExchangeServer\v15\Setup",
        "SOFTWARE\Microsoft\ExchangeServer\v14\Setup"
    )

    $baseKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $ServerName)
    }
    catch {
        return $null
    }

    try {
        foreach ($regSubPath in $regSubPaths) {
            $subKey = $null
            try {
                $subKey = $baseKey.OpenSubKey($regSubPath)
                if ($subKey) {
                    $value = $subKey.GetValue("MsiInstallPath")
                    if ($value) { return $value }
                }
            }
            catch {
                continue
            }
            finally {
                if ($subKey) { $subKey.Close() }
            }
        }
        return $null
    }
    finally {
        $baseKey.Close()
    }
}

function Resolve-ProtocolLogPath {
    param(
        [string]$ServerName,
        [ValidateSet("IMAP", "POP")]
        [string]$Protocol,
        [hashtable]$ServerLogPathOverride
    )

    $result = [PSCustomObject]@{
        Server   = $ServerName
        Protocol = $Protocol
        Path     = $null
        Source   = $null
        Message  = $null
    }

    # 1. Manual per-server override
    if ($ServerLogPathOverride -and $ServerLogPathOverride.ContainsKey($ServerName)) {
        $result.Path   = $ServerLogPathOverride[$ServerName]
        $result.Source = "Override"
        return $result
    }

    # 2. Exchange Management Shell cmdlets, if loaded
    if (Test-ExchangeShellAvailable) {
        try {
            if ($Protocol -eq "IMAP") {
                $settings = Get-ImapSettings -Server $ServerName -ErrorAction Stop
            }
            else {
                $settings = Get-PopSettings -Server $ServerName -ErrorAction Stop
            }

            if ($settings -and $settings.LogFileLocation) {
                $result.Path   = ConvertTo-UncPath -ServerName $ServerName -LocalPath $settings.LogFileLocation
                $result.Source = "ExchangeShell"
                return $result
            }
        }
        catch {
            # Falls through to the registry fallback below
        }
    }

    # 3. Registry fallback (remote), standard log subfolder
    $installPath = Get-RemoteExchangeInstallPath -ServerName $ServerName
    if ($installPath) {
        $subfolder = if ($Protocol -eq "IMAP") { "Logging\Imap4" } else { "Logging\Pop3" }
        $localPath = Join-Path $installPath $subfolder
        $result.Path   = ConvertTo-UncPath -ServerName $ServerName -LocalPath $localPath
        $result.Source = "Registry"
        return $result
    }

    $result.Message = "Could not resolve log path via override, Exchange Shell, or registry."
    return $result
}

function Get-LogFieldMap {
    param([string]$FilePath)

    $fieldLine = Get-Content -Path $FilePath -TotalCount 20 -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^#Fields:\s*(.+)$' } |
        Select-Object -First 1

    if (-not $fieldLine) { return $null }

    $fieldsPart = $fieldLine -replace '^#Fields:\s*', ''
    $fields = $fieldsPart -split ','

    $map = @{}
    for ($i = 0; $i -lt $fields.Count; $i++) {
        $map[$fields[$i].Trim()] = $i
    }
    return $map
}

function Get-ProtocolLogColumns {
    param([hashtable]$FieldMap)

    # Prefer remote/source IP fields over local/destination ones.
    $ipField = $FieldMap.Keys |
        Where-Object { ($_ -match 'remote' -or $_ -match 'source') -and ($_ -match 'ip' -or $_ -match 'endpoint') } |
        Select-Object -First 1

    if (-not $ipField) {
        $ipField = $FieldMap.Keys | Where-Object { $_ -match 'ip' -or $_ -match 'endpoint' } | Select-Object -First 1
    }

    $userField = $FieldMap.Keys | Where-Object { $_ -match 'user' } | Select-Object -First 1

    return [PSCustomObject]@{
        IPIndex       = if ($null -ne $ipField) { $FieldMap[$ipField] } else { 4 }
        UserIndex     = if ($null -ne $userField) { $FieldMap[$userField] } else { 5 }
        IPFieldName   = $ipField
        UserFieldName = $userField
    }
}

function Invoke-ProtocolLogFile {
    param(
        [string]$FilePath,
        [string]$ServerName,
        [string]$Protocol,
        [string]$Role,
        [System.Collections.Generic.Dictionary[string, object]]$ResultDict,
        [System.Collections.Generic.HashSet[string]]$ExcludeIPSet,
        [string[]]$ExcludeUserPatterns
    )

    $stats = [PSCustomObject]@{
        File    = $FilePath
        Lines   = 0
        Parsed  = 0
        Skipped = 0
        Errors  = 0
    }

    $fieldMap = $null
    try {
        $fieldMap = Get-LogFieldMap -FilePath $FilePath
    }
    catch {
        $stats.Errors++
        Write-Warning "Could not read header of $FilePath : $($_.Exception.Message)"
        return $stats
    }

    if (-not $fieldMap) {
        $stats.Skipped++
        Write-Warning "No '#Fields:' header found in $FilePath - file skipped."
        return $stats
    }

    $columns   = Get-ProtocolLogColumns -FieldMap $fieldMap
    $ipIndex   = $columns.IPIndex
    $userIndex = $columns.UserIndex
    $maxIndex  = [Math]::Max($ipIndex, $userIndex)

    $reader = $null
    try {
        $reader = [System.IO.StreamReader]::new($FilePath)

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            $stats.Lines++

            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }

            $fields = $line -split ','
            if ($fields.Count -le $maxIndex) {
                $stats.Skipped++
                continue
            }

            $rawIp = $fields[$ipIndex].Trim()
            # Remote-endpoint style fields can contain "IP:Port"
            $ip   = $rawIp.Split(':')[0]
            $user = $fields[$userIndex].Trim()

            if ([string]::IsNullOrWhiteSpace($ip)) {
                $stats.Skipped++
                continue
            }

            # Lines without a user are never useful for this report - always dropped.
            if ([string]::IsNullOrWhiteSpace($user)) {
                $stats.Skipped++
                continue
            }

            if ($ExcludeIPSet -and $ExcludeIPSet.Contains($ip)) {
                $stats.Skipped++
                continue
            }

            if (Test-UserExcluded -User $user -Patterns $ExcludeUserPatterns) {
                $stats.Skipped++
                continue
            }

            $key = "$ServerName|$Protocol|$Role|$ip|$user"
            if ($ResultDict.ContainsKey($key)) {
                $ResultDict[$key].Count++
            }
            else {
                $ResultDict[$key] = [PSCustomObject]@{
                    Server   = $ServerName
                    Protocol = $Protocol
                    Role     = $Role
                    IP       = $ip
                    User     = $user
                    Count    = 1
                }
            }
            $stats.Parsed++
        }
    }
    catch {
        $stats.Errors++
        Write-Warning "Error while reading $FilePath : $($_.Exception.Message)"
    }
    finally {
        if ($reader) { $reader.Close() }
    }

    return $stats
}

#endregion

#region Validation

if (-not $IMAP -and -not $POP) {
    Write-Error "Please specify at least one of -IMAP and/or -POP."
    return
}

if (-not $Server -and -not $LogPath) {
    Write-Error "Please specify -Server (one or more) or -LogPath."
    return
}

if (-not (Test-Path -Path $OutputPath)) {
    Write-Error "OutputPath '$OutputPath' does not exist."
    return
}

if ($Server) {
    $Server = Resolve-ServerNames -InputServers $Server
}

#endregion

#region Main

$protocols = @()
if ($IMAP) { $protocols += "IMAP" }
if ($POP) { $protocols += "POP" }

$defaultExcludeIP   = @('127.0.0.1')
$defaultExcludeUser = @('HealthMailbox*')

$effectiveExcludeIP = New-Object System.Collections.Generic.List[string]
if (-not $IncludeLoopback) { $effectiveExcludeIP.AddRange([string[]]$defaultExcludeIP) }
if ($ExcludeIP) { $effectiveExcludeIP.AddRange([string[]]$ExcludeIP) }

$excludeSet = $null
if ($effectiveExcludeIP.Count -gt 0) {
    $excludeSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$effectiveExcludeIP)
}

$effectiveExcludeUser = New-Object System.Collections.Generic.List[string]
if (-not $IncludeHealthMailbox) { $effectiveExcludeUser.AddRange([string[]]$defaultExcludeUser) }
if ($ExcludeUser) { $effectiveExcludeUser.AddRange([string[]]$ExcludeUser) }

$startDate        = (Get-Date).AddDays(-$Days)
$overallFileStats = New-Object System.Collections.Generic.List[object]
$pathResolutions  = New-Object System.Collections.Generic.List[object]
$allPassThruItems = New-Object System.Collections.Generic.List[object]

foreach ($protocol in $protocols) {

    $resultDict = [System.Collections.Generic.Dictionary[string, object]]::new()

    if ($LogPath) {
        $serverLabel = if ($Server -and $Server.Count -eq 1) { $Server[0] } else { "Manual" }
        $pathResolutions.Add([PSCustomObject]@{
            Server = $serverLabel; Protocol = $protocol; Path = $LogPath
            Source = "LogPath-Parameter"; Message = $null
        })

        if (-not (Test-Path -Path $LogPath)) {
            Write-Warning "[$serverLabel/$protocol] LogPath not reachable: $LogPath"
        }
        else {
            $fileEntries = Get-ProtocolLogFiles -Path $LogPath -Protocol $protocol -StartDate $startDate -IncludeBackend:$IncludeBackend

            if (-not $fileEntries -or $fileEntries.Count -eq 0) {
                Write-Warning "[$serverLabel/$protocol] No log files found in the selected time range under $LogPath"
            }
            else {
                Write-Host "[$serverLabel/$protocol] $($fileEntries.Count) file(s) to process."
            }

            $fileIndex = 0
            foreach ($entry in $fileEntries) {
                $fileIndex++
                Write-Host "[$serverLabel/$protocol] File $fileIndex of $($fileEntries.Count): $($entry.File.Name)"
                $stat = Invoke-ProtocolLogFile -FilePath $entry.File.FullName -ServerName $serverLabel `
                    -Protocol $protocol -Role $entry.Role -ResultDict $resultDict `
                    -ExcludeIPSet $excludeSet -ExcludeUserPatterns $effectiveExcludeUser
                $overallFileStats.Add($stat)
            }
        }
    }
    else {
        $serverCount = $Server.Count
        $serverIndex = 0

        foreach ($srv in $Server) {
            $serverIndex++
            Write-Host "Server $serverIndex of $serverCount ($protocol): $srv"

            $resolved = Resolve-ProtocolLogPath -ServerName $srv -Protocol $protocol -ServerLogPathOverride $ServerLogPath
            $pathResolutions.Add($resolved)

            if (-not $resolved.Path) {
                Write-Warning "[$srv/$protocol] $($resolved.Message)"
                continue
            }

            if (-not (Test-Path -Path $resolved.Path)) {
                Write-Warning "[$srv/$protocol] Path not reachable: $($resolved.Path) (source: $($resolved.Source))"
                continue
            }

            $fileEntries = Get-ProtocolLogFiles -Path $resolved.Path -Protocol $protocol -StartDate $startDate -IncludeBackend:$IncludeBackend

            if (-not $fileEntries -or $fileEntries.Count -eq 0) {
                Write-Warning "[$srv/$protocol] No log files found in the selected time range under $($resolved.Path)"
                continue
            }

            Write-Host "[$srv/$protocol] $($fileEntries.Count) file(s) to process."

            $fileIndex = 0
            foreach ($entry in $fileEntries) {
                $fileIndex++
                Write-Host "[$srv/$protocol] File $fileIndex of $($fileEntries.Count): $($entry.File.Name)"
                $stat = Invoke-ProtocolLogFile -FilePath $entry.File.FullName -ServerName $srv `
                    -Protocol $protocol -Role $entry.Role -ResultDict $resultDict `
                    -ExcludeIPSet $excludeSet -ExcludeUserPatterns $effectiveExcludeUser
                $overallFileStats.Add($stat)
            }
        }
    }

    $protocolResults = $resultDict.Values | Sort-Object Server, IP, User
    $timestamp       = Get-Date -Format 'yyyyMMdd_HHmmss'

    if ($IncludeUserSummary) {
        $userSummary = Get-UserSummary -DetailResults $resultDict.Values
        $summaryFile = Join-Path $OutputPath "ProtocolLogonStats_UserSummary_${protocol}_${timestamp}.csv"
        $userSummary | Export-Csv -Path $summaryFile -NoTypeInformation -Encoding UTF8

        Write-Host "$protocol : $($userSummary.Count) unique users (consolidated) -> $summaryFile"

        if ($PassThru) {
            foreach ($item in $userSummary) { $allPassThruItems.Add($item) }
        }
    }

    if (-not $IncludeBackend) {
        # Frontend-only run: Role is always "Frontend" for every row, so omit the column.
        $protocolResults = $protocolResults | Select-Object Server, Protocol, IP, User, Count
    }
    else {
        $protocolResults = $protocolResults | Select-Object Server, Protocol, Role, IP, User, Count
    }

    $outFile = Join-Path $OutputPath "ProtocolLogonStats_${protocol}_${timestamp}.csv"
    $protocolResults | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8

    Write-Host "$protocol : $($protocolResults.Count) unique Server/IP/User combinations -> $outFile"

    if ($PassThru) {
        foreach ($item in $protocolResults) { $allPassThruItems.Add($item) }
    }
}

#endregion

#region Summary

$totalFiles  = $overallFileStats.Count
$totalLines  = ($overallFileStats | Measure-Object -Property Lines -Sum).Sum
$totalParsed = ($overallFileStats | Measure-Object -Property Parsed -Sum).Sum
$totalErrors = ($overallFileStats | Measure-Object -Property Errors -Sum).Sum

Write-Host ""
Write-Host "Summary: $totalFiles files processed, $totalLines lines read, $totalParsed lines parsed, $totalErrors errors."

$resolutionIssues = $pathResolutions | Where-Object { -not $_.Path }
if ($resolutionIssues) {
    Write-Host ""
    Write-Warning "The following server/protocol combinations could not be resolved and were skipped:"
    $resolutionIssues | Format-Table Server, Protocol, Message -AutoSize
}

#endregion

if ($PassThru) {
    $allPassThruItems
}
