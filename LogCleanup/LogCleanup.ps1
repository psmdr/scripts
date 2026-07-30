<#
.SYNOPSIS
LogCleanup.ps1 - Remove outdated IIS, Exchange IMAP/POP, and custom log files.

.DESCRIPTION
Deletes log files older than a specified number of days. Supports well-known log types
(IIS, Exchange IMAP4, Exchange POP3) as well as any number of additional custom paths
via -CustomPath. Multiple log types can be combined in a single run.

The script can also register itself as a Scheduled Task (-InstallTask), list existing
tasks (-ListTasks), or remove them (-RemoveTask). Multiple independent tasks can be
created with different parameters and run times (e.g. one task for IIS+IMAP at 03:00,
a second task for POP only at 04:30).

.PARAMETER IIS
Cleans IIS logs (default path: $env:SystemDrive\inetpub\logs\LogFiles,
overridable via -IISPath).

.PARAMETER IMAP
Cleans Exchange IMAP4 logs. The path is detected automatically from the local Exchange
installation (registry), but can be overridden via -ImapPath.

.PARAMETER POP
Cleans Exchange POP3 logs. The path is detected automatically from the local Exchange
installation (registry), but can be overridden via -PopPath.

.PARAMETER CustomPath
One or more additional directories to clean using the same pattern (*.log, older than
-DaysToKeep). Provide multiple paths as a comma-separated list, e.g.
-CustomPath "D:\Logs\AppX","E:\Logs\AppY".

.PARAMETER IISPath
Optional override for the IIS log path (instead of the default path).

.PARAMETER ImapPath
Optional override for the IMAP4 log path (instead of the auto-detected path).

.PARAMETER PopPath
Optional override for the POP3 log path (instead of the auto-detected path).

.PARAMETER DaysToKeep
Number of days to retain log files. Applies globally to ALL log types selected in this
run (IIS/IMAP/POP/Custom). Default: 30.

.PARAMETER InstallTask
Registers a Scheduled Task that runs this script with the current parameter set on a
recurring schedule.

IMPORTANT: The Scheduled Task stores the file path from which -InstallTask was called
($PSCommandPath). The script should therefore reside in a permanent location
(e.g. C:\Scripts\LogCleanup.ps1) before a task is created. If the file is later moved
or deleted, the scheduled run will fail. The script warns if it is called from an obvious
temporary or download location, but cannot detect every case. This warning is also
documented in the built-in help (-Full).

.PARAMETER TaskName
Name of the Scheduled Task. If omitted, the name is derived automatically from the
selected log types (e.g. "LogCleanup_IIS_IMAP"). Using different names allows multiple
independent tasks with different parameters and run times.

.PARAMETER TaskTime
Time of day (format HH:mm) at which the Scheduled Task runs daily. Default: 03:00.

.PARAMETER TaskUser
Optional: user account under which the task runs (e.g. "DOMAIN\svc-logcleanup").
If omitted, the task runs as the local SYSTEM account. When a user account is specified,
the password is prompted interactively and held in memory only briefly; it is never
stored in the script or the task definition.

.PARAMETER Force
When used with -InstallTask: overwrites an existing task with the same name without
prompting. Without -Force, the script aborts with a warning on a name collision.

.PARAMETER ListTasks
Lists all Scheduled Tasks created by this script (folder \LogCleanup\), including
their state and next run time.

.PARAMETER RemoveTask
Removes the specified Scheduled Task (use the name shown by -ListTasks or -TaskName).

.EXAMPLE
.\LogCleanup.ps1 -IIS -DaysToKeep 14 -WhatIf
Shows which IIS logs older than 14 days would be deleted, without actually deleting anything.

.EXAMPLE
.\LogCleanup.ps1 -IIS -IMAP -POP -DaysToKeep 30
Deletes IIS, IMAP, and POP logs older than 30 days in a single run.

.EXAMPLE
.\LogCleanup.ps1 -CustomPath "D:\Logs\AppX","E:\Logs\AppY" -DaysToKeep 7
Deletes logs from two additional custom directories.

.EXAMPLE
.\LogCleanup.ps1 -InstallTask -IIS -IMAP -DaysToKeep 30 -TaskTime "03:00"
Creates a daily Scheduled Task "LogCleanup_IIS_IMAP" running as SYSTEM at 03:00.

.EXAMPLE
.\LogCleanup.ps1 -InstallTask -POP -DaysToKeep 14 -TaskTime "04:30" -TaskName "POP_Nightly" -TaskUser "DOMAIN\svc-logcleanup"
Creates a second independent task under a service account; password is prompted interactively.

.EXAMPLE
.\LogCleanup.ps1 -ListTasks
Lists all Scheduled Tasks created by this script in the \LogCleanup\ folder.

