<# 
********************************************************************************************************* 
			             Created by Tyler Lane, 5/2/2019		 	                
*********************************************************************************************************
Modified by   |  Date   | Revision | Comments                                                       
_________________________________________________________________________________________________________
Tyler Lane    | 5/2/19  |   v1.0   | First version
Tyler Lane    | 6/26/19 |   v1.1   | Cleaned up code, added comments, prepared for collaboration                                                 
_________________________________________________________________________________________________________ 
.NAME
	Migrate Direct Associations
.SYNOPSIS 
    Remove SCCM direct associations from one computer object and apply them to another. Useful for
	replacing a PC with a new one. 
.PARAMETERS 
    None
.EXAMPLE 
    None 
.NOTES 
	Search for "DATA_REQUIRED" to see any data points that need filled in for the script to work properly
#>

# Configure functions
<#
.SYNOPSIS
    Get-CMCollectionOfDevice retrieves all collections where the specified device has a membership

.DESCRIPTION
    The Get-CMCollectionOfDevice retrieves all collections where the specified device has a membership

.PARAMETER Computer
    The name of the computer device

    Example: Client01

.PARAMETER SiteCode
    The Configuration Manager Site Code

    Example: PRI

.PARAMETER SiteServer
    The computer name of the Configuration Manager Site Server

    Example: Contoso-01

.EXAMPLE
    Get-CMCollectionOfDevice -Computer Client01


    CollectionID                  Name                          Commnent                      LastRefreshTime             
    ------------                  ----                          --------                      ---------------             
    SMS00001                      All Systems                   All Systems                   14.10.2014 14:25:57         
    SMSDM003                      All Desktop and Server Cli... All Desktop and Server Cli... 14.10.2014 14:30:02         
    PR100011                      ALL Contoso  Workstation Lim. Limiting collection used f... 14.10.2014 16:37:53         
    PR100014                      Zurich                        Location Zuerich              14.10.2014 14:45:53         


    The above command lists all collections where computer Client01 is a member of. The default
    parameter values for SiteCode and SiteServer defined in the script are used. 

.EXAMPLE
    Get-CMCollectionOfDevice -Computer Client01 -SiteCode PRI -SiteServer Contoso-01
    
    The above command lists all collections where computer Client01 is a member of within the
    Configuration Manager site PRI connecting to Site Server Contoso-01

.NOTES
    Version 1.0 , Alex Verboon
    Credits to Kaido Järvemets and David O'Brien for the code snippets
#>

function Get-CMCollectionOfDevice
{
    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        # Computername
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [String]$Computer,

        # ConfigMgr SiteCode
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
        [String]$SiteCode = "PRI",

        # ConfigMgr SiteServer
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=2)]
        [String]$SiteServer = "contoso-01.corp.com"
    )
Begin
{
    [string] $Namespace = "root\SMS\site_$SiteCode"
}

Process
{
    $si=1
    #Write-Progress -Activity "Retrieving ResourceID for computer $computer" -Status "Retrieving data" 
    $ResIDQuery = Get-WmiObject -ComputerName $SiteServer -Namespace $Namespace -Class "SMS_R_SYSTEM" -Filter "Name='$Computer'"
    
    If ([string]::IsNullOrEmpty($ResIDQuery))
    {
        Write-Output "System $Computer does not exist in Site $SiteCode"
    }
    Else
    {
    $Collections = (Get-WmiObject -ComputerName $SiteServer -Class sms_fullcollectionmembership -Namespace $Namespace -Filter "ResourceID = '$($ResIDQuery.ResourceId)'")
    $colcount = $Collections.Count
    
    $devicecollections = @()
    ForEach ($res in $collections)
    {
        $colid = $res.CollectionID
        #Write-Progress -Activity "Processing  $si / $colcount" -Status "Retrieving Collection data" -PercentComplete (($si / $colcount) * 100)

        $collectioninfo = Get-WmiObject -ComputerName $SiteServer -Namespace $Namespace -Class "SMS_Collection" -Filter "CollectionID='$colid'"
        $object = New-Object -TypeName PSObject
        $object | Add-Member -MemberType NoteProperty -Name "CollectionID" -Value $collectioninfo.CollectionID
        $object | Add-Member -MemberType NoteProperty -Name "Name" -Value $collectioninfo.Name
        $object | Add-Member -MemberType NoteProperty -Name "Commnent" -Value $collectioninfo.Comment
        $object | Add-Member -MemberType NoteProperty -Name "LastRefreshTime" -Value ([Management.ManagementDateTimeConverter]::ToDateTime($collectioninfo.LastRefreshTime))
        $devicecollections += $object
        $si++
    }
} # end check system exists
}

End
{
    $devicecollections
}
}

Function Get-SCCMDeviceResourceID
{
[CmdletBinding()]
Param(
[Parameter(Mandatory=$True)]
$SiteServer,
[Parameter(Mandatory=$True)]
$SiteCode,
[Parameter(Mandatory=$True)]
$DeviceName
)

Try{
Get-WmiObject -Namespace "Root\SMS\Site_$($SiteCode)" -Class 'SMS_R_SYSTEM' -Filter     "Name='$DeviceName'" -ComputerName $SiteServer
}
Catch{
$_.Exception.Message
}
}

