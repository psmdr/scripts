
<# .SYNOPSIS
This script is used to place a Exchange 2016 Server in maintenance mode. It must be run on an exchange server and will allways use the local ExchangeServer

.DESCRIPTION


.NOTES
Written by max droege


#>


#load exchange powershell

         if (!$exscripts)
            {

                . "$($env:ExchangeInstallPath)\bin\RemoteExchange.ps1"

                Connect-ExchangeServer -auto -ClientApplication:ManagementShell
            }

        Set-AdServerSettings -ViewEntireForest $true

#set location
Set-Location $PSScriptRoot

$transcriptfile = "$(get-date -format yyMMdd)-StartMaintenanceTranscript.txt"
Start-Transcript -Path $transcriptfile




try
    {
        $ExchServer = Get-ExchangeServer -Identity $env:COMPUTERNAME -ErrorAction stop
    }
catch
    {
        write-host "$($server) is not a Exchange Server"  -ForegroundColor Red
        break
    }

$start = (get-date)


#get the dag name, we need it later
#$dag = Get-DatabaseAvailabilityGroup -Identity (((get-mailboxserver -id $ExchServer[0].name).DatabaseAvailabilityGroup).name)
$dag = Get-DatabaseAvailabilityGroup -Identity (get-mailboxserver -id $ExchServer.name).DatabaseAvailabilityGroup

#we need to define "other" servers, cause we need to move stuff around later
$targets = @()
#$comp = compare ($dag.servers.name)($Exchserver.name) | foreach {$targets += $_.inputobject}
$comp = compare ($dag.servers)($Exchserver.name) | foreach {$targets += $_.inputobject}

$target = Get-Random $targets


write-host "going to put server $($ExchServer.name) in maintenance. Mails and roles will be moved to $($target.name). We started at $($start). "
  
write-host "Moving Away Databases..."
Set-MailboxServer $exchServer.name -DatabaseCopyActivationDisabledAndMoveNow $True

write-host "Set Transport to drain ..."

Set-ServerComponentState -Identity $exchServer.name -Component HubTransport -State Draining -Requester Maintenance

write-host "Restart Transport Services..."

Restart-Service -Name MsExchangeTransport

write-host "Redirect Messages..."

Redirect-Message -Server $exchServer.name -Target (Get-ExchangeServer -id $target).fqdn -Confirm:$false

#check the queue until empty

write-host "Check the queues..."


do {
    $MessageCount = Get-Queue -Server $exchserver.name | ?{$_.Identity -notlike "*\Poison" -and $_.Identity -notlike"*\Shadow\*"} | Select MessageCount
    $count = 0
    foreach ($message in $MessageCount)
        {
            $count += $message.MessageCount
        }
    write-host "Queue MessageCount is $($count)"

    
    }
until ($count -eq 0)


write-host "check if server is pam..."


#is server the pam?
$pam = (Get-DatabaseAvailabilityGroup -id $dag.name -Status).PrimaryActiveManager

#command to move the pam


        if ($pam.Name -eq $exchServer.name)
            {
                Move-ClusterGroup -name "Cluster Group" -Node $target
            } 

write-host "check db state..."


#Check DB State


do
    {
        $copys = @(Get-MailboxDatabaseCopyStatus -Server $exchServer.Name)
        $healthy = $copys | where {$_.Status -Like "Healthy"}
        $unhealthy = $copys | where {$_.Status -NotLike "Mounted" -and $_.status -notlike "Healthy"}
        $mounted = $copys | where {$_.status -like "Mounted"}
        Write-Host "$($exchServer.name): Databases $($copys.count) Mounted $($mounted.count) Healthy $($healthy.count) NotHealthy $($unhealthy.count)"
        
        if ($mounted.count -ne 0 -or $unhealthy.count -ne 0) {Start-sleep -Seconds 30}

    }
until ($mounted.count -eq 0 -and $unhealthy.count -eq 0)






#lets turn things off

write-host "Lets Disable things..."

write-host "Disable FrontEnd Receive Connectors..."

        Get-ReceiveConnector -Server $ExchServer.name | where {$_.TransportRole -like "FrontendTransport"} | Set-ReceiveConnector -Enabled $false

write-host "Setting DatabaseCopyAutoActivationPolicy Blocked.."

        Set-MailboxServer $exchServer.name -DatabaseCopyAutoActivationPolicy Blocked


write-host "Setting Serverwideoffline ..."

        Set-ServerComponentState $exchServer.name -Component ServerWideOffline -State Inactive -Requester Maintenance



write-host "Suspending Clusternode ..."


        Suspend-ClusterNode -Name $exchServer.name | fl name,state

$stop = get-date

write-host "server is ready for maintenance at $($stop)"


Stop-Transcript