.EXAMPLE
.\LogCleanup.ps1 -RemoveTask "POP_Nightly"
Removes the task named "POP_Nightly".

.NOTES
History:
- Original version: IIS-only log cleanup (-LogPath/-DaysToKeep) by Max Droege,
  based on a script by Paul Cunningham.
- Revised: multiple log types (IIS/IMAP/POP/Custom) combinable in one run, global
  -DaysToKeep, -WhatIf support, proper error handling via try/catch instead of the
  global $error array, Scheduled Task management (Install/List/Remove) with
  administrator privilege check and name-collision detection.

Requirements: PowerShell module "ScheduledTasks" (included with Windows Server 2012 R2 /
Windows 8.1 and later) for -InstallTask / -ListTasks / -RemoveTask.
For IMAP/POP, the Exchange installation path is read from the registry
(v14 = Exchange 2010, v15 = Exchange 2013/2016/2019).
#>

[CmdletBinding(SupportsShouldProcess = $true)]
Param(
    [switch]$IIS,
    [switch]$IMAP,
    [switch]$POP,
    [string[]]$CustomPath,

    [string]$IISPath,
    [string]$ImapPath,
    [string]$PopPath,

    [int]$DaysToKeep = 30,

    [switch]$InstallTask,
    [string]$TaskName,
    [string]$TaskTime = "03:00",
    [string]$TaskUser,
    [switch]$Force,

    [switch]$ListTasks,
    [string]$RemoveTask
)

#region Helper functions

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ExchangeInstallPath {
    # v15 = Exchange 2013/2016/2019, v14 = Exchange 2010
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\ExchangeServer\v15\Setup",
        "HKLM:\SOFTWARE\Microsoft\ExchangeServer\v14\Setup"
    )
    foreach ($regPath in $regPaths) {
        $value = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).MsiInstallPath
        if ($value) { return $value }
    }
    return $null
}

function Invoke-LogCleanup {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Filter,
        [int]$DaysToKeep
    )

    $result = [PSCustomObject]@{
        Name    = $Name
        Path    = $Path
        Found   = 0
        Deleted = 0
        Errors  = 0
        Skipped = $false
        Message = ""
    }

    if (-not $Path) {
        $result.Skipped = $true
        $result.Message = "No path resolved or specified"
        return $result
    }

    if (-not (Test-Path -Path $Path)) {
        $result.Skipped = $true
        $result.Message = "Path not found: $Path"
        return $result
    }

    $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
    $files = Get-ChildItem -Path $Path -Recurse -Include $Filter -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoffDate }

    $result.Found = $files.Count

    foreach ($file in $files) {
        try {
            # -WhatIf is inherited automatically via $WhatIfPreference from the script scope,
            # because Remove-Item natively supports ShouldProcess.
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            $result.Deleted++
        }
        catch {
            $result.Errors++
            Write-Warning "Could not delete file: $($file.FullName) - $($_.Exception.Message)"
        }
    }

    return $result
}

#endregion

#region Constants

$TaskFolder = "\LogCleanup\"

#endregion

#region Scheduled Task management: List / Remove / Install

if ($ListTasks) {
    $tasks = Get-ScheduledTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue
    if (-not $tasks) {
        Write-Host "No tasks found in folder $TaskFolder."
        return
    }
    $tasks | ForEach-Object {
        $info = Get-ScheduledTaskInfo -InputObject $_
        [PSCustomObject]@{
            TaskName    = $_.TaskName
            State       = $_.State
            NextRunTime = $info.NextRunTime
            LastResult  = $info.LastTaskResult
        }
    } | Format-Table -AutoSize
    return
}

if ($RemoveTask) {
    if (-not (Test-IsAdmin)) {
        Write-Error "Removing a Scheduled Task requires administrator privileges."
        return
    }
    $existing = Get-ScheduledTask -TaskName $RemoveTask -TaskPath $TaskFolder -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-Warning "Task '$RemoveTask' was not found in folder $TaskFolder."
        return
    }
    Unregister-ScheduledTask -TaskName $RemoveTask -TaskPath $TaskFolder -Confirm:$false
    Write-Host "Task '$RemoveTask' has been removed."
    return
}

