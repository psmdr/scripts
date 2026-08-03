


<# .SYNOPSIS
This script is used to stop exchange maintenance mode. It must be run on an exchange server and will allways use the local exchagneserver

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
  

$transcriptfile = "$(get-date -format yyMMdd)-StopMaintenanceTranscript.txt"
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

write-host "Lets stop Maintenance Mode for server $($ExchServer.name) at $($start)"


#Get-HealthReport -Identity $ExchServer.name | where {$_.AlertValue -notlike "Healthy"}

write-host "Let's check the databases ..."


do
    {
        $copys = @(Get-MailboxDatabaseCopyStatus -Server $exchServer.Name)
        $healthy = $copys | where {$_.Status -Like "Healthy"}
        $unhealthy = $copys | where {$_.Status -NotLike "Mounted" -and $_.status -notlike "Healthy"}
        $mounted = $copys | where {$_.status -like "Mounted"}
        Write-Host "$($exchServer.name): Databases $($copys.count) Mounted $($mounted.count) Healthy $($healthy.count) NotHealthy $($unhealthy.count)"
        
        if ($unhealthy.count -ne 0) {Start-sleep -Seconds 30}

    }
until ($unhealthy.count -eq 0)



write-host "Now that DBs are ok, we reenbable everything ..."

write-host "Enable Front End Receive Connectors ..."

        Get-ReceiveConnector -Server $ExchServer.name | where {$_.TransportRole -like "FrontendTransport"} | Set-ReceiveConnector -Enabled $True



write-host "setting DatabaseCopyActivationDisabledAndMoveNow to False ..."


Set-MailboxServer $ExchServer.name -DatabaseCopyActivationDisabledAndMoveNow $False


write-host "Setting ComponentStates active and restart ExchangeTransoprt Service ..."


Set-ServerComponentState -Identity $ExchServer.name -Component HubTransport -State Active -Requester Maintenance


Restart-Service -Name MsExchangeTransport


Set-ServerComponentState $ExchServer.name -Component ServerWideOffline  -Requester Maintenance -state Active


#Get-ServerComponentState -Identity $ExchServer.name | where {$_.state -notlike "Active"}

write-host "setting DatabaseCopyAutoActivationPolicy to Unrestricted ..."


Set-MailboxServer $ExchServer.name -DatabaseCopyAutoActivationPolicy Unrestricted

write-host "Resume Clusternode ..."


Resume-ClusterNode -Name $ExchServer.name


$stop = get-date

write-host "server is out of maintenance at $($stop)"


Stop-Transcript








