<#
.SYNOPSIS
Collects information about an Exchange environment and sends an HTML report.

.DESCRIPTION
Checks mailbox distribution, databases, database copy / replication status,
disk space, message queues, certificates and critical services of the
Exchange servers in an environment, and sends a summarized HTML report by
mail. A copy of the HTML report can optionally be saved to disk. Warnings are
highlighted and include a short explanation of why each item was flagged.

The script does not manage or store any credentials for the report run
itself. All remote calls (Get-CimInstance, Get-Service, Exchange cmdlets) run
exclusively in the security context of the account that starts the script
(for example a Scheduled Task).

All environment specific values, thresholds and per-check enable/disable
switches are read from an external JSON config file instead of script
parameters. This makes it easy to reuse the same script file across multiple
environments and to run it from a Scheduled Task without editing the script
itself.

.PARAMETER ConfigPath
Path to the JSON configuration file. Defaults to config.json next to the
script.

.PARAMETER GenerateSampleConfig
Writes a sample configuration file (with placeholder values) and exits. Use
this to create a starting point for a new environment.

.PARAMETER SampleConfigPath
Target path for the sample configuration file created by
-GenerateSampleConfig. Defaults to config.sample.json next to the script.

.PARAMETER RegisterTask
Registers this script as a Windows Scheduled Task and exits. Prompts
interactively for the account credentials the task should run under. Combine
with -TaskInterval, -TaskTime, -TaskDayOfWeek and -TaskName.

.PARAMETER TaskInterval
Schedule type for -RegisterTask: Daily or Weekly.

.PARAMETER TaskTime
One or more times of day the task should run, in 24h "HH:mm" format, for
example "06:00" or "06:00","14:00","20:00" to run several times per day.
Each value creates its own trigger on the Scheduled Task.

.PARAMETER TaskDayOfWeek
Day of week for a Weekly schedule, for example "Monday". Ignored for Daily.

.PARAMETER TaskName
Name of the Scheduled Task to create.

.PARAMETER TaskCredential
Optional PSCredential object for the account the Scheduled Task should run
as. If provided, -RegisterTask uses it directly instead of prompting
interactively with Get-Credential. Useful for non-interactive or scripted
setup, for example from a deployment pipeline. Cannot be combined with
-RunAsSystem.

.PARAMETER RunAsSystem
Registers the Scheduled Task to run as NT AUTHORITY\SYSTEM instead of a named
account, no password needed. This is mainly useful when the script runs
directly on an Exchange server and needs to reach other Exchange servers in
the same organization: the server's computer account is typically already
trusted for the necessary Kerberos delegation, which a plain user or service
account usually is not, so this avoids "double hop" authentication failures
for cross-server calls. Cannot be combined with -TaskCredential.

.PARAMETER EnableDebugTranscript
Starts a PowerShell transcript for the duration of the report run. Intended
for troubleshooting only, disabled by default.

.EXAMPLE
.\ExchangeReport.ps1 -GenerateSampleConfig
Creates config.sample.json next to the script. Copy it to config.json and
fill in the environment specific values.

.EXAMPLE
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00"
Registers a daily Scheduled Task that runs this script at 06:00, prompting for
the account to run it as.

.EXAMPLE
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00","14:00","20:00" -RunAsSystem
Registers a daily Scheduled Task that runs three times a day, as
NT AUTHORITY\SYSTEM (no credential prompt).

.EXAMPLE
$cred = Get-Credential
.\ExchangeReport.ps1 -RegisterTask -TaskInterval Daily -TaskTime "06:00" -TaskCredential $cred
Registers the Scheduled Task using a credential object built beforehand,
without an interactive prompt during registration.

.EXAMPLE
.\ExchangeReport.ps1
Runs the report using config.json next to the script.

