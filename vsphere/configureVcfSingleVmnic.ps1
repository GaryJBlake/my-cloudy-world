<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Blog:          http:/my-cloudy-world.com
    .Twitter:       @GaryJBlake
    .Version:       1.0 (Build 002)
    .Date:          2020-12-12
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-12-11) - Initial script creation
    - 1.0.002 (Gary Blake / 2020-12-12) - Updated all variables to be obtained from management domain spec

    ===============================================================================================================
    .DESCRIPTION
    This scripts executes a number of steps in order to perform the reconfiguration of ESXi Hosts that have a
    single active vmnic. It uses the managementDomain.json as the input and then performs the following steps:
    - Migrates the vCenter from vDS to vSS Portgroup
    - Configures the Advanced Setting in vCenter Server to Network Rollback
    - Reboots the vCenter Server
    - Migrates the First ESXi Host vmk0 and vmnic to the vDS from vSS
    - Migrates the vCenter Server from vSS to vDS Portgroup
    - Migrates the vmk0 and vmnic to the vDS from vSS for the remaining ESXi Hosts

    .EXAMPLE
    .\configureVcfSingleVmnic.ps1 -json managementDomain.json
#>

Param (
    [Parameter(mandatory=$true)]
        [String]$json
)

Clear-Host

Function checkPowershellModules {
    Try {
        $powerVcf = Get-InstalledModule -Name PowerVCF -ErrorAction SilentlyContinue
        if ($powerVcf.Version -eq "2.1.1") {
            Write-LogMessage -Message "Checking for PowerVCF Module"
            Write-LogMessage -Message "PowerVCF Found"
        }
        else {
            Install-PackageProvider NuGet -Force | Out-File $logFile -Encoding ASCII -Append
            Set-PSRepository PSGallery -InstallationPolicy Trusted | Out-File $logFile -Encoding ASCII -Append
            Install-Module PowerVCF -MinimumVersion 2.1.1 -Force -confirm:$false | Out-File $logFile -Encoding ASCII -Append
            Write-LogMessage -Message "PowerVCF Module Not Found. Installing."  
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }

    Write-LogMessage -Message "Importing PowerCLI Modules"
    Try {
        Import-Module -Name VMware.VimAutomation.Common | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Common -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Core | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Core -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.License | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.License -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Nsxt | Out-File $logFile -Encoding ASCII -Append    
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Nsxt -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Storage | Out-File $logFile -Encoding ASCII -Append    
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Storage -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Vds | Out-File $logFile -Encoding ASCII -Append   
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Vds -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }

    Write-LogMessage -Message "Configuring PowerShell CEIP Setting"
    $setCLIConfigurationCEIP = Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP $false -Confirm:$false -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
    Write-LogMessage -Message "Configuring PowerShell Certifcate Setting"
    $setCLIConfigurationCerts = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False -Scope AllUsers -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
}

Function updatePortgroup ($vmName, $oldPortgroup, $newPortgroup) {
    Try {
        Write-LogMessage -Message "Reconfigured Virtual Machine $vmName Port Group from $oldPortgroup to $newPortgroup"
        Get-VM -Name $vmName | Get-NetworkAdapter | Where {$_.NetworkName -eq $oldPortgroup} | Set-NetworkAdapter -Portgroup $newPortgroup -Confirm:$False
        Write-LogMessage -Message "Reconfigured Virtual Machine $vmName Port Group from $oldPortgroup to $newPortgroup Successfully" -Colour Green
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function connectVsphere ($hostname, $user, $password) {
    Try {
        Write-LogMessage -Message "Connecting to vCenter/ESXi Server $hostname"
        Connect-VIServer -Server $hostname -User $user -Password $password | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Connected to vCenter/ESXi Server $hostname successfully" -Colour Green
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function disconnectVsphere ($hostname) {
    Try {
        Write-LogMessage -Message "Disconnecting from vCenter/ESXi Server $hostname"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Disconnected from vCenter/ESXi Server $hostname Successfully" -Colour Green
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function vCenterVss {
    Try {
        # Reconfigure vCenter Server Port Group from vSphere Distributed Switch back to vSphere Stadnard Switch
        connectVsphere -hostname $esxiHost0 -user $esxiHostUser -password $esxiHostPassword
        #Write-LogMessage -Message "Reconfigure vCenter Serer $vCenterFqdn Port Group from $portgroup1 to $portgroup2"
        #Set-UpdatePortgroup -vmName $vmName -oldPortgroup $portgroup1 -newPortgroup $portgroup2 | Out-File $logFile -Encoding ASCII -Append
        updatePortgroup -vmName "sfo-vcf01" -oldPortgroup $portgroup1 -newPortgroup $portgroup2
        disconnectVsphere -hostname $esxiHost0
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function rollbackFalse {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $vCenterFqdn"
        Connect-VIServer -Server $vCenterFqdn -User $vCenterAdminUser -Password $vCenterAdminPassword | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Setting vCenter Server $vCenterFqdn Advanced Setting"
        Get-AdvancedSetting -Entity $vCenterFqdn -Name config.vpxd.network.rollback | Set-AdvancedSetting -Value 'false' -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Disconnecting from vCenter Server $vCenterFqdn"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function rebootVcenter ($hostname, $user, $password) {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $hostname to Reboot"
        Connect-CisServer -Server $hostname -User $user -Password $password | Out-Null
        $vamiShudownApi = Get-CisService -Server $hostname -Name "com.vmware.appliance.shutdown"
        $vamiShudownApi.reboot(1,'Change Advanced Setting: config.vpxd.network.rollback')

        Write-LogMessage -Message "Waiting for vCenter Server $hostname to go Down After Reboot Request"
        do{}Until (!(Test-Connection -computername $hostname -Quiet -Count 1))
        Write-LogMessage -Message "Connectivity to vCenter Server $hostname Lost (Expected)"

        # Monitor for vCenter Server to Come Online
        Write-LogMessage -Message "Waiting for vCenter Server $hostname to Come Back up After Reboot"
        do{}Until (Test-Connection -computername $hostname -Quiet -Count 1)
        Write-LogMessage -Message "Connectivity to vCenter Server $hostname Re-Established"

        # Keep Attempting to Connect to the vCenter Server Until it Responds Correctly
        Write-LogMessage -Message "Waiting for vCenter Server Services to Start on $hostname (May Take Some Time)"
        Do {}Until (Connect-VIServer -Server $hostname -User $user -Pass $password -ErrorAction SilentlyContinue)
        Write-LogMessage -Message "Connection to vCenter Server $hostname Established"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function migrateNetworking {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $vCenterFqdn"
        Connect-VIServer -Server $vCenterFqdn -User $vCenterAdminUser -Password $vCenterAdminPassword | Out-File $logFile -Encoding ASCII -Append
        
        $vds = Get-View -ViewType DistributedVirtualSwitch
        $dvsId = $vds.MoRef.Type+"-"+$vds.MoRef.Value
        $dvsPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"="DVUplinks"}
        $mgmtPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"=$portgroup1}
        
        #---------------QueryAvailableDvsSpec---------------
        $recommended = $true
        $_this = Get-View -Id 'DistributedVirtualSwitchManager-DVSManager'
        $_this.QueryAvailableDvsSpec($recommended) | Out-File $logFile -Encoding ASCII -Append

        #---------------FetchDVPorts---------------
        
        $criteria = New-Object VMware.Vim.DistributedVirtualSwitchPortCriteria
        $criteria.UplinkPort = $true
        $_this = Get-View -Id $dvsId
        $_this.FetchDVPorts($criteria) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail0 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost0}
        $hostId0 = 'HostNetworkSystem-networkSystem-'+$hostDetail0.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (1)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '16'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId0
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost0"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        Write-LogMessage -Message "Disconnecting from vCenter Server $vCenterFqdn"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function vCenterVds {
    Try {
        # Reconfigure vCenter Server Port Group from vSphere Distributed Switch back to vSphere Stadnard Switch
        Write-LogMessage -Message "Connecting to ESXi Server $esxiHost"
        Connect-VIServer -Server $esxiHost -User $esxiHostUser -Password $esxiHostPassword | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Reconfigure vCenter Serer $vCenterFqdn Port Group from $portgroup2 to $portgroup1"
        Set-UpdatePortgroup -vmName $vmName -oldPortgroup $portgroup2 -newPortgroup $portgroup1 | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Disconnecting from ESXi Server $esxiHost"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function migrateAllHosts {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $vCenterFqdn"
        Connect-VIServer -Server $vCenterFqdn -User $vCenterAdminUser -Password $vCenterAdminPassword | Out-File $logFile -Encoding ASCII -Append
        
        $vds = Get-View -ViewType DistributedVirtualSwitch
        $dvsId = $vds.MoRef.Type+"-"+$vds.MoRef.Value
        $dvsPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"="DVUplinks"}
        $mgmtPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"=$portgroup1}
        
        
        #---------------QueryAvailableDvsSpec---------------
        $recommended = $true
        $_this = Get-View -Id 'DistributedVirtualSwitchManager-DVSManager'
        $_this.QueryAvailableDvsSpec($recommended) | Out-File $logFile -Encoding ASCII -Append

        #---------------FetchDVPorts---------------
        
        $criteria = New-Object VMware.Vim.DistributedVirtualSwitchPortCriteria
        $criteria.UplinkPort = $true
        $_this = Get-View -Id $dvsId
        $_this.FetchDVPorts($criteria) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail1 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost1}
        $hostId1 = 'HostNetworkSystem-networkSystem-'+$hostDetail1.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic2'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '19'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortKey = '18'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId1
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost1"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail2 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost2}
        $hostId2 = 'HostNetworkSystem-networkSystem-'+$hostDetail2.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic2'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '21'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortKey = '20'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId2
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost2"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail3 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost3}
        $hostId3 = 'HostNetworkSystem-networkSystem-'+$hostDetail3.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic2'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '23'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortKey = '22'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId3
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost3"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        Write-LogMessage -Message "Disconnecting from vCenter Server $vCenterFqdn"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Try {
    checkPowershellModules # Ensure PowerShell Modules are Installed (PowerVCF and PowerCLI)

    Start-SetupLogFile -Path $PSScriptRoot -ScriptName "configureSingleVmnic" # Create new log

    $jsonPath = $PSScriptRoot+"\"+$json
    Write-LogMessage  -Message "Reading the Management Domain JSON Spec" -Colour Yellow
    $Global:cbJson = (Get-Content -Raw $jsonPath) | ConvertFrom-Json

    $esxiHostUser = $cbJson.hostSpecs.credentials.username[0]
    $esxiHostPassword = $cbJson.hostSpecs.credentials.password[0]
    $esxiHost0 = $cbJson.hostSpecs.hostname[0]+"."+$cbJson.dnsSpec.subdomain
    $esxiHost1 = $cbJson.hostSpecs.hostname[1]+"."+$cbJson.dnsSpec.subdomain
    $esxiHost2 = $cbJson.hostSpecs.hostname[2]+"."+$cbJson.dnsSpec.subdomain
    $esxiHost3 = $cbJson.hostSpecs.hostname[3]+"."+$cbJson.dnsSpec.subdomain

    $vCenterFqdn = $cbJson.vcenterSpec.vcenterHostname+'.'+$cbJson.dnsSpec.subdomain
    $vCenterAdminUser = "administrator@vsphere.local"
    $vCenterAdminPassword = $cbJson.pscSpecs.adminUserSsoPassword
    $vmName = $cbJson.vcenterSpec.vcenterHostname
    $portgroup1 = $cbJson.networkSpecs.portGroupKey[0]
    $portgroup2 = "VM Network"

    connectVsphere -hostname $esxiHost0 -user $esxiHostUser -password $esxiHostPassword # Connect to First ESXi Host
    updatePortgroup -vmName $vmName -oldPortgroup $portgroup1 -newPortgroup $portgroup2 # Migrate vCenter Server from vDS to vSS
    disconnectVsphere -hostname $esxiHost0 # Disconnect from First ESXi Host

    #connectVsphere -hostname $vCenterFqdn -user $vCenterAdminUser -password $vCenterAdminPassword # Connect to vCenter Server
    #Get-AdvancedSetting -Entity $vCenterFqdn -Name config.vpxd.network.rollback | Set-AdvancedSetting -Value 'false' -Confirm:$false | Out-File $logFile -Encoding ASCII -Append # Set vCenter Advanced Setting config.vpxd.network.rollback to false
    #disconnectVsphere -hostname $vCenterFqdn # Disconnect from First ESXi Host
    #rollbackFalse

    #rebootVcenter -hostname $vCenterFqdn -user $vCenterAdminUser -password $vCenterAdminPassword # Reboot vCenter Server
    ##migrateNetworking

    #connectVsphere -hostname $esxiHost0 -user $esxiHostUser -password $esxiHostPassword # Connect to First ESXi Host
    #updatePortgroup -vmName vmName -oldPortgroup $portgroup2 -newPortgroup $portgroup1 # Migrate vCenter Server from vSS to vDS
    #disconnectVsphere -hostname $esxiHost0 # Disconnect from First ESXi Host
    #vCenterVds

    #PAUSE
    #migrateAllHosts
}
Catch {
    Debug-CatchWriter -object $_
}