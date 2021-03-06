# Script to fix OneView expired certificate msg: "Delete the expired certificate from OneView, regenerate a new certificate and add the new certificate to OneView with the same alias name."
#
# Useful to generate a new certificate in iLO4 v2.55 when the iLO certificate is expired
# In iLO 2.55, renaming the iLO name + reset does not generate a new certificate in iLO
#
# To learn more, refer to this CA:
# https://support.hpe.com/hpsc/doc/public/display?docId=emr_na-c03743622
#
# This script is using 'RefreshFailed' status in Server Hardware to select the impacted servers and then it collects their iLO IP addresses
#
# Requires the HP iLO Cmdlets for Windows PowerShell (HPiLOCmdlets library), see https://www.hpe.com/us/en/product-catalog/detail/pip.5440657.html 
#
# When the script execution is complete, it is necessary to import in OneView the new iLO certificate using the iLO IP address (From Settings > Security > Manage Certificate page)



# OneView Credentials and IP
$username = "Administrator" 
$password = "password" 
$IP = "192.168.1.110" 


#Loading HPiLOCmdlets module
Try
{
    Import-Module HPiLOCmdlets -ErrorAction stop
}

Catch 

{
    Write-Host "`nHPiLOCmdlets module cannot be loaded"
    write-host "It is necessary to install the HPE iLO Cmdlets for Windows PowerShell (HPiLOCmdlets library)"
    write-host "See http://www.hpe.com/servers/powershell" 
    Write-Host "Exit..."
    exit
    }


    $InstallediLOModule  =  Get-Module -Name "HPiLOCmdlets"
    Write-Host "`nHPiLOCmdlets Module Version : $($InstallediLOModule.Version) is installed on your machine."




#Loading OneView 3.10 module

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

    if (-not (get-module HPOneview.310)) 
    {  
    Import-module HPOneview.310
    }

   
$PWord = ConvertTo-SecureString –String $password –AsPlainText -Force
$cred = New-Object –TypeName System.Management.Automation.PSCredential –ArgumentList $Username, $PWord


#Connecting to the Synergy Composer

if ($connectedSessions -and ($connectedSessions | ?{$_.name -eq $IP}))
{
    Write-Verbose "Already connected to $IP."
}

else
{
    Try 
    {
        Connect-HPOVMgmt -appliance $IP -PSCredential $cred | Out-Null
    }
    Catch 
    {
        throw $_
    }
}

               
import-HPOVSSLCertificate -ApplianceConnection ($connectedSessions | ?{$_.name -eq $IP})



#Capturing iLO IP adresses managed by OneView
$iloIPs = Get-HPOVServer | ? refreshState -Match "RefreshFailed" | where mpModel -eq iLO4 | % {$_.mpHostInfo.mpIpAddresses[1].address }


#Proceeding factory Reset
Foreach ($iloIP in $iLOIPs)
{
   Try 
   { 
        Set-HPiLOFactoryDefault -Force -Password password -Server $iloIP -Username demopaq -DisableCertificateAuthentication
    }
   Catch
   {
        write-host " Factory reset Error for iLO : $iloIP"
   }

}

write-host "`nYou can now import the new iLO certificate of each iLO in OneView using the iLO IP address from Settings > Security > Manage Certificate page"

