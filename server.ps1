﻿if(${env:PORT}) {
   $url = "http://*:${env:PORT}/"
   $localUrl = "http://localhost:${env:PORT}/"
} else {
   $url = "http://*:8080/"
   $localUrl = "http://localhost:8080/"
}

$serverStopMessage = 'break-signal-e2db683c-b8ff-4c4f-8158-c44f734e2bf1'

. ./handler.ps1

$backgroundServer = Start-ThreadJob {
   param($url, $serverStopMessage)

   #prepare necessary modules on start
   install-module -name vmware.powercli -scope CurrentUser -confirm:$False -force
   connect-viserver -server 10.197.83.249 #may need username and password here
   Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
   install-module psexcel -confirm:$false -force
   Import-Module 'Microsoft.PowerShell.Utility'
   Import-Module CloudEvents.Sdk

   . ./handler.ps1

   function Start-HttpCloudEventListener {
   <#
      .DESCRIPTION
      Starts a HTTP Listener on specified Url
   #>

   [CmdletBinding()]
   param(
      [Parameter(
         Mandatory = $true,
         ValueFromPipeline = $false,
         ValueFromPipelineByPropertyName = $false)]
      [ValidateNotNull()]
      [string]
      $Url
   )

      $listener = New-Object -Type 'System.Net.HttpListener'
      $listener.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::Anonymous
      $listener.Prefixes.Add($Url)

      $cloudEvent = $null

      try {
         $listener.Start()
         $context = $listener.GetContext()

         try {
            # Read Input Stream
            $buffer = New-Object 'byte[]' -ArgumentList 1024
            $ms = New-Object 'IO.MemoryStream'
            $read = 0
            while (($read = $context.Request.InputStream.Read($buffer, 0, 1024)) -gt 0) {
               $ms.Write($buffer, 0, $read);
            }
            $bodyData = $ms.ToArray()
            $ms.Dispose()

            # Read Headers
            $headers = @{}
            for($i =0; $i -lt $context.Request.Headers.Count; $i++) {
               $headers[$context.Request.Headers.GetKey($i)] = $context.Request.Headers.GetValues($i)
            }

            $cloudEvent = ConvertFrom-HttpMessage -Headers $headers -Body $bodyData

            # function result
            ([System.Text.Encoding]::UTF8.GetString($bodyData) -eq $serverStopMessage)

            if ( $cloudEvent -ne $null ) {
               try {
                  Process-Handler -CloudEvent $cloudEvent | Out-Null
                  $context.Response.StatusCode = [int]([System.Net.HttpStatusCode]::OK)
               } catch {
                  Write-Error "$(Get-Date) - Handler Processing Error: $($_.Exception.ToString())"
                  $context.Response.StatusCode = [int]([System.Net.HttpStatusCode]::InternalServerError)
               }
            }

         } catch {
            Write-Error "`n$(Get-Date) - HTTP Request Processing Error: $($_.Exception.ToString())"
            $context.Response.StatusCode = [int]([System.Net.HttpStatusCode]::InternalServerError)
         } finally {
            $context.Response.Close();
         }

      } catch {
         Write-Error "$(Get-Date) - Listener Processing Error: $($_.Exception.ToString())"
         exit 1
      } finally {
         $listener.Stop()
      }
   }

   # Runs Init function (defined in handler.ps1) which can be used to enable warm startup
   try {
      Process-Init
   } catch {
      Write-Error "$(Get-Date) - Init Processing Error: $($_.Exception.ToString())"
      exit 1
   }

   while($true) {
      $breakSignal = Start-HttpCloudEventListener -Url $url
      if ($breakSignal) {
         Write-Host "$(Get-Date) - PowerShell HTTP server stop requested"
         break;
      }
   }
} -ArgumentList $url, $serverStopMessage

$killEvent = new-object 'System.Threading.AutoResetEvent' -ArgumentList $false

$serverTerminateJob = Start-ThreadJob {
param($killEvent, $url, $serverStopMessage)
   $killEvent.WaitOne() | Out-Null
   Invoke-WebRequest -Uri $url -Body $serverStopMessage | Out-Null
} -ArgumentList $killEvent, $localUrl, $serverStopMessage

try {
   Write-Host "$(Get-Date) - Verne's PowerShell HTTP server start listening on '$url'"
   $running = $true
   while($running) {
      Start-Sleep  -Milliseconds 100
      $running = ($backgroundServer.State -eq 'Running')
      $backgroundServer = $backgroundServer | Get-Job
      $backgroundServer | Receive-Job
   }
} finally {
   Write-Host "$(Get-Date) - PowerShell HTTP Server stop requested. Waiting for server to stop"
   $killEvent.Set() | Out-Null
   Get-Job | Wait-Job | Receive-Job
   Write-Host "$(Get-Date) - PowerShell HTTP server is stopped"

   # Runs Shutdown function (defined in handler.ps1) to clean up connections from warm startup
   try {
      Process-Shutdown
   } catch {
      Write-Error "`n$(Get-Date) - Shutdown Processing Error: $($_.Exception.ToString())"
   }
}