if ($InstallTask) {
    if (-not (Test-IsAdmin)) {
        Write-Error "Creating a Scheduled Task requires administrator privileges. Please run PowerShell as Administrator."
        return
    }

    if (-not $TaskName) {
        $parts = @()
        if ($IIS)        { $parts += "IIS" }
        if ($IMAP)       { $parts += "IMAP" }
        if ($POP)        { $parts += "POP" }
        if ($CustomPath) { $parts += "Custom" }
        if ($parts.Count -eq 0) {
            Write-Error "Please specify at least one log type (-IIS, -IMAP, -POP, and/or -CustomPath)."
            return
        }
        $TaskName = "LogCleanup_" + ($parts -join "_")
    }

    $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue
    if ($existingTask -and -not $Force) {
        Write-Warning "A task named '$TaskName' already exists in $TaskFolder. Use -TaskName to choose a different name, or -Force to overwrite."
        return
    }

    $ScriptPath = $PSCommandPath
    if (-not $ScriptPath) {
        Write-Error "The script must be run as a .ps1 file to register a Scheduled Task."
        return
    }
    if ($ScriptPath -match "\\Temp\\|\\Downloads\\|AppData\\Local\\Temp") {
        Write-Warning "The script is currently located at '$ScriptPath'. For a stable Scheduled Task it should reside in a permanent location (e.g. C:\Scripts\), because the task will reference exactly this path."
    }

    $argList = @("-NoProfile", "-ExecutionPolicy Bypass", "-File `"$ScriptPath`"")
    if ($IIS)      { $argList += "-IIS" }
    if ($IMAP)     { $argList += "-IMAP" }
    if ($POP)      { $argList += "-POP" }
    if ($IISPath)  { $argList += "-IISPath `"$IISPath`"" }
    if ($ImapPath) { $argList += "-ImapPath `"$ImapPath`"" }
    if ($PopPath)  { $argList += "-PopPath `"$PopPath`"" }
    if ($CustomPath) {
        $customPathsString = ($CustomPath | ForEach-Object { "'$_'" }) -join ","
        $argList += "-CustomPath $customPathsString"
    }
    $argList += "-DaysToKeep $DaysToKeep"
    $argumentString = $argList -join " "

    $action      = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentString
    $triggerTime = [datetime]::ParseExact($TaskTime, "HH:mm", $null)
    $trigger     = New-ScheduledTaskTrigger -Daily -At $triggerTime

    if ($TaskUser) {
        $cred = Get-Credential -UserName $TaskUser -Message "Enter the password for Scheduled Task account '$TaskUser'"
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($cred.Password)
        try {
            $plainPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
            Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Action $action -Trigger $trigger `
                -User $TaskUser -Password $plainPwd -RunLevel Highest -Force | Out-Null
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($bstr)
            Remove-Variable plainPwd -ErrorAction SilentlyContinue
        }
    }
    else {
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskFolder -Action $action -Trigger $trigger `
            -Principal $principal -Force | Out-Null
    }

    Write-Host "Scheduled Task '$TaskName' has been created in $TaskFolder (daily at $TaskTime)."
    return
}

#endregion

#region Log cleanup

$ExchangeInstallPath = Get-ExchangeInstallPath

if (-not $IISPath)                            { $IISPath  = "$env:SystemDrive\inetpub\logs\LogFiles" }
if (-not $ImapPath -and $ExchangeInstallPath) { $ImapPath = Join-Path $ExchangeInstallPath "Logging\Imap4" }
if (-not $PopPath  -and $ExchangeInstallPath) { $PopPath  = Join-Path $ExchangeInstallPath "Logging\Pop3" }

$jobs = @()
if ($IIS)  { $jobs += [PSCustomObject]@{ Name = "IIS";  Path = $IISPath;  Filter = "*.log" } }
if ($IMAP) { $jobs += [PSCustomObject]@{ Name = "IMAP"; Path = $ImapPath; Filter = "*.log" } }
if ($POP)  { $jobs += [PSCustomObject]@{ Name = "POP";  Path = $PopPath;  Filter = "*.log" } }
foreach ($cp in $CustomPath) {
    $jobs += [PSCustomObject]@{ Name = "Custom: $cp"; Path = $cp; Filter = "*.log" }
}

if ($jobs.Count -eq 0) {
    Write-Warning "No log type selected. Please specify -IIS, -IMAP, -POP, and/or -CustomPath (or use -InstallTask / -ListTasks / -RemoveTask). See: Get-Help .\LogCleanup.ps1 -Full"
    return
}

if ($WhatIfPreference) {
    Write-Host "WhatIf mode active: nothing will be deleted. 'Deleted' shows what would be removed." -ForegroundColor Cyan
}

Write-Host "Cleanup started. DaysToKeep = $DaysToKeep"

$results = foreach ($job in $jobs) {
    Invoke-LogCleanup -Name $job.Name -Path $job.Path -Filter $job.Filter -DaysToKeep $DaysToKeep
}

$results | Format-Table Name, Path, Found, Deleted, Errors, Skipped, Message -AutoSize

$totalFound   = ($results | Measure-Object -Property Found   -Sum).Sum
$totalDeleted = ($results | Measure-Object -Property Deleted -Sum).Sum
$totalErrors  = ($results | Measure-Object -Property Errors  -Sum).Sum

Write-Host "Total: $totalFound found, $totalDeleted deleted, $totalErrors errors."

#endregion