.NOTES
 Version 4.6
 Changes in v4.6:
  - Added WarningsOnly: when enabled, the report contains only the warning
    sections (no routine overview tables). If a run finds no warnings, no
    mail is sent (logged instead), and if SaveHtmlReport is enabled a report
    file with a "_NoWarnings" suffix is still saved to disk
  - Added ShowMailboxOverview, ShowDatabaseOverview, ShowDatabaseCopyStatus,
    ShowPrimaryActiveManager and ShowDriveOverview to individually hide those
    report sections, the same way Message Queues/Certificates/Services
    already could be disabled. The underlying data and warning detection are
    unaffected, only the display of the routine overview table is controlled

 Version 4.5
 Changes in v4.5:
  - TaskTime now accepts multiple values (for example "06:00","14:00") so the
    Scheduled Task can run several times a day, one trigger per time
  - Added -RunAsSystem: registers the Scheduled Task to run as
    NT AUTHORITY\SYSTEM instead of a named account. Useful when the script
    runs on an Exchange server itself and needs to reach other Exchange
    servers, since the computer account is typically already trusted for the
    required Kerberos delegation, avoiding double-hop authentication failures
    that a regular user or service account can run into for cross-server
    calls such as Get-MailboxStatistics against a database mounted elsewhere

 Version 4.4
 Changes in v4.4:
  - Fixed a startup error ("Join-Path: Cannot bind argument to parameter
    'Path' because it is an empty string") that could occur when the script
    was started with "powershell.exe -File ..." (for example from a
    Scheduled Task or cmd.exe), because $PSScriptRoot can be empty when used
    directly as a parameter default value depending on how the script was
    invoked. The script's own folder is now resolved explicitly right after
    the Param block, with fallbacks, and used everywhere instead

 Version 4.3
 Changes in v4.3:
  - Added -TaskCredential: -RegisterTask can now take a PSCredential object
    directly instead of always prompting interactively with Get-Credential

 Version 4.2
 Changes in v4.2:
  - Added CimConnectionMode config option ("Default" or "SSL") to support
    environments where plain WinRM CIM access is restricted and an SSL based
    CIM session (with configurable certificate check skips) is required
  - Drive and service checks now share a single CIM connection per server,
    opened once and closed afterwards, instead of connecting twice
  - Service check now uses Win32_Service via CIM instead of
    Get-Service -ComputerName, so it goes through the same connection mode
  - Remote checks (drives, services, queues, certificates, health report) now
    use each server's FQDN instead of its short name. The AD mailbox
    homeserver match still intentionally uses the short name, since that is
    what is stored in msExchHomeServerName

 Version 4.1
 Changes in v4.1:
  - Added ServiceCheckInclude: additional service names that are checked even
    if they do not match MSExchange* or are not set to Automatic start.
    ServiceCheckExclude still takes precedence if a name appears in both lists

 Version 4.0
 Changes in v4.0:
  - Added Test-ReportConfig: validates all config values (email format,
    numeric ranges, writable paths) before any Exchange access happens, and
    reports all problems found in a single error instead of stopping at the
    first one
  - SMTP reachability is checked as a soft warning (logged only, does not
    stop the run)
  - Database and database copy warning tables now include an "Issue" column
    that explains in plain text why each row was flagged
  - Removed ContentIndexState (retired since Exchange 2019)
  - Added optional checks, each with its own enable switch and thresholds in
    the config: message queues (with a dedicated poison queue rule),
    certificates actually in use by an Exchange service, critical Exchange
    services, and database copy replication queue length
  - The generated HTML report can optionally be saved to disk (separate
    folder and retention period from the log files)

 Version 3.0
  - Environment settings moved from script parameters into an external JSON
    config file (-ConfigPath)
  - Added -GenerateSampleConfig to create a starting configuration file
  - Added -RegisterTask to register the script as a Scheduled Task
  - Server pattern and DAG name are now optional and auto discovered if not
    set in the config
  - Removed all environment specific example values from the script itself
  - PowerShell transcript is disabled by default, can be enabled with
    -EnableDebugTranscript for troubleshooting
  - Environment name from the config is used as report title and mail subject

 Version 2.0
  - Removed credential handling, script runs in the caller's security context
  - Get-WmiObject replaced with Get-CimInstance
  - Added pre-flight check that the Exchange shell loaded correctly
  - Fixed backup-age warning that compared the wrong variable
  - Fixed log cleanup that never received a valid path
  - Fixed a possible division by zero for zero-capacity volumes
  - Added try/catch/finally around the main logic plus an emergency mail on
    unexpected failure
  - New HTML layout with CSS and highlighted warning rows

 Version 1.4
  - Original script
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$GenerateSampleConfig,

    [Parameter(Mandatory = $false)]
    [string]$SampleConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$RegisterTask,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Daily", "Weekly")]
    [string]$TaskInterval = "Daily",

    [Parameter(Mandatory = $false)]
    [string[]]$TaskTime = @("06:00"),

    [Parameter(Mandatory = $false)]
    [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
    [string]$TaskDayOfWeek = "Monday",

    [Parameter(Mandatory = $false)]
    [string]$TaskName = "ExchangeReport",

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$TaskCredential,

    [Parameter(Mandatory = $false)]
    [switch]$RunAsSystem,

    [Parameter(Mandatory = $false)]
    [switch]$EnableDebugTranscript
)

#region Resolve script location

# $PSScriptRoot can be an empty string when it is used directly as a
# parameter default value, depending on how the script was started (this is
# a known PowerShell quirk, most commonly seen with
# "powershell.exe -File ..." invocations such as a Scheduled Task, even
# though the same script runs fine when started interactively). To avoid
# that, the script's own folder is resolved here explicitly, with fallbacks,
# and $ConfigPath / $SampleConfigPath are filled in afterwards if the caller
# did not supply them.
$scriptRoot = if ($PSScriptRoot) {
    $PSScriptRoot
}
elseif ($PSCommandPath) {
    Split-Path -Path $PSCommandPath -Parent
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
}
else {
    (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path -Path $scriptRoot -ChildPath "config.json"
}
if ([string]::IsNullOrWhiteSpace($SampleConfigPath)) {
    $SampleConfigPath = Join-Path -Path $scriptRoot -ChildPath "config.sample.json"
}

#endregion

#region Sample config generation

Function New-SampleConfig {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $sample = [ordered]@{
        EnvironmentName          = "Exchange Environment Name"
        ServerNamePattern        = ""
        DagName                  = ""
        ExpectedPamServer        = ""
        SmtpServer                = "smtp.example.local"
        MailFrom                  = "exchangereport@example.local"
        MailTo                     = @("admin@example.local")

        DriveFreePercentWarning  = 12
        BackupMaxAgeDays          = 1
        LogDaysToKeep             = 30
        LogRootPath               = "logs"

        CimConnectionMode         = "Default"
        CimSkipCaCheck            = $true
        CimSkipCnCheck            = $true
        CimSkipRevocationCheck   = $true

        SaveHtmlReport            = $true
        HtmlReportPath            = "Reports"
        HtmlReportDaysToKeep     = 30

        WarningsOnly              = $false

        ShowMailboxOverview       = $true
        ShowDatabaseOverview      = $true
        ShowDatabaseCopyStatus   = $true
        ShowPrimaryActiveManager = $true
        ShowDriveOverview         = $true

        EnableQueueCheck          = $true
        QueueLengthWarning        = 100
        PoisonQueueAlwaysWarn    = $true

        EnableCertificateCheck   = $true
        CertExpiryWarningDays    = 30

        EnableServiceCheck        = $true
        ServiceCheckExclude       = @()
        ServiceCheckInclude       = @()

        EnableReplicationCheck   = $true
        CopyQueueLengthWarning   = 5
        ReplayQueueLengthWarning = 5
    }

    $sample | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding utf8

    Write-Host "Sample configuration written to: $Path"
    Write-Host ""
    Write-Host "Notes on the fields:"
    Write-Host " EnvironmentName          Free text label, used in report title and mail subject"
    Write-Host " ServerNamePattern        Optional. Wildcard for Get-ExchangeServer, for example EXCH*"
    Write-Host "                          Leave empty to auto discover all Exchange servers"
    Write-Host " DagName                  Optional. Leave empty to auto discover the DAG"
    Write-Host " ExpectedPamServer        Optional. Leave empty to skip the PAM mismatch check"
    Write-Host " SmtpServer               SMTP relay used to send the report"
    Write-Host " MailFrom                 Sender address of the report mail"
    Write-Host " MailTo                   Array of recipient addresses"
    Write-Host ""
    Write-Host " DriveFreePercentWarning  Free space percentage below which a drive is flagged"
    Write-Host " BackupMaxAgeDays         Maximum allowed age in days of the last full backup"
    Write-Host " LogDaysToKeep            Days to keep old log files before automatic cleanup"
    Write-Host " LogRootPath              Folder for log files, relative to the script folder or absolute"
    Write-Host ""
    Write-Host " CimConnectionMode        'Default' or 'SSL'. Controls how the script connects to each"
    Write-Host "                          Exchange server for drive and service checks. 'Default' uses"
    Write-Host "                          plain Get-CimInstance -ComputerName (current behavior)."
    Write-Host "                          'SSL' opens a CIM session over HTTPS, needed in environments"
    Write-Host "                          where plain WinRM is restricted"
    Write-Host " CimSkipCaCheck           Only relevant when CimConnectionMode is 'SSL'. Skip CA trust"
    Write-Host "                          validation of the server certificate"
    Write-Host " CimSkipCnCheck           Only relevant when CimConnectionMode is 'SSL'. Skip common name"
    Write-Host "                          validation of the server certificate"
    Write-Host " CimSkipRevocationCheck   Only relevant when CimConnectionMode is 'SSL'. Skip certificate"
    Write-Host "                          revocation check"
    Write-Host ""
    Write-Host " SaveHtmlReport           If true, a copy of the HTML report is saved to disk"
    Write-Host " HtmlReportPath           Folder for saved HTML reports, relative or absolute"
    Write-Host " HtmlReportDaysToKeep     Days to keep saved HTML reports before automatic cleanup"
    Write-Host ""
    Write-Host " WarningsOnly             If true, the report only contains warning sections (no routine"
    Write-Host "                          overview tables). If a run finds no warnings, no mail is sent;"
    Write-Host "                          a note is logged instead, and (if SaveHtmlReport is true) a"
    Write-Host "                          report file with a '_NoWarnings' suffix is still saved to disk"
    Write-Host ""
    Write-Host " ShowMailboxOverview      Include the Mailbox Overview section in the report"
    Write-Host " ShowDatabaseOverview     Include the Database Overview section in the report"
    Write-Host " ShowDatabaseCopyStatus   Include the Database Copy Status section in the report"
    Write-Host " ShowPrimaryActiveManager Include the Primary Active Manager section in the report"
    Write-Host " ShowDriveOverview        Include the Drive Overview section in the report"
    Write-Host "                          These five only control whether the section is shown. The"
    Write-Host "                          underlying data is always collected, so related warnings (for"
    Write-Host "                          example a backup issue or a PAM mismatch) still appear in the"
    Write-Host "                          Warnings section even if the corresponding overview is hidden."
    Write-Host "                          All four, and WarningsOnly itself, are ignored (treated as"
    Write-Host "                          hidden) whenever WarningsOnly is true"
    Write-Host ""
    Write-Host " EnableQueueCheck         Enable or disable the message queue check"
    Write-Host " QueueLengthWarning       Message count above which a queue is flagged"
    Write-Host " PoisonQueueAlwaysWarn    If true, any message in the poison queue is always flagged,"
    Write-Host "                          regardless of QueueLengthWarning"
    Write-Host ""
    Write-Host " EnableCertificateCheck   Enable or disable the certificate check"
    Write-Host " CertExpiryWarningDays    Days before expiry at which a certificate is flagged."
    Write-Host "                          Only certificates that are actually bound to an Exchange"
    Write-Host "                          service are checked, not every certificate in the store"
    Write-Host ""
    Write-Host " EnableServiceCheck       Enable or disable the Exchange service check"
    Write-Host " ServiceCheckExclude      Array of service names to ignore in the service check."
    Write-Host "                          Takes precedence over ServiceCheckInclude if a name is in both"
    Write-Host " ServiceCheckInclude      Array of additional service names to check, even if they do"
    Write-Host "                          not match MSExchange* or are not set to Automatic start"
    Write-Host ""
    Write-Host " EnableReplicationCheck   Enable or disable the replication queue length check"
    Write-Host " CopyQueueLengthWarning   CopyQueueLength above which a database copy is flagged"
    Write-Host " ReplayQueueLengthWarning ReplayQueueLength above which a database copy is flagged"
    Write-Host ""
    Write-Host "Copy this file to config.json (or a custom name passed via -ConfigPath) and fill in the values."
}

if ($GenerateSampleConfig) {
    New-SampleConfig -Path $SampleConfigPath
    return
}

#endregion

#region Scheduled task registration

Function Register-ExchangeReportTask {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Daily", "Weekly")]
        [string]$Interval,

        [Parameter(Mandatory = $true)]
        [string[]]$Time,

        [Parameter(Mandatory = $false)]
        [string]$DayOfWeek,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $false)]
        [switch]$RunAsSystem
    )

    if ($RunAsSystem -and $Credential) {
        throw "Use either -RunAsSystem or -TaskCredential, not both."
    }

    $triggers = @()
    foreach ($t in $Time) {
        $atTime = $null
        try {
            $atTime = [datetime]::ParseExact($t.Trim(), "HH:mm", $null)
        }
        catch {
            throw "TaskTime '$t' is not in the expected HH:mm format."
        }

        if ($Interval -eq "Daily") {
            $triggers += New-ScheduledTaskTrigger -Daily -At $atTime
        }
        else {
            $triggers += New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DayOfWeek -At $atTime
        }
    }

    $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -ConfigPath `"$ConfigPath`""
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentList
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd
    $taskDescription = "Runs ExchangeReport.ps1 to collect and mail an Exchange environment report."

    if ($RunAsSystem) {
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

        Register-ScheduledTask -TaskName $TaskName `
            -Action $action `
            -Trigger $triggers `
            -Settings $settings `
            -Principal $principal `
            -Description $taskDescription `
            -Force | Out-Null
    }
    else {
        $cred = if ($Credential) {
            $Credential
        }
        else {
            Write-Host "Please provide the account this task should run as."
            Get-Credential -Message "Account to run the Exchange Report Scheduled Task"
        }

        Register-ScheduledTask -TaskName $TaskName `
            -Action $action `
            -Trigger $triggers `
            -Settings $settings `
            -User $cred.UserName `
            -Password $cred.GetNetworkCredential().Password `
            -RunLevel Highest `
            -Description $taskDescription `
            -Force | Out-Null
    }

    $timesText = $Time -join ", "
    $accountText = if ($RunAsSystem) { "NT AUTHORITY\SYSTEM" } else { "the provided account" }
    Write-Host "Scheduled Task '$TaskName' registered ($Interval at $timesText, running as $accountText)."
}

