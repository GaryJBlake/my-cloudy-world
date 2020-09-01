﻿<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-07-22
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-05-29) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates performing the prerequisite configugration tasks for each ESXi Hosts that is consumed by
    SDDC Manager. It uses the Planning and Preparation Workbook to obtain the required details.

    .EXAMPLE

    .\configureEsxiHostPrerequisites.ps1 -Workbook E:\pnpWorkbook.xlsx -rootPassword VMw@re1!
#>

 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json
)

$module = "Commission Host JSON Spec"

Function LogMessage {

    Param(
        [Parameter(Mandatory=$true)]
            [String]$message,
        [Parameter(Mandatory=$false)]
            [String]$colour,
        [Parameter(Mandatory=$false)]
            [string]$skipnewline
    )

    If (!$colour) {
        $colour = "green"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timestamp]"
    If ($skipnewline) {
        Write-Host -NoNewline -ForegroundColor $colour " $message"
    }
    else {
        Write-Host -ForegroundColor $colour " $message"
    }
}

Try {
    LogMessage " Importing ImportExcel Module"
    Import-Module ImportExcel -WarningAction SilentlyContinue -ErrorAction Stop
}
Catch {
    LogMessage " ImportExcel Module not found. Installing"
    Install-Module ImportExcel
}

LogMessage " Starting the Process of Generating the $module" Yellow
LogMessage " Opening the Excel Workbook: $Workbook"
$pnpWorkbook = Open-ExcelPackage -Path $Workbook

LogMessage " Checking Valid Planning and Prepatation Workbook Provided"
if ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.0.1") {
    LogMessage " Planning and Prepatation Workbook Provided Not Supported" Red 
    Break
}

LogMessage " Extracting Worksheet Data from the Excel Workbook"
$Global:networkPoolName = $pnpWorkbook.Workbook.Names["wld_pool_name"].Value 

LogMessage " Generating the $module"
$resourcesObject = @()
$resourcesObject += [pscustomobject]@{
    'fqdn' = $pnpWorkbook.Workbook.Names["wld_host1_fqdn"].Value
    'username' = "root"
    'storageType' = "VSAN"
    'password' = "VMw@re1!"
    'networkPoolName' = $networkPoolName
    'networkPoolId' = "POOL-ID"
}
$resourcesObject += [pscustomobject]@{
    'fqdn' = $pnpWorkbook.Workbook.Names["wld_host2_fqdn"].Value
    'username' = "root"
    'storageType' = "VSAN"
    'password' = "VMw@re1!"
    'networkPoolName' = $networkPoolName
    'networkPoolId' = "POOL-ID"
}
$resourcesObject += [pscustomobject]@{
    'fqdn' = $pnpWorkbook.Workbook.Names["wld_host3_fqdn"].Value
    'username' = "root"
    'storageType' = "VSAN"
    'password' = "VMw@re1!"
    'networkPoolName' = $networkPoolName
    'networkPoolId' = "POOL-ID"
}
$resourcesObject += [pscustomobject]@{
    'fqdn' = $pnpWorkbook.Workbook.Names["wld_host4_fqdn"].Value
    'username' = "root"
    'storageType' = "VSAN"
    'password' = "VMw@re1!"
    'networkPoolName' = $networkPoolName
    'networkPoolId' = "POOL-ID"
}

LogMessage " Exporting the $module to $Json"
$resourcesObject | ConvertTo-Json | Out-File -FilePath $Json
Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
LogMessage " Closing the Excel Workbook: $Workbook"
LogMessage " Completed the Process of Generating the $module" Yellow