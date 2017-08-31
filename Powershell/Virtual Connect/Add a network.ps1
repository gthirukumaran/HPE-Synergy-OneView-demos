# -------------------------------------------------------------------------------------------------------
#   by lionel.jullien@hpe.com
#   June 2016
#
#   This PowerShell script adds a network resource to a Synergy environment and presents this network to all Compute Modules using a Network Set.    
#   The network name generated by the script in OneView/Virtual Connect is always a `prefixname`+`VLAN ID` like `Production-400`.   
#   The script also adds the network resource to the LIG uplinkset and to the network set present in OneView.       
#  
#   This script can be used in conjunction with 'Remove a network.ps1". See https://github.com/jullienl/HPE-Synergy-OneView-demos/blob/master/Powershell/Virtual Connect/Remove a network.ps1
#
#   With this script, you can demonstrate that with a single line of code, you can present easily and quickly a network VLAN to all Compute Modules present in the Synergy frames managed by HPE OneView. 
#        
#   OneView administrator account is required. Global variables (i.e. OneView details, LIG, UplinkSet, Network Set names, etc.) must be modified with your own environment information.
# 
# --------------------------------------------------------------------------------------------------------
   
#################################################################################
#        (C) Copyright 2017 Hewlett Packard Enterprise Development LP           #
#################################################################################
#                                                                               #
# Permission is hereby granted, free of charge, to any person obtaining a copy  #
# of this software and associated documentation files (the "Software"), to deal #
# in the Software without restriction, including without limitation the rights  #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell     #
# copies of the Software, and to permit persons to whom the Software is         #
# furnished to do so, subject to the following conditions:                      #
#                                                                               #
# The above copyright notice and this permission notice shall be included in    #
# all copies or substantial portions of the Software.                           #
#                                                                               #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR    #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,      #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE   #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER        #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, #
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN     #
# THE SOFTWARE.                                                                 #
#                                                                               #
#################################################################################



#################################################################################
#                                Global Variables                               #
#################################################################################

$LIG="LIG-MLAG"
$Uplinkset="M-LAG-Comware"
$Networkprefix="Production-"
$NetworkSet="Production Networks"


# OneView Credentials and IP
$username = "Administrator" 
$password = "password" 
$IP = "192.168.1.110" 


# Importing the OneView 3.10 library

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

    if (-not (get-module HPOneview.310)) 
    {  
    Import-module HPOneview.310
    }

   
$PWord = ConvertTo-SecureString –String $password –AsPlainText -Force
$cred = New-Object –TypeName System.Management.Automation.PSCredential –ArgumentList $Username, $PWord


# Connection to the Synergy Composer

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
clear-host


#################################################################################
#                     Creating a new Network resource                          #
#################################################################################



$networks = Get-HPOVNetwork -type Ethernet | where {$_.Name -match $Networkprefix} | % {$_.name}

if ($networks -eq $Null)

{

write-host "`nThere is no network using the prefix: " -NoNewline
Write-host -f Cyan $networkprefix -NoNewline
Write-host "* available in Oneview"

}

if ($networks.count -lt 2)

{

write-host "`nThe following: " -NoNewline
Write-host -f Cyan $networkprefix -NoNewline
Write-host "* network is available in OneView:`n"

Get-HPOVNetwork -type Ethernet  | where {$_.Name -match $Networkprefix} | Select-Object @{Name="Network name";Expression={$_.Name}}, @{Name="VLAN ID";Expression={$_.vlanid}} | Out-Host

}

if ($networks.count -gt 1)

{

write-host "`nThe following: " -NoNewline
Write-host -f Cyan $networkprefix -NoNewline
Write-host "* networks are available in OneView:`n"

Get-HPOVNetwork -type Ethernet  | where {$_.Name -match $Networkprefix} | Select-Object @{Name="Network name";Expression={$_.Name}}, @{Name="VLAN ID";Expression={$_.vlanid}}  | Out-Host

}


$VLAN = Read-Host "`n`nEnter the VLAN ID you want to add" 

Write-host "`nCreating a Network: " -NoNewline
Write-host -f Cyan ($networkprefix + $VLAN) -NoNewline
Write-host " in OneView" 

