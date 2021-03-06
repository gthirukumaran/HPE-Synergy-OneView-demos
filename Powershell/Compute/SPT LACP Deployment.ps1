<#
# In OneView 4.1, adding LAG configuration in a Server Profile Template, does not turn the associated Server profile(s) 
# as inconsistent therefore it is required to update all Server Profiles manually with LAG. To avoid that, this script can be used to 
# deploy automatically the LAG configuration present in the Server Profile Template to all associated server profiles.
#
# During the execution, the script displays a list of Server Profile Templates available in OneView and then ask the name of 
# the Server Profile Template that you want to use to propagate the LACP configuration across all associated server profiles.  
# 
# Notice: the script verifies that the same network connections present in Server profile template are also available in the server profiles 
# 
#  Author: lionel.jullien@hpe.com
#  Date:   November 2018
#    
#################################################################################
#                         SPT LACP Deployment.ps1                       #
#                                                                               #
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
#>


# MyImport-Module HPRESTCmdlets


# OneView Credentials and IP
$username = "Administrator" 
$password = "password" 
$IP = "192.168.1.110" 


Function MyImport-Module {
    
    # Import a module that can be imported
    # If it cannot, the module is installed
    # When -update parameter is used, the module is updated 
    # to the latest version available on the PowerShell library
    
    param ( 
        $module, 
        [switch]$update 
    )
   
    if (get-module $module -ListAvailable) {
        if ($update.IsPresent) {
            
            # Updates the module to the latest version
            [string]$Moduleinstalled = (Get-Module -Name $module).version
            
            Try {
                [string]$ModuleonRepo = (Find-Module -Name $module -ErrorAction Stop).version
            }
            Catch {
                Write-Warning "Error: No internet connection to update $module ! `
                `nCheck your network connection, you might need to configure a proxy if you are connected to a corporate network!"
                return 
            }

            $Compare = Compare-Object $Moduleinstalled $ModuleonRepo -IncludeEqual

            If (-not $Compare.SideIndicator -eq '==') {
                Try {
                    Update-Module -ErrorAction stop -Name $module -Confirm -Force | Out-Null
                }
                Catch {
                    write-warning "Error: $module cannot be updated !"
                    return
                }
           
            }
            Else {
                Write-host "You are using the latest version of $module !" 
            }
        }
            
        Import-module $module
            
    }

    Else {
        Write-host "$Module cannot be found, let's install it..." -ForegroundColor Cyan

        
        If ( !(get-PSRepository).name -eq "PSGallery" )
        {Register-PSRepository -Default}
                
        Try {
            find-module -Name $module -ErrorAction Stop | out-Null
                
            Try {
                Install-Module –Name $module -Scope CurrentUser –Force -ErrorAction Stop | Out-Null
                Write-host "`nInstalling $Module ..." 
            }
            catch {
                Write-Warning "$Module cannot be installed!" 
                $error[0] | FL * -force
                pause
                exit
            }

        }
        catch {
            write-warning "Error: $module cannot be found in the online PSGallery !"
            return
        }
            
    }

}

MyImport-Module HPOneview.410 

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

#Connecting to the Synergy Composer

if ($connectedSessions -and ($connectedSessions | Where-Object {$_.name -eq $IP})) {
    Write-Verbose "Already connected to $IP."
}

else {
    Try {
        $ApplianceConnection = Connect-HPOVMgmt -appliance $IP -UserName $username -Password $password 
    }
    Catch {
        throw $_
    }
}

               
import-HPOVSSLCertificate -ApplianceConnection ($connectedSessions | Where-Object {$_.name -eq $IP})

Get-HPOVServerprofiletemplate | Out-Host
        
$spt = read-host "Which Server Profile Template do you want to use to propagate the LACP configuration accross all associated server profiles?"


#Capturing Server profiles under the SPT
$_spt = (Get-HPOVServerProfileTemplate -Name $spt) 

$association = "server_profile_template_to_server_profiles"

$uri = "/rest/index/associations?name={0}&parentUri={1}" -f $association, $_spt.uri


Try {

    $_IndexResults = Send-HPOVRequest -Uri $Uri -Hostname $ApplianceConnection

}

Catch {

    $PSCmdlet.ThrowTerminatingError($_)

}

#Creating object with Server profile information
$serverprofiles = New-Object System.Collections.ArrayList

foreach ($member in $_IndexResults.members) {
    $childuri = $member.childuri
    $_FullIndexEntry = Send-HPOVRequest -Uri $childuri -Hostname $ApplianceConnection
    [void]$serverprofiles.Add($_FullIndexEntry)

}

Write-verbose "SPT Child Server list: $serverprofiles.name"

#Capturing LAG names and network URI for each LAG enabled connection in SPT

$uniqueconnections = $_spt.connectionSettings.connections | Sort-Object -Property networkUri -Unique


$_Connections = @{}

Foreach ($connection in ($uniqueconnections)) {

    If ($connection.lagName -match "LAG") {
              
        $_Connections[$connection.lagname] += , $connection.networkUri
    }
}

# Exiting if no LAG configured in SPT    
If (-not $_Connections.Count -gt 0) {
    write-warning "No LAG connections can be detected in your Server Profile Template ! Exiting..."
    return
}

#Collecting LAG name(s)
$lagnames = $_Connections.keys 


#Updating all child Server profiles with LAG
foreach ($serverprofile in $serverprofiles) {
    
    $Applyprofile = $False 
    
    #for each LAG team in the profile, we configure the connection
    foreach ($lagname in $lagnames) {
        
        #collecting connection URI for the Lagname and network name
        [system.string]$connectionuri = $_Connections.$lagname 
        $networkname = (Send-HPOVRequest -Uri $connectionuri -Hostname $ApplianceConnection).name 
          
        #Throwing error if SPT network connection not found in SP or if only one network connection
        If ($serverprofile.connectionSettings.connections.networkuri -notcontains $connectionuri -or (($serverprofile.connectionSettings.connections.networkuri -match $connectionuri).count -eq 1) ) { 
            write-warning "Profile '$($serverprofile.name)' does not contain redundant '$networkname' networks, LAG cannot be enabled for '$networkname' !"
            $Applyprofile = $False
        }
        #If SPT network found in SP                         
        Else { 
            # If LAG already configured, no profile change       
            If ( (($serverprofile.connectionSettings.connections | Where-Object {$_.networkUri -eq $connectionuri}).lagName) -match $lagname) {
                write-host "Profile $($serverprofile.name): Connection '$networkname' is already configured for $lagname"
            }
            #If LAG not found, profile modification           
            Else {
                    
                $Applyprofile = $True
                    
                write-host "Profile $($serverprofile.name): Connection '$networkname' must be configured for LAG"
                                       
                $networkconnections = ($serverprofile.connectionSettings.connections | Where-Object {$_.networkUri -eq $connectionuri})
                
                foreach ($networkconnection in $networkconnections) {
                    
                    $networkconnection.lagname = $lagname 

                }
            }
        }                    
    }
                
    #Updating Server Profile if needed
    If ($Applyprofile -eq $True) {
        Set-HPOVResource $serverprofile | out-Null
        write-host "Profile '$($serverprofile.name)' is now LAG enabled, please wait for the profile to be updated...`n" -ForegroundColor green
    }
    Else {
        write-warning "Profile '$($serverprofile.name)' unchanged!`n" 

    }



}

    