# Push appropriate directory
If (((Get-WmiObject Win32_OperatingSystem).OSArchitecture) -eq "64-Bit") { Push-Location 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin'} 
If (((Get-WmiObject Win32_OperatingSystem).OSArchitecture) -eq "32-Bit") { Push-Location 'C:\Program Files\Microsoft Configuration Manager\AdminConsole\bin' }

# Connect to SCCM Instance
$SiteCode = "" <# DATA_REQUIRED : Site Code #> 
$ProviderMachineName = "" <# DATA_REQUIRED : SMS Provider machine name #>
Import-Module .\ConfigurationManager.psd1
New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName -ErrorAction SilentlyContinue
Set-Location "$($SiteCode):\"

# Clear that nonsense
#cls

# Collect variables
Write-Host "`n"
$SourceComputerName = Read-Host "What Is The Source Computer Name?" 
$DestinationComputerName = Read-Host "What Is The Destination Computer Name?"
$SourceComputerID = (Get-SCCMDeviceResourceID -SiteServer $ProviderMachineName -SiteCode $SiteCode -DeviceName $SourceComputerName).ResourceID
$DestinationComputerID = (Get-SCCMDeviceResourceID -SiteServer $ProviderMachineName -SiteCode $SiteCode -DeviceName $DestinationComputerName).ResourceID
$SourceDirectAssociations = @()
$DestinationDirectAssociations = @()

# Query all collections for source PC
$SourceCollectionIDs = Get-CMCollectionOfDevice -Computer $SourceComputerName -SiteCode $SiteCode -SiteServer $ProviderMachineName | Where CollectionID -Like "" <# DATA_REQUIRED : Site Code. May need wildcard at end #> | Select -ExpandProperty CollectionID

# Reduce the query results to just Direct associations
ForEach ($SourceCollectionID In $SourceCollectionIDs) { 

If ((Get-CMCollectionMember -CollectionId $SourceCollectionID -ResourceId $SourceComputerID).IsDirect -eq $True) { $SourceDirectAssociations += $SourceCollectionID }

}

# Translate reduced query to friendly names
$SourceCollectionNames = ForEach ($SourceCollectionID In $SourceDirectAssociations) {Get-CMCollection -Id $SourceCollectionID | Select -ExpandProperty Name}

# User validation of data
Write-Host "`n"
Write-Host "Source Computer ($SourceComputerName) Configuration Manager Direct Associations Listed Below..."
Write-Host "`n"
ForEach ($SourceCollectionName In $SourceCollectionNames) {Write-Host "        $SourceCollectionName"}
Write-Host "`n"
Write-Host "Are You Sure You Want To Migrate The Direct Associations From $SourceComputerName To $DestinationComputerName`?"
$Decision = Read-Host "   (Y/N)"
Write-Host "`n"

# Do the things now
If ($Decision -like "*Y*") {

Write-Host "Migration Confirmed. Working..." -ForegroundColor Yellow

# Remove direct collections from old computer
ForEach ($SourceCollectionID In $SourceDirectAssociations) { Remove-CMDeviceCollectionDirectMembershipRule -CollectionID $SourceCollectionID -ResourceID $SourceComputerID -ErrorAction SilentlyContinue -Force }

# Add direct collections to new computer
ForEach ($SourceCollectionID In $SourceDirectAssociations) { Add-CMDeviceCollectionDirectMembershipRule -CollectionID $SourceCollectionID -ResourceID $DestinationComputerID -ErrorAction SilentlyContinue -Confirm:$false }

# Sleep to let SCCM process
Write-Host "`n"
Write-Host "Please Wait While Configuration Manager Updates Data..." -ForegroundColor Yellow
Sleep 30

# Query all collections for destination PC PC
$DestinationCollectionIDs = Get-CMCollectionOfDevice -Computer $DestinationComputerName -SiteCode $SiteCode -SiteServer $ProviderMachineName | Where CollectionID -Like "" <# DATA_REQUIRED : Site Code. May need wildcard at end #> | Select -ExpandProperty CollectionID

# Reduce the query results to just Direct associations
ForEach ($DestinationCollectionID In $DestinationCollectionIDs) { 

If ((Get-CMCollectionMember -CollectionId $DestinationCollectionID -ResourceId $DestinationComputerID).IsDirect -eq $True) { $DestinationDirectAssociations += $DestinationCollectionID }

}

# Translate reduced query to friendly names
$DestinationCollectionNames = ForEach ($DestinationCollectionID In $DestinationDirectAssociations) {Get-CMCollection -Id $DestinationCollectionID | Select -ExpandProperty Name}

# Clear that nonsense
cls

# User validation of data
Write-Host "`n"
Write-Host "`n"
Write-Host "						MANUAL DATA VALIDATION" -ForegroundColor Red
Write-Host "`n"
Write-Host "`n"
Write-Host "Source Computer ($SourceComputerName) Configuration Manager Direct Associations Listed Below..."
Write-Host "	Note: These have been removed from the original PC" -ForegroundColor Yellow
Write-Host "`n"
ForEach ($SourceCollectionName In $SourceCollectionNames) {Write-Host "        $SourceCollectionName"}
Write-Host "`n"
Write-Host "Destination Computer ($DestinationComputerName) Configuration Manager Direct Associations Listed Below..."
Write-Host "`n"
ForEach ($DestinationCollectionName In $DestinationCollectionNames) {Write-Host "        $DestinationCollectionName"}
Write-Host "`n"
Write-Host "If There Are Any Discrepancies With The Source And Destination Computers, Check The"
Write-Host "Collections Manually To Ensure The Process Completed Successfully."
Write-Host "`n"
Read-Host "Press Enter To Exit..."
Write-Host "`n"

}

Else {

Write "Aborting..."
Sleep 2

}