try {
    New-HPOVNetwork -Name ($networkprefix + $VLAN) -type Ethernet -vlanID "$VLAN" -VLANType "Tagged" -purpose General -typicalBandwidth 2500 -maximumBandwidth 10000 -ErrorAction Stop | Out-Null
    }
catch [exception]
    { 
    echo $_
    return
    }


#################################################################################
#                       Adding Network to LIG Uplink Set                        #
#################################################################################



Write-host "`nAdding Network: " -NoNewline
Write-host -f Cyan ($networkprefix + $VLAN) -NoNewline
Write-host " to Logical Interconnect Group: " -NoNewline
Write-host -f Cyan $LIG


$Mylig = Get-HPOVLogicalInterconnectGroup -Name $LIG 
$uplink_set = $Mylig.uplinkSets | where-Object {$_.name -eq $uplinkset} 
$uplink_Set.networkUris += (Get-HPOVNetwork -Name ($networkprefix + $VLAN)).uri

try {
    Set-HPOVResource $Mylig -ErrorAction Stop | Wait-HPOVTaskComplete | Out-Null
    }
catch
    {
    echo $_ #.Exception
    }


#################################################################################
#                            Updating LI from LIG                               #
#################################################################################

# This steps takes time (average 5mn for 3 frames) so we don't wait for the LI update to be completed, once the network is detected in the uplinkset we continue
$Updating = Read-Host "`n`nDo you want to apply the new LIG configuration to the Synergy frames [y] or [n] ?" 

$vlanuri = (Get-HPOVNetwork -Name ($networkprefix + $VLAN)).uri

if ($Updating -eq "y")
    {
    
        Write-host "`nUpdating all Logical Interconnects from the Logical Interconnect Group: " -NoNewline
        Write-host -f Cyan $LIG

        try {
            Get-HPOVLogicalInterconnect | Update-HPOVLogicalInterconnect -confirm:$false -ErrorAction Stop| Out-Null  #| Wait-HPOVTaskComplete | Out-Null
            }
        catch
            {
            echo $_ #.Exception
            }
    

        do  {
                $uplinksetnew= (Get-HPOVUplinkSet -Name $uplinkset).networkUris  | where { $_ -eq $vlanuri }  
            } 
        until ($uplinksetnew -eq $vlanuri)

    }
else
    {
    write-warning "The Logical Interconnects will be marked in OneView as inconsistent with the logical interconnect group: $LIG"
    }


#################################################################################
#                       Adding Network to Network Set                           #
#################################################################################



Write-host "`nAdding Network: " -NoNewline
Write-host -f Cyan ($networkprefix + $VLAN) -NoNewline
Write-host " to NetworkSet: " -NoNewline
Write-host -f Cyan $networkset



$netset = Get-HPOVNetworkSet -Name $NetworkSet
$netset.networkUris += (Get-HPOVNetwork -Name Production-$VLAN).uri


try
    {
    Set-HPOVNetworkSet $netset -ErrorAction Stop | Wait-HPOVTaskComplete | Out-Null
    }
catch
    {
    echo $_
    }


if  ((Get-HPOVLogicalInterconnect).consistencyStatus -eq "consistent" -and $Updating -eq "y")   # Get-HPOVNetworkSet -Name $NetworkSet).networkUris  -ccontains $vlanuri

    {
    Write-host "`nThe network VLAN ID: " -NoNewline
    Write-host -f Cyan $vlan -NoNewline
    Write-host " has been successfully added and presented to all server profiles that are using the Network Set: " -NoNewline
    Write-host -f Cyan $networkset 
    Write-host ""
    return
    }

if ($Updating -eq "n" -and ((Get-HPOVNetworkSet -Name $NetworkSet).networkUris  -ccontains $vlanuri))
    {
    Write-host "`nThe network VLAN ID: " -NoNewline
    Write-host -f Cyan $vlan -NoNewline
    Write-host " has been added successfully to all Server Profiles that are using the Network Set: " -NoNewline
    Write-host -f Cyan $networkset 
    Write-host "but the Virtual Connect Module(s) have not been configured yet`n" -NoNewline
    return
    }

if ((Get-HPOVNetworkSet -Name $NetworkSet).networkUris  -notcontains $vlanuri)
    {
    Write-Warning "`nThe network VLAN ID: $vlan has NOT been added successfully, check the status of your Logical Interconnect resource`n" 
    }