if ($RegisterTask) {
    if ($RunAsSystem -and $TaskCredential) {
        throw "Use either -RunAsSystem or -TaskCredential, not both."
    }
    $scriptPathForTask = if ($PSCommandPath) { $PSCommandPath } else { Join-Path -Path $scriptRoot -ChildPath "ExchangeReport.ps1" }
    Register-ExchangeReportTask -TaskName $TaskName -Interval $TaskInterval -Time $TaskTime `
        -DayOfWeek $TaskDayOfWeek -ScriptPath $scriptPathForTask -ConfigPath $ConfigPath `
        -Credential $TaskCredential -RunAsSystem:$RunAsSystem
    return
}

#endregion

#region Config loading and validation

Function Get-ReportConfig {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Config file not found at '$Path'. Run the script with -GenerateSampleConfig to create a starting point."
    }

    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Config file '$Path' could not be parsed as JSON: $($_.Exception.Message)"
    }

    $required = @("SmtpServer", "MailFrom", "MailTo", "EnvironmentName")
    foreach ($key in $required) {
        if (-not ($raw.PSObject.Properties.Name -contains $key) -or [string]::IsNullOrWhiteSpace(($raw.$key | Out-String))) {
            throw "Config file '$Path' is missing a value for required field '$key'."
        }
    }

    Function Get-ConfigValue {
        Param($Raw, $Name, $Default)
        if ($Raw.PSObject.Properties.Name -contains $Name -and $null -ne $Raw.$Name) {
            return $Raw.$Name
        }
        return $Default
    }

    $config = [pscustomobject]@{
        EnvironmentName          = $raw.EnvironmentName
        ServerNamePattern        = Get-ConfigValue $raw "ServerNamePattern" ""
        DagName                  = Get-ConfigValue $raw "DagName" ""
        ExpectedPamServer        = Get-ConfigValue $raw "ExpectedPamServer" ""
        SmtpServer                = $raw.SmtpServer
        MailFrom                  = $raw.MailFrom
        MailTo                     = @($raw.MailTo)

        DriveFreePercentWarning  = [double](Get-ConfigValue $raw "DriveFreePercentWarning" 12)
        BackupMaxAgeDays          = [int](Get-ConfigValue $raw "BackupMaxAgeDays" 1)
        LogDaysToKeep             = [int](Get-ConfigValue $raw "LogDaysToKeep" 30)
        LogRootPath               = Get-ConfigValue $raw "LogRootPath" "logs"

        CimConnectionMode         = Get-ConfigValue $raw "CimConnectionMode" "Default"
        CimSkipCaCheck            = [bool](Get-ConfigValue $raw "CimSkipCaCheck" $true)
        CimSkipCnCheck            = [bool](Get-ConfigValue $raw "CimSkipCnCheck" $true)
        CimSkipRevocationCheck   = [bool](Get-ConfigValue $raw "CimSkipRevocationCheck" $true)

        SaveHtmlReport            = [bool](Get-ConfigValue $raw "SaveHtmlReport" $true)
        HtmlReportPath            = Get-ConfigValue $raw "HtmlReportPath" "Reports"
        HtmlReportDaysToKeep     = [int](Get-ConfigValue $raw "HtmlReportDaysToKeep" 30)

        WarningsOnly              = [bool](Get-ConfigValue $raw "WarningsOnly" $false)

        ShowMailboxOverview       = [bool](Get-ConfigValue $raw "ShowMailboxOverview" $true)
        ShowDatabaseOverview      = [bool](Get-ConfigValue $raw "ShowDatabaseOverview" $true)
        ShowDatabaseCopyStatus   = [bool](Get-ConfigValue $raw "ShowDatabaseCopyStatus" $true)
        ShowPrimaryActiveManager = [bool](Get-ConfigValue $raw "ShowPrimaryActiveManager" $true)
        ShowDriveOverview         = [bool](Get-ConfigValue $raw "ShowDriveOverview" $true)

        EnableQueueCheck          = [bool](Get-ConfigValue $raw "EnableQueueCheck" $true)
        QueueLengthWarning        = [int](Get-ConfigValue $raw "QueueLengthWarning" 100)
        PoisonQueueAlwaysWarn    = [bool](Get-ConfigValue $raw "PoisonQueueAlwaysWarn" $true)

        EnableCertificateCheck   = [bool](Get-ConfigValue $raw "EnableCertificateCheck" $true)
        CertExpiryWarningDays    = [int](Get-ConfigValue $raw "CertExpiryWarningDays" 30)

        EnableServiceCheck        = [bool](Get-ConfigValue $raw "EnableServiceCheck" $true)
        ServiceCheckExclude       = @(Get-ConfigValue $raw "ServiceCheckExclude" @())
        ServiceCheckInclude       = @(Get-ConfigValue $raw "ServiceCheckInclude" @())

        EnableReplicationCheck   = [bool](Get-ConfigValue $raw "EnableReplicationCheck" $true)
        CopyQueueLengthWarning   = [int](Get-ConfigValue $raw "CopyQueueLengthWarning" 5)
        ReplayQueueLengthWarning = [int](Get-ConfigValue $raw "ReplayQueueLengthWarning" 5)
    }

    if (-not [string]::IsNullOrWhiteSpace($config.LogRootPath) -and -not [System.IO.Path]::IsPathRooted($config.LogRootPath)) {
        $config.LogRootPath = Join-Path -Path $scriptRoot -ChildPath $config.LogRootPath
    }
    if (-not [string]::IsNullOrWhiteSpace($config.HtmlReportPath) -and -not [System.IO.Path]::IsPathRooted($config.HtmlReportPath)) {
        $config.HtmlReportPath = Join-Path -Path $scriptRoot -ChildPath $config.HtmlReportPath
    }

    return $config
}

