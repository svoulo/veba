Function Process-Init {
   [CmdletBinding()]
   param()
   Write-Host "$(Get-Date) - Processing Init`n"

   Write-Host "$(Get-Date) - Init Processing Completed`n"
}

Function Process-Shutdown {
   [CmdletBinding()]
   param()
   Write-Host "$(Get-Date) - Processing Shutdown`n"

   Write-Host "$(Get-Date) - Shutdown Processing Completed`n"
}

Function Process-Handler {
   [CmdletBinding()]
   param(
      [Parameter(Position=0,Mandatory=$true)][CloudNative.CloudEvents.CloudEvent]$CloudEvent
   )

 #  Write-Host $(Get-Date) - "Cloud Event"
 # Write-Host $(Get-Date) - "  Source: $($cloudEvent.Source)"
   Write-Host $(Get-Date) - "  Subject: $($cloudEvent.Subject)"
#   Write-Host $(Get-Date) - "  Type: $($cloudEvent.Type)"
#   Write-Host $(Get-Date) - "  EventClass: $($cloudEvent.EventClass)"
#   Write-Host $(Get-Date) - "  Id: $($cloudEvent.Id)"

   $subject = ($CloudEvent.Subject)

   # Decode CloudEvent
   try {
      $cloudEventData = $cloudEvent | Read-CloudEventJsonData -Depth 10
   } catch {
      throw "`nPayload must be JSON encoded"
   }

 #  Write-Host $(Get-Date) - "CloudEvent Data:"
   Write-Host $(Get-Date) - "`n$($cloudEventData | ConvertTo-Json)"
#   Write-Host $cloudEventData

      If ($subject -eq "com.vmware.vc.vm.VmStateReverted") {

#vmcheck must get vmname from cloud event details $cloudeventdata
$vmstart = ($cloudEventData.Vm.Name)

$vmcheck = get-vm $vmstart
$neta = Get-NetworkAdapter -vm $vmstart -name "Network Adapter 1" 
$netn = $neta.networkname
write-host "Detected VM Revert Event on VM: $vmstart  Current Networkname: $netn"

#remark out next line when not testing
#$netn=$null

#check if currentnet is null
if ($netn -eq $null) {

Write-host "Current Network is null, do crosscheck"

#set network adapter lookup file
$file = "\\VBAUMAN-7820\rcos\rconetlookup\rconetlookup.xlsx"

#import-module psexcel
$vm = new-object System.Collections.ArrayList

foreach ($vmnamelook in (Import-XLSX -Path $file -RowStart 1)) {
$vm.add($vmnamelook) | out-null
$vmset = ($vmnamelook.vm)
if (($vmset) -eq $vmstart) {

$net = ($vmnamelook.network)
write-host "Setting VM: $vmset to network: $net"
#$vmname = get-vm $vmstart  
#$neta = Get-NetworkAdapter -vm $vmstart -name "Network Adapter 1" 
$vmpower = ($vmcheck.PowerState)

if ($vmpower -eq "PoweredOn") {
Set-NetworkAdapter -networkadapter $neta -networkname $net -connected:$true -Confirm:$false
break
} else {
Set-NetworkAdapter -networkadapter $neta -networkname $net -Confirm:$false
break
}
 } 
  }
   }
}}
#Disconnect-VIServer -Server 10.197.83.249 -confirm:$false