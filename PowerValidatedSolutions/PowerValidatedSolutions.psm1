# PowerShell module for VMware Cloud Foundation Validated Solutions
# Contributions, Improvements &/or Complete Re-writes Welcome!
# https://github.com/?

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Note
# This powershell module should be considered entirely experimental. It is still in development & not tested beyond lab
# scenarios. It is recommended you dont use it for any production environment without testing extensively!

# Enable communication with self signed certs when using Powershell Core. If you require all communications to be secure
# and do not wish to allow communication with self signed certs remove lines 17-38 before importing the module.

if ($PSEdition -eq 'Core') {
    $PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck", $true)
}

if ($PSEdition -eq 'Desktop') {
    # Enable communication with self signed certs when using Windows Powershell
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

    add-type @"
	using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertificatePolicy : ICertificatePolicy {
        public TrustAllCertificatePolicy() {}
		public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate certificate,
            WebRequest wRequest, int certificateProblem) {
            return true;
        }
	}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertificatePolicy
}

####  Do not modify anything below this line. All user variables are in the accompanying JSON files #####

Function Resolve-PSModule {
    <#
        .SYNOPSIS
        Check for a PowerShell module presence, if not there try to import/install it.

        .DESCRIPTION
        This function is not exported. The idea is to use the return searchResult from the caller function to establish
        if we can proceed to the next step where the module will be required (developed to check on Posh-SSH).
        Logic:
        - Check if module is imported into the current session
        - If module is not imported, check if available on disk and try to import
        - If module is not imported & not available on disk, try PSGallery then install and import
        - If module is not imported, not available and not in online gallery then abort

        Informing user only if the module needs importing/installing. If the module is already present nothing will be displayed.

        .EXAMPLE
        PS C:\> $poshSSH = Resolve-PSModule -moduleName "Posh-SSH"
        This example will check if the current PS module session has Posh-SSH installed, if not will try to install it
    #>

    Param (
        [Parameter (Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$moduleName
    )

    # check if module is imported into the current session
    if (Get-Module -Name $moduleName) {
        $searchResult = "ALREADY_IMPORTED"
    }
    else {
        # If module is not imported, check if available on disk and try to import
        if (Get-Module -ListAvailable | Where-Object { $_.Name -eq $moduleName }) {
            Try {
                "`n Module $moduleName not loaded, importing now please wait..."
                Import-Module $moduleName
                Write-Output "Module $moduleName imported successfully."
                $searchResult = "IMPORTED"
            }
            Catch {
                $searchResult = "IMPORT_FAILED"
            }
        }
        else {
            # If module is not imported & not available on disk, try PSGallery then install and import
            if (Find-Module -Name $moduleName | Where-Object { $_.Name -eq $moduleName }) {
                Try {
                    Write-Output "Module $moduleName was missing, installing now please wait..."
                    Install-Module -Name $moduleName -Force -Scope CurrentUser
                    Write-Output "Importing module $moduleName, please wait..."
                    Import-Module $moduleName
                    Write-Output "Module $moduleName installed and imported"
                    $searchResult = "INSTALLED_IMPORTED"
                }
                Catch {
                    $searchResult = "INSTALLIMPORT_FAILED"
                }
            }
            else {
                # If module is not imported, not available and not in online gallery then abort
                $searchResult = "NOTAVAILABLE"
            }
        }
    }
    Return $searchResult
}

######### Start Identity and Access Management  ##########

Function New-GlobalPermission {
    <#
    	.SYNOPSIS
    	Script to add/remove vSphere Global Permission

    	.DESCRIPTION
    	The Connect-CloudBuilder cmdlet connects to the specified Cloud Builder and stores the credentials
    	in a base64 string. It is required once per session before running all other cmdlets

        .NOTES
        Author:     William Lam. Modified by Ken Gould to permit principal type (user or group) and Gary Blake to include
                    in this function
        Reference:  http://www.virtuallyghetto.com/2017/02/automating-vsphere-global-permissions-with-powercli.html

    	.EXAMPLE
    	PS C:\> New-GlobalPermission -vcServer sfo-m01-vc01.sfo.rainpole.io -username administrator@vsphewre.local -vcPassword VMware1! -user svc-vc-admins
    	This example shows how to add the Administrator global permission to a user called svc-vc-admins
  	#>

    Param (
        [Parameter(Mandatory = $true)][string]$vcServer,
        [Parameter(Mandatory = $true)][String]$vcUsername,
        [Parameter(Mandatory = $true)][String]$vcPassword,
        [Parameter(Mandatory = $true)][String]$user,
        [Parameter(Mandatory = $true)][String]$roleId,
        [Parameter(Mandatory = $true)][String]$propagate,
        [Parameter(Mandatory = $true)][String]$type
    )
    
    $secpasswd = ConvertTo-SecureString $vcPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($vcUsername, $secpasswd)
    
    $mob_url = "https://$vcServer/invsvc/mob3/?moid=authorizationService&method=AuthorizationService.AddGlobalAccessControlList" # vSphere MOB URL to private enableMethods
    
    # Ignore SSL Warnings
    add-type -TypeDefinition  @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    
    $results = Invoke-WebRequest -Uri $mob_url -SessionVariable vmware -Credential $credential -Method GET # Initial login to vSphere MOB using GET and store session using $vmware variable
    # Extract hidden vmware-session-nonce which must be included in future requests to prevent CSRF error
    # Credit to https://blog.netnerds.net/2013/07/use-powershell-to-keep-a-cookiejar-and-post-to-a-web-form/ for parsing vmware-session-nonce via Powershell
    if ($results.StatusCode -eq 200) {
        $null = $results -match 'name="vmware-session-nonce" type="hidden" value="?([^\s^"]+)"'
        $sessionnonce = $matches[1]
    }
    else {
        Write-Error "Failed to login to vSphere MOB"
        exit 1
    }
    
    $vc_user_escaped = [uri]::EscapeUriString($user) # Escape username
    
    # The POST data payload must include the vmware-session-nonce variable + URL-encoded
    If ($type -eq "group") {
        $body = @"
vmware-session-nonce=$sessionnonce&permissions=%3Cpermissions%3E%0D%0A+++%3Cprincipal%3E%0D%0A++++++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A++++++%3Cgroup%3Etrue%3C%2Fgroup%3E%0D%0A+++%3C%2Fprincipal%3E%0D%0A+++%3Croles%3E$roleId%3C%2Froles%3E%0D%0A+++%3Cpropagate%3E$propagate%3C%2Fpropagate%3E%0D%0A%3C%2Fpermissions%3E
"@        
    }
    else {
        $body = @"
vmware-session-nonce=$sessionnonce&permissions=%3Cpermissions%3E%0D%0A+++%3Cprincipal%3E%0D%0A++++++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A++++++%3Cgroup%3Efalse%3C%2Fgroup%3E%0D%0A+++%3C%2Fprincipal%3E%0D%0A+++%3Croles%3E$roleId%3C%2Froles%3E%0D%0A+++%3Cpropagate%3E$propagate%3C%2Fpropagate%3E%0D%0A%3C%2Fpermissions%3E
"@
    }
    
    $results = Invoke-WebRequest -Uri $mob_url -WebSession $vmware -Method POST -Body $body # Second request using a POST and specifying our session from initial login + body request
    if ($results.StatusCode -eq 200) {
        Write-Verbose "Successfully added global permission for: $user"
    }
    $mob_logout_url = "https://$vcServer/invsvc/mob3/logout" # Logout out of vSphere MOB
    $results = Invoke-WebRequest -Uri $mob_logout_url -WebSession $vmware -Method GET
}
Export-ModuleMember -Function New-GlobalPermission


Function Add-IdentitySource {
    # Add Active Directory over LDAP as Identity Provider to vCenter Server and Set as Default
    Param (
        [Parameter(Mandatory = $true)][String]$vCenterVmName,
        [Parameter(Mandatory = $true)][String]$rootPass,
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $true)][String]$domainBindUser,
        [Parameter(Mandatory = $true)][String]$domainBindPass,
        [Parameter(Mandatory = $true)][String]$dcMachineName,
        [Parameter(Mandatory = $true)][String]$baseGroupDn,
        [Parameter(Mandatory = $true)][String]$baseUserDn
    )

    $domainAlias = ($domain.Split("."))[0].ToUpper()
    $bindUser = $domainBindUser + '@' + ($domain.Split("."))[0].ToLower()
    $primaryUrl = 'ldap://' + $dcMachineName + '.' + $domain + ':389'

    Try {
        $scriptCommand = '/opt/vmware/bin/sso-config.sh -get_identity_sources'
        $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass -ErrorAction SilentlyContinue
        if (($output.ScriptOutput).Contains($domain)) {
            Write-Warning "Identity Source $domain already added to vCenter Server $vCenterVmName"
        }
        else {
            $scriptCommand = '/opt/vmware/bin/sso-config.sh -add_identity_source -type adldap -baseUserDN ' + $baseUserDn + ' -baseGroupDN ' + $baseGroupDn + ' -domain ' + $domain + ' -alias ' + $domainAlias + ' -username ' + $bindUser + ' -password ' + $domainBindPass + ' -primaryURL ' + $primaryUrl + ''
            $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass
            $scriptCommand = '/opt/vmware/bin/sso-config.sh -get_identity_sources'
            $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass -ErrorAction SilentlyContinue
            if (($output.ScriptOutput).Contains($domain)) {
                Write-Output "Confirmed adding Identity Source $domain to vCenter Server $vCenterVmName Successfully"
            }
            else {
                Write-Error  "Adding Identity Source $domain to vCenter Server $vCenterVmName Failed"
            }
            $scriptCommand = '/opt/vmware/bin/sso-config.sh -set_default_identity_sources -i ' + $domain + ''
            $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPass
            Write-Output  "Confirmed setting $domain as Default Identity Source on vCenter Server $vCenterVmName Successfully"
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Add-IdentitySource

Function Add-GlobalPermission {
    # Assign an Active Directory Group Role as a Global Permission in vCenter Server
    Param (
        [Parameter(Mandatory = $true)][String]$server,
        [Parameter(Mandatory = $true)][String]$user,
        [Parameter(Mandatory = $true)][String]$pass,
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $true)][String]$domainBindUser,
        [Parameter(Mandatory = $true)][String]$domainBindPass,
        [Parameter(Mandatory = $true)][String]$principal,
        [Parameter(Mandatory = $true)][String]$role,
        [Parameter(Mandatory = $true)][ValidateSet("group","user")][String]$type
    )

    $securePass = ConvertTo-SecureString -String $domainBindPass -AsPlainText -Force
    $domainCreds = New-Object System.Management.Automation.PSCredential ($domainBindUser, $securePass)

    Try {
        if (Get-ADGroup -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $principal }) {
            $roleId = (Get-VIRole -Name $role | Select-Object -ExpandProperty Id)
            New-GlobalPermission -vcServer $server -vcUsername $user -vcPassword $pass -roleId $roleId -user $principal -propagate $true -type $type
            Write-Output "Assigned Global Permission Role $role to '$principal' in vCenter Server $server Successfully"
        }
        else {
            Write-Error "Active Directory Group '$principal' not found in the Active Directory Domain, please create and retry"
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Add-GlobalPermission

Function Add-SddcManagerRole {
    # Assign Active Directory Groups to the Admin, Operator and Viewer Roles in SDDC Manager
    Param (
        [Parameter(Mandatory = $true)][String]$server,
        [Parameter(Mandatory = $true)][String]$user,
        [Parameter(Mandatory = $true)][String]$pass,
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $true)][String]$domainBindUser,
        [Parameter(Mandatory = $true)][String]$domainBindPass,
        [Parameter(Mandatory = $true)][String]$group,
        [Parameter(Mandatory = $true)][ValidateSet("ADMIN","OPERATOR","VIEWER")][String]$role
    )   

    $securePass = ConvertTo-SecureString -String $domainBindPass -AsPlainText -Force
    $domainCreds = New-Object System.Management.Automation.PSCredential ($domainBindUser, $securePass)

    Try {
        Request-VCFToken -fqdn $server -Username $user -Password $pass
        if (Get-ADGroup -Server $domain -Credential $domainCreds -Filter { SamAccountName -eq $group }) {
            $groupCheck = Get-VCFUser | Where-Object { $_.name -eq $($domain.ToUpper() + "\" + $group) }
            if ($groupCheck.name -eq $($domain.ToUpper() + "\" + $group)) {
                Write-Warning -Message "Active Directory Group '$group' already assigned the $role role in SDDC Manager"
            }
            else {
                New-VCFGroup -group $group -domain $domain -role $role
                $groupCheck = Get-VCFUser | Where-Object { $_.name -eq $($domain.ToUpper() + "\" + $group) }
                if ($groupCheck.name -eq $($domain.ToUpper() + "\" + $group)) {
                    Write-Output "Active Directory Group '$group' assigned the $role role in SDDC Manager Successfully"
                }
                else {
                    Write-Error "Assigning Active Directory Group '$group' the $role role in SDDC Manager Failed"
                }
            }
        }
        else {
            Write-Error "Active Directory Group '$group' not found in the Active Directory Domain, please create and retry"
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Add-SddcManagerRole

Function Join-ESXiJoinDomain {
    # Join each ESXi Host to the Active Directory Domain
    Param (
        [Parameter(Mandatory = $true)][String]$domain,
        [Parameter(Mandatory = $true)][String]$domainJoinUser,
        [Parameter(Mandatory = $true)][String]$domainJoinPass
    )  

    Try {
        $checkAdAuthentication = Test-ADAuthentication -user $domainJoinUser -pass $domainJoinPass -server $domain -domain $domain
        if ($checkAdAuthentication -contains "2") {
            $esxiHosts = Get-VMHost
            $count = 0
            Foreach ($esxiHost in $esxiHosts) {
                $currentDomainState = Get-VMHostAuthentication -VMHost $esxiHost
                $currentDomain = [String]$currentDomainState.Domain
                if ($currentDomain -ne $domain) {
                    Get-VMHostAuthentication -VMHost $esxiHost | Set-VMHostAuthentication -Domain $domain -JoinDomain -Username $domainJoinUser -Password $domainJoinPassword -Confirm:$false
                    $currentDomainState = Get-VMHostAuthentication -VMHost $esxiHost
                    $currentDomain = [String]$currentDomainState.Domain
                    if ($currentDomain -eq $domain.ToUpper()) {
                        Write-Output "Confirmed ESXi Host $esxiHost joined Active Directory Domain $domain Successfully"
                    }
                    else {
                        Write-Error "Adding ESXi Host $esxiHost to Active Directory Domain $domain Failed"
                    }
                }
                else {
                    Write-Warning "ESXi Host $esxiHost already joined to Active Directory Domain $domain"
                }
                $count = $count + 1
            }
        }
        else {
            Write-Error "Domain User $domainJoinUser Authentication Failed"
        }
    }
    Catch {
        Debug-CatchWriter -object $_
    }
}
Export-ModuleMember -Function Join-ESXiJoinDomain

######### End Identity and Access Management  ##########


######### Start Shared Functions  ##########

Function connectVsphere {
    Param (
        [Parameter(Mandatory = $true)][string]$hostname,
        [Parameter(Mandatory = $true)][String]$user,
        [Parameter(Mandatory = $true)][String]$password
    )

    Try {
        Write-Output  "Connecting to vCenter/ESXi Server $hostname"
        Connect-VIServer -Server $hostname -User $user -Password $password
        Write-Output -Message "Connected to vCenter/ESXi Server $hostname Successfully"
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function disconnectVsphere ($hostname) {
    Try {
        Write-Output  "Disconnecting from vCenter/ESXi Server $hostname"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
        Write-Output  "Disconnected from vCenter/ESXi Server $hostname Successfully" -Colour Green
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function connectVcf ($fqdn, $username, $password) {
    Write-Output  "Connecting to SDDC Manager $sddcMgrFqdn"
    Try {
        if (Test-Connection -ComputerName $fqdn -ErrorAction SilentlyContinue) {
            Write-Output - "Checking that connection to SDDC Manager $fqdn is possible"
            $connection = Request-VCFToken -fqdn $fqdn -username $username -password $password
            if ($connection.success) { Write-Output "$($connection.success)" }
        }
        else {
            if ($connection.error) { Write-Output "$($connection.error)" }
        }
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function Test-ADAuthentication {
    Param (
        [Parameter(Mandatory)][string]$user,
        [Parameter(Mandatory)]$pass,
        [Parameter(Mandatory = $false)]$server,
        [Parameter(Mandatory = $false)][string]$domain = $env:USERDOMAIN
    )
      
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        
    $contextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain
        
    $argumentList = New-Object -TypeName "System.Collections.ArrayList"
    $null = $argumentList.Add($contextType)
    $null = $argumentList.Add($domain)
    if($null -ne $server){
        $argumentList.Add($server)
    }
    $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList $argumentList -ErrorAction SilentlyContinue
    if ($null -eq $principalContext) {
        Write-Error "$domain\$user - AD Authentication Failed"
    }
    if ($principalContext.ValidateCredentials($user, $pass)) {
        Write-Output "$domain\$user - AD Authentication Successful"
    }
    else {
        Write-Error "$domain\$eser - AD Authentication Failed"
    }
}
Export-ModuleMember -Function Test-ADAuthentication


######### Start Shared Functions  ##########


######### Start Workspace One Access Functions  ##########

Function Request-WSAToken {
    <#
		.SYNOPSIS
    	Connects to the specified Workspace ONE Access instance to obtain a session token

    	.DESCRIPTION
    	The Request-WSAToken cmdlet connects to the specified Workspace ONE Access instance and requests a session token

    	.EXAMPLE
    	PS C:\> Request-WSAToken -fqdn sfo-wsa01.sfo.rainpole.io -username admin -password VMware1!
        This example shows how to connect to a Workspace ONE Access instance and request a session token
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [string]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [string]$password
    )

    If ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        # Request Credentials
        $creds = Get-Credential
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }
    
    # Validate credentials by executing an API call
    $headers = @{"Content-Type" = "application/json"}
    $headers.Add("Accept", "application/json; charset=utf-8")
    $uri = "https://$fqdn/SAAS/API/1.0/REST/auth/system/login"
    $body = '{"username": "' + $username + '", "password": "' + $password + '", "issueToken": "true"}'
    
    Try {
        # Checking against the API
        # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -SkipCertificateCheck
            $Global:accessToken = "HZN " + $response.sessionToken
        }
        else {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body
            $Global:accessToken = "HZN " + $response.sessionToken
        }
        if ($response.sessionToken) {
            Write-Output "Successfully Requested New Session Token From Workspace ONE Access instance: $fqdn"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-WSAToken

######### End Workspace One Access Functions  ##########


######### Start Utility Functions Functions ##########

Function Start-SetupLogFile ($path, $scriptName) {
    $filetimeStamp = Get-Date -Format "MM-dd-yyyy_hh_mm_ss"   
    $Global:logFile = $path + '\logs\' + $scriptName + '-' + $filetimeStamp + '.log'
    $logFolder = $path + '\logs'
    $logFolderExists = Test-Path $logFolder
    if (!$logFolderExists) {
        New-Item -ItemType Directory -Path $logFolder | Out-Null
    }
    New-Item -type File -Path $logFile | Out-Null
    $logContent = '[' + $filetimeStamp + '] Beginning of Log File'
    Add-Content -Path $logFile $logContent | Out-Null
}
Export-ModuleMember -Function Start-SetupLogFile

Function Write-LogMessage {
    Param (
        [Parameter(Mandatory = $true)]
        [String]$message,
        [Parameter(Mandatory = $false)]
        [String]$colour,
        [Parameter(Mandatory = $false)]
        [string]$skipNewLine
    )

    If (!$colour) {
        $colour = "Cyan"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timeStamp]"
    If ($skipNewLine) {
        Write-Host -NoNewline -ForegroundColor $colour " $message"        
    }
    else {
        Write-Host -ForegroundColor $colour " $message" 
    }
    $logContent = '[' + $timeStamp + '] ' + $message
    Add-Content -path $logFile $logContent
}
Export-ModuleMember -Function Write-LogMessage


Function Debug-CatchWriter {
    Param (
        [Parameter(Mandatory = $true)]
        [PSObject]$object
    )

    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    Write-Output " Error at Script Line $lineNumber"
    Write-Output " Relevant Command: $lineText"
    Write-Output " Error Message: $errorMessage"
}
Export-ModuleMember -Function Debug-CatchWriter

######### End Utility Functions Functions ##########