# Validates all config values before any Exchange access happens. Collects
# every problem found instead of stopping at the first one, so a single run
# can report all issues at once.
Function Test-ReportConfig {
    Param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    $errorList = New-Object System.Collections.Generic.List[string]
    $emailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'

    if ($Config.MailFrom -notmatch $emailPattern) {
        $errorList.Add("MailFrom '$($Config.MailFrom)' does not look like a valid email address.")
    }

    if (-not $Config.MailTo -or $Config.MailTo.Count -eq 0) {
        $errorList.Add("MailTo must contain at least one recipient address.")
    }
    else {
        foreach ($addr in $Config.MailTo) {
            if ($addr -notmatch $emailPattern) {
                $errorList.Add("MailTo entry '$addr' does not look like a valid email address.")
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Config.SmtpServer)) {
        $errorList.Add("SmtpServer must not be empty.")
    }

    if ($Config.CimConnectionMode -notin @("Default", "SSL")) {
        $errorList.Add("CimConnectionMode must be either 'Default' or 'SSL', got '$($Config.CimConnectionMode)'.")
    }

    Function Test-NumericRange {
        Param($Name, $Value, $Min, $Max)
        if ($Value -isnot [int] -and $Value -isnot [double]) {
            $errorList.Add("$Name must be a number, got '$Value'.")
            return
        }
        if ($null -ne $Min -and $Value -lt $Min) {
            $errorList.Add("$Name ($Value) must be greater than or equal to $Min.")
        }
        if ($null -ne $Max -and $Value -gt $Max) {
            $errorList.Add("$Name ($Value) must be less than or equal to $Max.")
        }
    }

    Test-NumericRange "DriveFreePercentWarning" $Config.DriveFreePercentWarning 0 100
    Test-NumericRange "BackupMaxAgeDays" $Config.BackupMaxAgeDays 1 $null
    Test-NumericRange "LogDaysToKeep" $Config.LogDaysToKeep 1 $null
    Test-NumericRange "HtmlReportDaysToKeep" $Config.HtmlReportDaysToKeep 1 $null
    Test-NumericRange "QueueLengthWarning" $Config.QueueLengthWarning 0 $null
    Test-NumericRange "CertExpiryWarningDays" $Config.CertExpiryWarningDays 1 $null
    Test-NumericRange "CopyQueueLengthWarning" $Config.CopyQueueLengthWarning 0 $null
    Test-NumericRange "ReplayQueueLengthWarning" $Config.ReplayQueueLengthWarning 0 $null

    Function Test-WritablePath {
        Param($Name, $Path)
        try {
            if (-not (Test-Path $Path)) {
                New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            $testFile = Join-Path -Path $Path -ChildPath ".writetest_$([guid]::NewGuid().ToString('N')).tmp"
            "test" | Out-File -FilePath $testFile -ErrorAction Stop
            Remove-Item -Path $testFile -ErrorAction SilentlyContinue
        }
        catch {
            $errorList.Add("$Name '$Path' is not writable: $($_.Exception.Message)")
        }
    }

    Test-WritablePath "LogRootPath" $Config.LogRootPath
    if ($Config.SaveHtmlReport) {
        Test-WritablePath "HtmlReportPath" $Config.HtmlReportPath
    }

    if ($errorList.Count -gt 0) {
        throw "Config validation failed:`n - $($errorList -join "`n - ")"
    }

    # Soft check: SMTP reachability. Logged as a warning only, does not stop the run,
    # because a blocked test connection does not always mean the real send will fail.
    try {
        $smtpTest = Test-NetConnection -ComputerName $Config.SmtpServer -Port 25 -WarningAction SilentlyContinue -InformationLevel Quiet -ErrorAction Stop
        if (-not $smtpTest) {
            LogAndOutput "Warning: SMTP server '$($Config.SmtpServer)' on port 25 does not appear reachable from this host." -outcolor yellow
        }
    }
    catch {
        LogAndOutput "Warning: could not test connectivity to SMTP server '$($Config.SmtpServer)': $($_.Exception.Message)" -outcolor yellow
    }
}

#endregion

#region Helper functions

Function global:createLogfile ($NameFilePart, $LogRootPath) {
    $CreateDate   = Get-Date -Format yyyyMMdd_HHmm
    $LogName      = "$($CreateDate)_$($NameFilePart)"
    $computername = $env:computername
    $userdomain   = $env:userdomain
    $activeuser   = $env:username

    if (-not (Test-Path $LogRootPath)) {
        New-Item -ItemType Directory -Path $LogRootPath -Force | Out-Null
        Write-Host "Log folder created: $LogRootPath"
    }

    $LogPathName = Join-Path -Path $LogRootPath -ChildPath $LogName

    "$(Get-Date -Format s) Start logging" | Out-File $LogPathName -Append
    "Computer: $($Computername) - User: $($Userdomain)\$($activeuser)" | Out-File $LogPathName -Append
    "" | Out-File $LogPathName -Append

    return $LogPathName
}

Function LogAndOutput {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$loginput,

        [Parameter(Mandatory = $false)]
        [switch]$outputonly,

        [Parameter(Mandatory = $false)]
        [switch]$logonly,

        [Parameter(Mandatory = $false)]
        [string]$outcolor = "white"
    )

    if ($outputonly -eq $false -and $logfile) {
        $timestamp = Get-Date -Format "yyyyMMdd - HH:mm:ss"
        "$timestamp - $loginput" | Out-File $logfile -Append
    }

    if ($logonly -eq $false) {
        Write-Host $loginput -ForegroundColor $outcolor
    }
}

Function SetLocation {
    if ($scriptRoot) {
        $mydir = (Get-Location).Path
        if ($mydir -ne $scriptRoot) {
            Set-Location $scriptRoot
        }
    }
}

Function CleanOldFiles {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$FileExt = "*.log",

        [Parameter(Mandatory = $false)]
        [int]$DaysToKeep = 30
    )

    if (-not (Test-Path $Path)) {
        LogAndOutput "CleanOldFiles: path '$Path' does not exist, skipping cleanup." -outcolor yellow
        return
    }

    $removedate = (Get-Date).AddDays(-$DaysToKeep)
    $files = Get-ChildItem -Path $Path -Recurse -Include $FileExt -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $removedate }

    foreach ($file in $files) {
        try {
            Remove-Item -Path $file.FullName -ErrorAction Stop
        }
        catch {
            LogAndOutput "$($file.Name) could not be deleted: $($_.Exception.Message)" -outcolor yellow
        }
    }
}

# Converts an Exchange size value (for example a ByteQuantifiedSize object or its
# string form) into a plain number. Returns $null instead of throwing if the
# value cannot be parsed.
Function ConvertBytesStringToValue {
    Param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    if ($null -eq $Value) { return $null }

    try {
        if ($Value.PSObject.Methods.Name -contains "ToBytes") {
            [int64]$bytes = $Value.ToBytes()
        }
        else {
            $text = $Value.ToString()
            [int64]$bytes = $text.Split("(")[1].Split(" ")[0].Replace(",", "").Replace(".", "")
        }

        $bytevalue = $bytes / "1$Type"
        return [math]::Round($bytevalue, 2)
    }
    catch {
        LogAndOutput "ConvertBytesStringToValue: value '$Value' could not be parsed." -outcolor yellow
        return $null
    }
}

# Verifies the Exchange Management Shell is usable before any data collection
# starts. Throws (caught by the main try/catch) if it is not.
Function Test-ExchangeEnvironment {
    Param(
        [Parameter(Mandatory = $false)]
        [string]$ServerNamePattern
    )

    if (-not (Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue)) {
        try {
            Add-PsSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
        }
        catch {
            throw "Exchange snapin could not be loaded: $($_.Exception.Message)"
        }
    }

    try {
        if ([string]::IsNullOrWhiteSpace($ServerNamePattern)) {
            $testServer = Get-ExchangeServer -ErrorAction Stop | Select-Object -First 1
        }
        else {
            $testServer = Get-ExchangeServer -Identity $ServerNamePattern -ErrorAction Stop | Select-Object -First 1
        }

        if (-not $testServer) {
            throw "Get-ExchangeServer returned no servers."
        }
    }
    catch {
        throw "Exchange shell is loaded, but the test query (Get-ExchangeServer) failed: $($_.Exception.Message)"
    }

    LogAndOutput "Exchange shell verified (test server: $($testServer.Name))." -outcolor green
}

# Best effort emergency mail if the script aborts early. Wrapped in its own
# try/catch so a failure here does not throw an unhandled exception.
Function Send-EmergencyMail {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,

        [Parameter(Mandatory = $true)]
        $Config
    )

    try {
        $body = @"
The ExchangeReport script was aborted before it could finish.

Environment: $($Config.EnvironmentName)

Error:
$ErrorMessage

Computer: $($env:computername)
Running as: $($env:userdomain)\$($env:username)
Time: $(Get-Date -Format s)
"@
        Send-MailMessage -SmtpServer $Config.SmtpServer -From $Config.MailFrom -To $Config.MailTo `
            -Subject "$($Config.EnvironmentName) - Report script aborted" -Body $body -Encoding utf8 -ErrorAction Stop
    }
    catch {
        Write-Host "Emergency mail could not be sent: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Builds a styled HTML table from objects. RowClassRule is a scriptblock that
# is invoked per object and may return a CSS class name ("warn" or "crit").
Function ConvertTo-StyledHtmlTable {
    Param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Objects,

        [Parameter(Mandatory = $true)]
        [string[]]$Columns,

        [Parameter(Mandatory = $false)]
        [scriptblock]$RowClassRule
    )

    if (-not $Objects -or $Objects.Count -eq 0) {
        return "<p class='muted'>No data available.</p>"
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<table class='data'><thead><tr>")
    foreach ($col in $Columns) { [void]$sb.Append("<th>$col</th>") }
    [void]$sb.Append("</tr></thead><tbody>")

    foreach ($obj in $Objects) {
        $rowClass = ""
        if ($RowClassRule) {
            $rowClass = & $RowClassRule $obj
        }
        $classAttr = if ($rowClass) { " class='$rowClass'" } else { "" }
        [void]$sb.Append("<tr$classAttr>")
        foreach ($col in $Columns) {
            $val = $obj.$col
            [void]$sb.Append("<td>$val</td>")
        }
        [void]$sb.Append("</tr>")
    }

    [void]$sb.Append("</tbody></table>")
    return $sb.ToString()
}

# Establishes the connection info used for CIM based checks (drives, services)
# against one Exchange server, honoring CimConnectionMode from the config.
# Returns an object with Fqdn and, for SSL mode, an open CimSession. The
# caller is responsible for closing the session with Remove-CimSession.
Function Get-ServerConnection {
    Param(
        [Parameter(Mandatory = $true)]
        $ExchangeServer,

        [Parameter(Mandatory = $true)]
        $Config
    )

    $fqdn = if ($ExchangeServer.Fqdn) { $ExchangeServer.Fqdn } else { $ExchangeServer.Name }

    $session = $null
    if ($Config.CimConnectionMode -eq "SSL") {
        $sessionOption = New-CimSessionOption -UseSsl `
            -SkipCACheck:$Config.CimSkipCaCheck `
            -SkipCNCheck:$Config.CimSkipCnCheck `
            -SkipRevocationCheck:$Config.CimSkipRevocationCheck

        $session = New-CimSession -ComputerName $fqdn -SessionOption $sessionOption -ErrorAction Stop
    }

    return [pscustomobject]@{
        Fqdn    = $fqdn
        Session = $session
    }
}

# Best effort close of a CIM session opened by Get-ServerConnection. Does
# nothing if the connection did not use a session (Default mode).
Function Close-ServerConnection {
    Param($Connection)

    if ($Connection -and $Connection.Session) {
        Remove-CimSession -CimSession $Connection.Session -ErrorAction SilentlyContinue
    }
}


Function Get-SafeFileNamePart {
    Param([string]$Text)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars() -join ""
    $pattern = "[{0}]" -f [regex]::Escape($invalid)
    $safe = ($Text -replace $pattern, "_") -replace "\s+", "_"
    return $safe
}

#endregion

#region CSS

$reportCss = @"
<style>
  body { font-family: Segoe UI, Arial, sans-serif; color: #1f2933; background: #f4f6f8; margin: 0; padding: 24px; }
  .container { max-width: 1000px; margin: 0 auto; background: #ffffff; border-radius: 8px; padding: 24px 32px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
  h1 { font-size: 20px; margin-bottom: 4px; }
  h2 { font-size: 16px; margin-top: 28px; margin-bottom: 8px; border-bottom: 1px solid #e2e8f0; padding-bottom: 4px; }
  .subtitle { color: #64748b; font-size: 13px; margin-top: 0; }
  .badge { display: inline-block; padding: 6px 14px; border-radius: 4px; font-weight: 600; font-size: 13px; }
  .badge-ok { background: #dcfce7; color: #166534; }
  .badge-warn { background: #fef3c7; color: #92400e; }
  table.data { border-collapse: collapse; width: 100%; font-size: 13px; margin-bottom: 8px; }
  table.data th { background: #f1f5f9; text-align: left; padding: 6px 10px; border-bottom: 2px solid #cbd5e1; }
  table.data td { padding: 6px 10px; border-bottom: 1px solid #e2e8f0; }
  table.data tr.warn td { background: #fef3c7; }
  table.data tr.crit td { background: #fee2e2; }
  .muted { color: #64748b; font-size: 13px; }
  .notice { padding: 10px 14px; border-radius: 6px; font-size: 13px; margin-bottom: 8px; }
  .notice-ok { background: #f1f5f9; }
  .notice-warn { background: #fef3c7; color: #92400e; }
  .footer { margin-top: 24px; color: #94a3b8; font-size: 11px; }
</style>
"@

#endregion

#region Main

$error.Clear()
$warning = $false
$transcriptStarted = $false
$logfile = $null
$reportConfig = $null

try {
    $reportConfig = Get-ReportConfig -Path $ConfigPath

    SetLocation

    if ($EnableDebugTranscript) {
        $transcriptPath = Join-Path -Path $reportConfig.LogRootPath -ChildPath "transcript_$(Get-Date -Format yyyyMMdd_HHmm).txt"
        if (-not (Test-Path $reportConfig.LogRootPath)) {
            New-Item -ItemType Directory -Path $reportConfig.LogRootPath -Force | Out-Null
        }
        Start-Transcript -Path $transcriptPath -ErrorAction SilentlyContinue | Out-Null
        $transcriptStarted = $true
    }

    $logfile = createLogfile "ExchangeReport.log" $reportConfig.LogRootPath
    Write-Host "Log file created at $logfile"

    #### Validate config values before touching Exchange ####
    Test-ReportConfig -Config $reportConfig

    #### Pre-flight check: is the Exchange shell usable? ####
    Test-ExchangeEnvironment -ServerNamePattern $reportConfig.ServerNamePattern

    #region Discover servers
    if ([string]::IsNullOrWhiteSpace($reportConfig.ServerNamePattern)) {
        $xserver = Get-ExchangeServer -ErrorAction Stop
        LogAndOutput "No ServerNamePattern configured, discovered $($xserver.Count) Exchange server(s) automatically."
    }
    else {
        $xserver = Get-ExchangeServer -Identity $reportConfig.ServerNamePattern -ErrorAction Stop
    }

    if (-not $xserver -or $xserver.Count -eq 0) {
        throw "No Exchange servers were found."
    }

    $serverNames = @($xserver.Name)
    # Note: msExchHomeServerName in AD stores the short server name inside the
    # legacyExchangeDN, not the FQDN, so this match intentionally uses Name
    # rather than Fqdn.
    $serverPatternForMatch = ($serverNames | ForEach-Object { [regex]::Escape($_) }) -join "|"
    #endregion

    #region Discover DAG
    if ([string]::IsNullOrWhiteSpace($reportConfig.DagName)) {
        $dagsFound = Get-DatabaseAvailabilityGroup -Status -ErrorAction Stop
        if (-not $dagsFound -or $dagsFound.Count -eq 0) {
            throw "No DagName configured and no Database Availability Group could be found automatically."
        }
        if ($dagsFound.Count -gt 1) {
            LogAndOutput "Multiple Database Availability Groups found, using the first one: $($dagsFound[0].Name)" -outcolor yellow
        }
        $dag = $dagsFound[0]
        LogAndOutput "No DagName configured, discovered DAG automatically: $($dag.Name)"
    }
    else {
        $dag = Get-DatabaseAvailabilityGroup -Identity $reportConfig.DagName -Status -ErrorAction Stop
    }
    #endregion

    #region Mailboxes
    $objMbInfo = $null
    if ($reportConfig.ShowMailboxOverview) {
        $Types = 1, 2, 4, 16, 32

        $adu = Get-ADUser -Properties msExchHomeServerName, MsExchRecipientTypeDetails -Filter * -ErrorAction Stop
        $rec = $adu | Where-Object {
            $Types -contains $_.MsExchRecipientTypeDetails -and
            $_.msExchHomeServerName -and
            $_.msExchHomeServerName -match "cn=($serverPatternForMatch)$"
        }
        $stdmbx    = $rec | Where-Object { $_.MsExchRecipientTypeDetails -eq 1 -or $_.MsExchRecipientTypeDetails -eq 2 }
        $sharedMbx = $rec | Where-Object { $_.MsExchRecipientTypeDetails -eq 4 }
        $resMbx    = $rec | Where-Object { $_.MsExchRecipientTypeDetails -eq 16 -or $_.MsExchRecipientTypeDetails -eq 32 }

        $objMbInfo = [pscustomobject]@{
            "User Mailboxes"     = $stdmbx.Count
            "Shared Mailboxes"   = $sharedMbx.Count
            "Resource Mailboxes" = $resMbx.Count
            "Total Mailboxes"    = $rec.Count
        }
    }
    else {
        LogAndOutput "ShowMailboxOverview is disabled, skipping mailbox count collection."
    }
    #endregion

    #region Server queries (drives and services)
    # Both checks connect to each Exchange server via CIM. The connection
    # (plain CIM or an SSL CIM session, depending on CimConnectionMode) is
    # established once per server and reused for both checks, then closed.
    $objAllDrives = @()
    $serviceInfo = @()

    foreach ($xms in $xserver) {
        $conn = $null
        try {
            $conn = Get-ServerConnection -ExchangeServer $xms -Config $reportConfig
        }
        catch {
            LogAndOutput "Could not connect to $($xms.Fqdn) for CIM queries: $($_.Exception.Message)" -outcolor yellow
            continue
        }

        try {
            try {
                if ($conn.Session) {
                    $drives = Get-CimInstance -CimSession $conn.Session -ClassName Win32_Volume -ErrorAction Stop | Sort-Object Name
                }
                else {
                    $drives = Get-CimInstance -ComputerName $conn.Fqdn -ClassName Win32_Volume -ErrorAction Stop | Sort-Object Name
                }

                foreach ($drive in $drives) {
                    $capa = [math]::Truncate($drive.Capacity / 1GB)
                    $free = [math]::Truncate($drive.FreeSpace / 1GB)

                    if ($capa -gt 0) {
                        $percFree = [math]::Round(($free / $capa * 100), 1)
                    }
                    else {
                        $percFree = $null
                    }

                    $objAllDrives += [pscustomobject]@{
                        Server         = $conn.Fqdn
                        Drive          = $drive.Name
                        "Size (GB)"    = $capa
                        "Free (GB)"    = $free
                        "Free (%)"     = $percFree
                    }
                }
            }
            catch {
                LogAndOutput "Drives on $($conn.Fqdn) could not be queried: $($_.Exception.Message)" -outcolor yellow
            }

            if ($reportConfig.EnableServiceCheck) {
                try {
                    if ($conn.Session) {
                        $winServices = Get-CimInstance -CimSession $conn.Session -ClassName Win32_Service -ErrorAction Stop
                    }
                    else {
                        $winServices = Get-CimInstance -ComputerName $conn.Fqdn -ClassName Win32_Service -ErrorAction Stop
                    }

                    $services = $winServices | Where-Object {
                        (
                            ($_.Name -like "MSExchange*" -and $_.StartMode -eq "Auto") -or
                            ($reportConfig.ServiceCheckInclude -contains $_.Name)
                        ) -and
                        ($reportConfig.ServiceCheckExclude -notcontains $_.Name)
                    }

                    foreach ($svc in $services) {
                        $svcIssues = New-Object System.Collections.Generic.List[string]
                        if ($svc.State -ne "Running") {
                            $svcIssues.Add("Service is '$($svc.State)' but StartMode is $($svc.StartMode)")
                        }

                        $serviceInfo += [pscustomobject]@{
                            Server      = $conn.Fqdn
                            ServiceName = $svc.Name
                            DisplayName = $svc.DisplayName
                            Status      = $svc.State
                            StartType   = $svc.StartMode
                            Issue       = $svcIssues -join "; "
                        }
                    }
                }
                catch {
                    LogAndOutput "Services on $($conn.Fqdn) could not be queried: $($_.Exception.Message)" -outcolor yellow
                }
            }
        }
        finally {
            Close-ServerConnection -Connection $conn
        }
    }
    #endregion


    #region Database and database copy info
    $mbdbs = Get-MailboxDatabase -Identity "$($dag.Name)*" -Status -ErrorAction Stop

    $backupCutoff = (Get-Date).AddDays(-$reportConfig.BackupMaxAgeDays)

    $DBInfo = @()
    $mbcopystate = @()

    foreach ($db in $mbdbs) {
        try {
            $mbxCount = (Get-MailboxStatistics -Database $db.Name -ErrorAction Stop | Where-Object { $null -eq $_.DisconnectReason }).Count
        }
        catch {
            LogAndOutput "MailboxStatistics for database $($db.Name) failed: $($_.Exception.Message)" -outcolor yellow
            $mbxCount = $null
        }

        $mbstate    = Get-MailboxDatabaseCopyStatus -Identity $db.Name -ErrorAction SilentlyContinue
        $activecopy = $mbstate | Where-Object { $_.Status -eq "Mounted" }
        $Pref1      = $mbstate | Where-Object { $_.ActivationPreference -eq 1 }

        $correctsrv = if ($activecopy.MailboxServer -eq $Pref1.MailboxServer) { "YES" } else { "NO" }

        $dbIssues = New-Object System.Collections.Generic.List[string]
        if ($correctsrv -ne "YES") {
            $dbIssues.Add("Not mounted on the preferred server (Pref1: $($Pref1.MailboxServer), active: $($db.Server))")
        }
        if (-not $db.LastFullBackup) {
            $dbIssues.Add("No full backup recorded")
        }
        elseif ($db.LastFullBackup -lt $backupCutoff) {
            $dbIssues.Add("Last full backup is older than $($reportConfig.BackupMaxAgeDays) day(s) (last: $($db.LastFullBackup))")
        }

        $DBInfo += [pscustomobject]@{
            Name                     = $db.Name
            ActiveOnServer           = $db.Server
            MailboxCount             = $mbxCount
            DBSizeInGB               = ConvertBytesStringToValue -Value $db.DatabaseSize -Type GB
            WhiteSpaceInGB           = ConvertBytesStringToValue -Value $db.AvailableNewMailboxSpace -Type GB
            LastFullBackup           = $db.LastFullBackup
            IsMountedOnCorrectServer = $correctsrv
            Pref1Server              = $Pref1.MailboxServer
            Issue                    = $dbIssues -join "; "
        }

        foreach ($mb in $mbstate) {
            $copyIssues = New-Object System.Collections.Generic.List[string]
            if ($mb.Status -notlike "Healthy" -and $mb.Status -notlike "Mounted") {
                $copyIssues.Add("Status is '$($mb.Status)' (expected Healthy or Mounted)")
            }
            if ($reportConfig.EnableReplicationCheck) {
                if ($null -ne $mb.CopyQueueLength -and $mb.CopyQueueLength -gt $reportConfig.CopyQueueLengthWarning) {
                    $copyIssues.Add("CopyQueueLength $($mb.CopyQueueLength) exceeds threshold $($reportConfig.CopyQueueLengthWarning)")
                }
                if ($null -ne $mb.ReplayQueueLength -and $mb.ReplayQueueLength -gt $reportConfig.ReplayQueueLengthWarning) {
                    $copyIssues.Add("ReplayQueueLength $($mb.ReplayQueueLength) exceeds threshold $($reportConfig.ReplayQueueLengthWarning)")
                }
            }

            $mbcopystate += [pscustomobject]@{
                DBName            = $db.Name
                Server            = $mb.MailboxServer
                Status            = $mb.Status
                CopyQueueLength   = $mb.CopyQueueLength
                ReplayQueueLength = $mb.ReplayQueueLength
                Issue             = $copyIssues -join "; "
            }
        }
    }
    #endregion

    #region Message queues
    $queueInfo = @()
    if ($reportConfig.EnableQueueCheck) {
        foreach ($xms in $xserver) {
            try {
                $queues = Get-Queue -Server $xms.Fqdn -ErrorAction Stop
            }
            catch {
                LogAndOutput "Queues on $($xms.Fqdn) could not be queried: $($_.Exception.Message)" -outcolor yellow
                continue
            }

            foreach ($q in $queues) {
                $isPoison = $q.Identity -like "*\Poison"
                $queueIssues = New-Object System.Collections.Generic.List[string]

                if ($isPoison -and $reportConfig.PoisonQueueAlwaysWarn -and $q.MessageCount -gt 0) {
                    $queueIssues.Add("Poison queue contains $($q.MessageCount) message(s)")
                }
                elseif ($q.MessageCount -gt $reportConfig.QueueLengthWarning) {
                    $queueIssues.Add("MessageCount $($q.MessageCount) exceeds threshold $($reportConfig.QueueLengthWarning)")
                }

                $queueInfo += [pscustomobject]@{
                    Server       = $xms.Fqdn
                    Queue        = $q.Identity
                    DeliveryType = $q.DeliveryType
                    MessageCount = $q.MessageCount
                    Status       = $q.Status
                    Issue        = $queueIssues -join "; "
                }
            }
        }
    }
    #endregion

    #region Certificates
    $certInfo = @()
    if ($reportConfig.EnableCertificateCheck) {
        foreach ($xms in $xserver) {
            try {
                $certs = Get-ExchangeCertificate -Server $xms.Fqdn -ErrorAction Stop | Where-Object { $_.Services -and $_.Services -ne "None" }
            }
            catch {
                LogAndOutput "Certificates on $($xms.Fqdn) could not be queried: $($_.Exception.Message)" -outcolor yellow
                continue
            }

            foreach ($cert in $certs) {
                $daysRemaining = [math]::Floor(($cert.NotAfter - (Get-Date)).TotalDays)
                $certIssues = New-Object System.Collections.Generic.List[string]

                if ($daysRemaining -lt 0) {
                    $certIssues.Add("Certificate expired $([math]::Abs($daysRemaining)) day(s) ago")
                }
                elseif ($daysRemaining -le $reportConfig.CertExpiryWarningDays) {
                    $certIssues.Add("Certificate expires in $daysRemaining day(s) (threshold: $($reportConfig.CertExpiryWarningDays))")
                }

                $certInfo += [pscustomobject]@{
                    Server        = $xms.Fqdn
                    Subject       = $cert.Subject
                    Services      = $cert.Services
                    NotAfter      = $cert.NotAfter
                    DaysRemaining = $daysRemaining
                    Issue         = $certIssues -join "; "
                }
            }
        }
    }
    #endregion

    #region Services
    # Services are checked together with drives in the "Server queries" region
    # above, so both share the same per-server CIM connection.
    #endregion


    #region Health check
    $healthwarning = @(
        $xserver |
        Where-Object { $_.AdminDisplayVersion -like "Version 15.1*" } |
        ForEach-Object {
            try { Get-HealthReport -Server $_.Fqdn -ErrorAction Stop | Where-Object { $_.AlertValue -notlike "Healthy" } }
            catch { LogAndOutput "Get-HealthReport for $($_.Fqdn) failed." -outcolor yellow }
        }
    )
    #endregion

    #region Determine warnings
    $dbwarning     = @($DBInfo | Where-Object { $_.Issue })
    $drivewarning  = @($objAllDrives | Where-Object { $null -ne $_."Free (%)" -and $_."Free (%)" -le $reportConfig.DriveFreePercentWarning })
    $dbcopywarning = @($mbcopystate | Where-Object { $_.Issue })
    $queuewarning  = @($queueInfo | Where-Object { $_.Issue })
    $certwarning   = @($certInfo | Where-Object { $_.Issue })
    $servicewarning = @($serviceInfo | Where-Object { $_.Issue })

    $dagwarning = $null
    if (-not [string]::IsNullOrWhiteSpace($reportConfig.ExpectedPamServer) -and $dag.PrimaryActiveManager -notlike $reportConfig.ExpectedPamServer) {
        $dagwarning = "The current Primary Active Manager is not the expected PAM $($reportConfig.ExpectedPamServer) (current: $($dag.PrimaryActiveManager))."
    }

    if ($dbwarning.Count -ne 0)      { $warning = $true }
    if ($drivewarning.Count -ne 0)   { $warning = $true }
    if ($dbcopywarning.Count -ne 0)  { $warning = $true }
    if ($queuewarning.Count -ne 0)   { $warning = $true }
    if ($certwarning.Count -ne 0)    { $warning = $true }
    if ($servicewarning.Count -ne 0) { $warning = $true }
    if ($dagwarning)                 { $warning = $true }
    if ($healthwarning.Count -ne 0)  { $warning = $true }
    #endregion

    #region Build report
    $statusBadge = if ($warning) {
        "<span class='badge badge-warn'>WARNING - issues found</span>"
    } else {
        "<span class='badge badge-ok'>OK - no issues found</span>"
    }

    $html = New-Object System.Text.StringBuilder
    [void]$html.Append("<html><head><meta charset='utf-8'>$reportCss</head><body><div class='container'>")
    [void]$html.Append("<h1>$($reportConfig.EnvironmentName) - Exchange Report</h1>")
    [void]$html.Append("<p class='subtitle'>Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>")
    [void]$html.Append("<p>$statusBadge</p>")

    if ($reportConfig.WarningsOnly -and -not $warning) {
        [void]$html.Append("<p class='muted'>WarningsOnly is enabled and no warnings were found on this run. No mail was sent.</p>")
    }

    if ($warning) {
        [void]$html.Append("<h2>Warnings</h2>")

        if ($dbwarning.Count -gt 0) {
            [void]$html.Append("<p class='muted'>Databases with a backup or mount issue:</p>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects $dbwarning -Columns @("Name","ActiveOnServer","Issue") -RowClassRule { "crit" }))
        }
        if ($drivewarning.Count -gt 0) {
            [void]$html.Append("<p class='muted'>Drives with low free space:</p>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects $drivewarning -Columns @("Server","Drive","Size (GB)","Free (GB)","Free (%)") -RowClassRule { "warn" }))
        }
        if ($dbcopywarning.Count -gt 0) {
            [void]$html.Append("<p class='muted'>Database copies with a noteworthy status:</p>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects $dbcopywarning -Columns @("DBName","Server","Status","Issue") -RowClassRule { "crit" }))
        }
        if ($queuewarning.Count -gt 0) {
            [void]$html.Append("<p class='muted'>Message queues with a noteworthy status:</p>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects $queuewarning -Columns @("Server","Queue","MessageCount","Issue") -RowClassRule { "warn" }))
        }
        if ($certwarning.Count -gt 0) {
            [void]$html.Append("<p class='muted'>Certificates in use that are expiring or expired:</p>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects $certwarning -Columns @("Server","Subject","Services","NotAfter","Issue") -RowClassRule {
                param($o)
                if ($o.DaysRemaining -lt 0) { "crit" } else { "warn" }
            }))
        }
        if ($servicewarning.Count -gt 0) {
            [void]$html.Append("<p class='muted'>Exchange services that should be running but are not:</p>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects $servicewarning -Columns @("Server","ServiceName","Status","Issue") -RowClassRule { "crit" }))
        }
        if ($dagwarning) {
            [void]$html.Append("<p class='muted'>$dagwarning</p>")
        }
        if ($healthwarning.Count -gt 0) {
            [void]$html.Append("<p class='muted'>Server health report findings:</p>")
            [void]$html.Append(($healthwarning | Sort-Object Server | ConvertTo-Html -Fragment))
        }
    }

    if (-not $reportConfig.WarningsOnly) {
        if ($reportConfig.ShowPrimaryActiveManager) {
            [void]$html.Append("<h2>Primary Active Manager</h2>")
            $pamNoticeClass = if ($dagwarning) { "notice-warn" } else { "notice-ok" }
            [void]$html.Append("<div class='notice $pamNoticeClass'>")
            [void]$html.Append("<p>Primary Active Manager is <strong>$($dag.PrimaryActiveManager)</strong></p>")
            if ($dagwarning) {
                [void]$html.Append("<p>$dagwarning</p>")
            }
            [void]$html.Append("</div>")
        }

        if ($reportConfig.ShowMailboxOverview -and $objMbInfo) {
            [void]$html.Append("<h2>Mailbox Overview</h2>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects @($objMbInfo) -Columns @("User Mailboxes","Shared Mailboxes","Resource Mailboxes","Total Mailboxes")))
        }

        if ($reportConfig.ShowDatabaseOverview) {
            [void]$html.Append("<h2>Database Overview</h2>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects ($DBInfo | Sort-Object Name) -Columns @("Name","ActiveOnServer","MailboxCount","DBSizeInGB","WhiteSpaceInGB","LastFullBackup","IsMountedOnCorrectServer","Pref1Server") -RowClassRule {
                param($o)
                if ($o.Issue) { "warn" }
            }))
        }

        if ($reportConfig.ShowDatabaseCopyStatus) {
            [void]$html.Append("<h2>Database Copy Status</h2>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects ($mbcopystate | Sort-Object DBName, Server) -Columns @("DBName","Server","Status","CopyQueueLength","ReplayQueueLength") -RowClassRule {
                param($o)
                if ($o.Issue) { "warn" }
            }))
        }

        if ($reportConfig.EnableQueueCheck) {
            [void]$html.Append("<h2>Message Queues</h2>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects ($queueInfo | Sort-Object Server, Queue) -Columns @("Server","Queue","DeliveryType","MessageCount","Status") -RowClassRule {
                param($o)
                if ($o.Issue) { "warn" }
            }))
        }

        if ($reportConfig.EnableCertificateCheck) {
            [void]$html.Append("<h2>Certificates In Use</h2>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects ($certInfo | Sort-Object Server, NotAfter) -Columns @("Server","Subject","Services","NotAfter","DaysRemaining") -RowClassRule {
                param($o)
                if ($o.DaysRemaining -lt 0) { "crit" } elseif ($o.Issue) { "warn" }
            }))
        }

        if ($reportConfig.EnableServiceCheck) {
            [void]$html.Append("<h2>Exchange Services</h2>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects ($serviceInfo | Sort-Object Server, ServiceName) -Columns @("Server","ServiceName","DisplayName","Status","StartType") -RowClassRule {
                param($o)
                if ($o.Issue) { "crit" }
            }))
        }

        if ($reportConfig.ShowDriveOverview) {
            [void]$html.Append("<h2>Drive Overview</h2>")
            [void]$html.Append((ConvertTo-StyledHtmlTable -Objects ($objAllDrives | Sort-Object Server, Drive) -Columns @("Server","Drive","Size (GB)","Free (GB)","Free (%)") -RowClassRule {
                param($o)
                if ($null -ne $o."Free (%)" -and $o."Free (%)" -le $reportConfig.DriveFreePercentWarning) { "warn" }
            }))
        }
    }

    [void]$html.Append("<div class='footer'>Automatically generated by ExchangeReport.ps1 on $($env:computername)</div>")
    [void]$html.Append("</div></body></html>")

    $htmlContent = $html.ToString()
    #endregion

    #region Save HTML report to disk
    if ($reportConfig.SaveHtmlReport) {
        try {
            if (-not (Test-Path $reportConfig.HtmlReportPath)) {
                New-Item -ItemType Directory -Path $reportConfig.HtmlReportPath -Force | Out-Null
            }
            $envPart = Get-SafeFileNamePart $reportConfig.EnvironmentName
            $noWarningsSuffix = if ($reportConfig.WarningsOnly -and -not $warning) { "_NoWarnings" } else { "" }
            $reportFileName = "$(Get-Date -Format yyyyMMdd_HHmm)_$envPart$noWarningsSuffix.html"
            $reportFilePath = Join-Path -Path $reportConfig.HtmlReportPath -ChildPath $reportFileName
            $htmlContent | Set-Content -Path $reportFilePath -Encoding utf8 -ErrorAction Stop
            LogAndOutput "HTML report saved to $reportFilePath"
        }
        catch {
            LogAndOutput "HTML report could not be saved: $($_.Exception.Message)" -outcolor yellow
        }
    }
    #endregion

    #region Send mail
    if ($reportConfig.WarningsOnly -and -not $warning) {
        LogAndOutput "WarningsOnly is enabled and no warnings were found, mail was not sent."
    }
    else {
        $subject = if ($warning) { "$($reportConfig.EnvironmentName) - Exchange Report - Warning found" } else { "$($reportConfig.EnvironmentName) - Exchange Report" }

        Send-MailMessage -SmtpServer $reportConfig.SmtpServer -From $reportConfig.MailFrom -To $reportConfig.MailTo -Subject $subject `
            -Body $htmlContent -Encoding utf8 -BodyAsHtml -ErrorAction Stop

        LogAndOutput "Mail sent"
    }
    LogAndOutput "Script finished"
    #endregion

    CleanOldFiles -Path $reportConfig.LogRootPath -FileExt "*.log" -DaysToKeep $reportConfig.LogDaysToKeep
    if ($reportConfig.SaveHtmlReport) {
        CleanOldFiles -Path $reportConfig.HtmlReportPath -FileExt "*.html" -DaysToKeep $reportConfig.HtmlReportDaysToKeep
    }
}
catch {
    $errMsg = $_.Exception.Message
    Write-Host "Script aborted: $errMsg" -ForegroundColor Red
    if ($logfile) {
        LogAndOutput "Script aborted: $errMsg" -outcolor red
    }
    if ($reportConfig) {
        Send-EmergencyMail -ErrorMessage $errMsg -Config $reportConfig
    }
}
finally {
    if ($transcriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
}

#endregion
