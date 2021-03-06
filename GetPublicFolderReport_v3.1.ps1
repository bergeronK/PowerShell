<#
 Name: GetPublicFolderReport.ps1
 Author: Craig Threadgill
 Version: 3.1
 Date: 11/16/2015
 
 Description:  
 This script exports key public folder statistics, including mail settings.
 For best performance, run this script on an Exchange Server with 
 a local copy of the most Public Folder replicas.
 This script will perform much slower when gathering folder statistics from remote servers.
 
 Because of Exchange version differences, if the organization has both Exchange 2007 and 2010,
 then the script must be run from both versions of Exchange PowerShell in order to get 
 statistics for each.
 
 Added parameters:
 -OrgStatistics
 	This option will pull the full report, including public folder statistics from all replicas
	(If organization has both 2007 and 2010, this needs to be run from each version of Exchange PowerShell)
 
 -LocalStatisticsOnly
 	This option will only query for public folder statistics on the local server.  If the statistics
	are unavailable, then it will log that the statistics were skipped.  This option significantly 
	reduced the amount of time the script will run in a very large environment, however it 
	is up to the user to run this from each public folder server that statistics are desired.
 
 -SkipStatistics
 	This option skips gathering public folder statistics completely.  This parameter will complete
	the script the fastest, but will only provide public folder on the hierarchy and mail enabled
	public folders.
	
If no parameters are used, then a menu will prompt the user to select one of these options.
 
#>
param
(
 [Parameter(Mandatory = $false)]
 [switch]$OrgStatistics,
 [Parameter(Mandatory = $false)]
 [switch]$LocalStatisticsOnly,
  [Parameter(Mandatory = $false)]
 [switch]$SkipStatistics
)

If (!$OrgStatistics -and !$LocalStatisticsOnly -and !$SkipStatistics) {
$caption = "Choose Action";
$message = "Select from these options:";
$1st = new-Object System.Management.Automation.Host.ChoiceDescription "&Organization Wide Statistics","Organization Wide Statistics";
$2nd = new-Object System.Management.Automation.Host.ChoiceDescription "&Local Statistics Only","Local Statistics Only";
$3rd = new-Object System.Management.Automation.Host.ChoiceDescription "&No Statistics","No Statistics";
$quit = new-object System.Management.Automation.Host.ChoiceDescription "&Quit","Quit";
$choices = [System.Management.Automation.Host.ChoiceDescription[]]($1st,$2nd,$3rd,$Quit);
$answer = $host.ui.PromptForChoice($caption,$message,$choices,3)

switch ($answer){
    0 {"You entered Organization Statistics"; break}
    1 {"You entered Local Statistics"; break}
	2 {"You entered No Statistics"; break}
    3 {"You entered Quit"; break}
}
	if ($answer -eq "0") {$OrgStatistics  = $True}
	if ($answer -eq "1") {$LocalStatisticsOnly = $True}
	if ($answer -eq "2") {$SkipStatistics = $True}
	if ($answer -eq "3") {Break}
}

If ($LocalStatisticsOnly -and $SkipStatistics) {Write-Host -ForegroundColor Red "LocalStatistics and SkipStatistics cannot be combined. Please choose only one option.";break}

$PSHost = (get-pssession).computername
if (!$PSHost) {$PSHost = $env:COMPUTERNAME}
$ExchangeServer = Get-ExchangeServer $PSHost 
$PFDBHost = Get-PublicFolderDatabase -Server $PSHost -ErrorAction Silentlycontinue
if ($PFDBHost) {$PFDB = $PFDBHost.name}
if ($ExchangeServer.AdminDisplayVersion -like "Version 8.*") {$Version = "2007"}
if ($ExchangeServer.AdminDisplayVersion -like "Version 14.*") {$Version = "2010"}
if ($ExchangeServer.AdminDisplayVersion -like "Version 15.*") {Write-Host -ForegroundColor Red "Exchange 2013 detected.  This script will only run from Exchange 2007/2010.";break}
Write-Host -ForegroundColor Cyan "Script is running from Exchange version $version. "
Write-Host -ForegroundColor Yellow "If your organization has both 2007 and 2010, to get full results, run this script from both."

$Date = $(Get-Date -f MMddyyyy)
$Output = New-Item -type file .\PublicFolderReport_$Date.csv -Force
Add-Content $Output "Identity,EntryID,Name,MailEnabled,HiddenFromAB,PrimarySMTP,GUID,Alias,ItemCount,ItemSizeInBytes,Quota,FolderType,LastUserAccessTime,LastUserModificationTime" -Encoding UTF8

Write-Host -ForegroundColor Green "Step 1: Getting a list of Public Folder databases in the organization"
$AllPFDBs = Get-PublicFolderDatabase | select name,server

Write-Host  -ForegroundColor Green "Step 2: Gathering a list of all public folders in the org. This may take a while...`n"
Write-Host  "`n"

$PFs = Get-PublicFolder "\" -Recurse -ResultSize Unlimited | Where {$_.Name -ne "IPM_SUBTREE"} | Select Identity,Name,Replicas,ProhibitPostQuota,EntryID,MailEnabled,HiddenFromAddressListsEnabled,FolderType
$count = 0
$totalfolders = $PFs.count
Write-Host -ForegroundColor Green "Step 2: Complete!`n"
Write-Host -ForegroundColor Green "Found $totalfolders in organization. Begin processing Folder information."

Foreach($PF in $PFs){
 If ($PF.Identity.ToString() -ne "\") {
  # Create Progress bar
  $statusstring = "$count of $totalfolders"
  write-Progress -Activity "Gathering Public Folder Information." -Status $statusstring -PercentComplete ($count/$totalfolders*100)

  $TargetServer = ""
  $TargetDB = ""
  $PFStats = ""
  $PFIdentity = $PF.Identity.ToString()
  $count ++
  Write-host -ForegroundColor White "`nProcessing Folder $count - $PFIdentity"

# Create variables

  $Replicas = $PF.Replicas | select Name,Parent
  $2010Replicas = $replicas | where {$_.parent -eq "Databases"}
  $2007Replicas = $Replicas | where {$_.parent -like "*\*"}
  
  Write-Host "2010Replicas "($2010Replicas | select Name)
  Write-Host "2007Replicas "($2007Replicas | select Name,Parent)
################################
# Get Public Folder Statistics #
################################
 
      # check if replicas are 2010
	  If ($Version -eq "2010") {
	  	  # Apply optional script parameters
		  If ($LocalStatisticsOnly) {
		  Write-Host -ForegroundColor Cyan "Only gathering Local Statistics"
		  $PFStats = Get-PublicFolderStatistics -Identity $PF.Identity -Server $PSHost -ErrorAction Silentlycontinue
		  	if (!$PFstats) {
			Write-Host -ForegroundColor Yellow "No local statistics found for $PFIdentity. Skipping statistics."
			$PFStats = "LocalStatsUnavailable"
			}
		  }	  
		  ElseIf ($SkipStatistics) {
		  Write-Host -ForegroundColor Cyan "Skipping Statistics"
		  $PFStats = "SkippedUnavailable"
		  }
		  
		  # Checking to see if local 2010 server has a replica
		  ElseIf ($Replicas -match $PFDB) {
		  Write-Host -ForegroundColor Cyan "Local Replica found"
		  $PFStats = Get-PublicFolderStatistics -Identity $PF.Identity
  		  }
		  ElseIf ($2010Replicas.count -gt "1") {
		  $TargetDB = $2010Replicas[0].name
		  $TargetServer = $AllPFDBs | where {$_.name -match $TargetDB} | select Server
		  $TargetServerName = $TargetServer.Server.Name
		  Write-Host -ForegroundColor Yellow "Multiple Remote replicas found.  Using $TargetServerName"
		  $PFStats = Get-PublicFolderStatistics -Identity $PF.Identity -Server $TargetServerName
		  }
		  ElseIf ($2010Replicas) {
		  $TargetDB = $2010Replicas.name
		  $TargetServer = $AllPFDBs | where {$_.name -match $TargetDB} | select Server
		  $TargetServerName = $TargetServer.Server.Name
		  Write-Host -ForegroundColor Yellow "Remote replica found on $TargetServerName"
		  $PFStats = Get-PublicFolderStatistics -Identity $PF.Identity -Server $TargetServerName
		  }
		  ElseIf ($2007Replicas) {
		  Write-Host -ForegroundColor Magenta "Replica only found on Exchange 2007.  Statistics not available from Exchange 2010 PowerShell."
		  $PFStats = "Exchange2007-Unavailable"
		  }
	  }
	  
	  # replicas use 2007 format
	  if ($Version -eq "2007") {
	  	  # Apply optional script parameters
		  If ($LocalStatisticsOnly) {
		  Write-Host -ForegroundColor Cyan "Only gathering Local Statistics"
		  $PFStats = Get-PublicFolderStatistics -Identity $PF.Identity -Server $PSHost -ErrorAction Silentlycontinue
		  	if (!$PFstats) {
			Write-Host -ForegroundColor Yellow "No local statistics found for $PFIdentity. Skipping statistics."
			$PFStats = "LocalStatsUnavailable"
			}
		  }	  
		  ElseIf ($SkipStatistics) {
		  Write-Host -ForegroundColor Cyan "Skipping Statistics"
		  $PFStats = "SkippedUnavailable"
		  }
		  
		  ElseIf ($2007Replicas.count -gt "1") {
		  $TargetServerFull = $2007Replicas[0].Parent.ToString()
		  $TargetServerFull = $TargetServerFull.Split("\")
		  $TargetServer = $TargetServerFull[0]
		  Write-Host -ForegroundColor Yellow "Replica found on $TargetServer"
		  $PFStats = Get-PublicFolderStatistics -Identity $PF.Identity -Server $TargetServer -errorAction Silentlycontinue
			}
		  ElseIf ($2007Replicas) {
		  $TargetServerFull = $2007Replicas.Parent.ToString()
		  $TargetServerFull = $TargetServerFull.Split("\")
		  $TargetServer = $TargetServerFull[0]
		  Write-Host -ForegroundColor Yellow "Replica found on $TargetServer"
		  $PFStats = Get-PublicFolderStatistics -Identity $PF.Identity -Server $TargetServer -errorAction Silentlycontinue
			}
		  ElseIf ($2010Replicas) {
		  Write-Host -ForegroundColor Magenta "Replica only found on Exchange 2010.  Statistics not available from Exchange 2007 PowerShell."
		  $PFStats = "Exchange2010-Unavailable"
			}
	  }
	  
	  # No conditions met.  Log status unavailable.
	  if (!$PFStats) {  Write-Host -ForegroundColor Yellow "Public Folder Statistics unavailable."
      $PFStats = "Unknown-Unavailable"
	  }
	}

##################

  $PFQuotaRaw = $PF.ProhibitPostQuota
  if (!$PFQuotaRaw) {$PFQuota = "InheritFromDB"}
    Else {$PFQuota = $PFQuotaRaw.Value.ToBytes()}
  $EntryID = $PF.EntryID
  $Name = $PF.Name
  $MailEnabled = $PF.MailEnabled
  $HiddenFromAB = $PF.HiddenFromAddressListsEnabled
  	  if ($PFStats -like "*Unavailable") {
	  $ItemCount = $PFStats
	  $ItemSize = "Unavailable"
	  }
	  Else {
	  $ItemCount = $PFStats.ItemCount
	  $ItemSize = $PFStats.TotalItemSize.Value.ToBytes()
	  }
  $FolderType = $PF.FolderType
  $LastUserAccessTime = $PFStats.LastUserAccessTime
  $LastUserModificationTime = $PFStats.LastUserModificationTime
  $CreationTime = $PFStats.CreationTime
  $PFPrimarySMTP = ""
  $PFGUID = ""
  $Alias = ""
  # Get Mail Public Folder info
  if ($MailEnabled -eq 'True') {$PFMail = Get-MailPublicFolder $PF.Identity  -ErrorAction silentlycontinue
  $PFPrimarySMTP = $PFMail.PrimarySMTPAddress.ToString()
  $PFGUID = $PFMail.GUID
  $Alias = $PFMail.Alias
  write-host -fore Green "Mail enabled folder processed: $PFPrimarySMTP"
  }

# Writing data to log file
Add-Content $Output """$PFIdentity"",$EntryID,""$Name"",$MailEnabled,$HiddenFromAB,$PFPrimarySMTP,$PFGUID,""$Alias"",$ItemCount,""$ItemSize"",""$PFQuota"",$FolderType,$LastUserAccessTime,$LastUserModificationTime" -Encoding UTF8
 } 
 $SumCount = $count ++
Add-Content $Output ",,,,,,,,,=SUM(J2:J$SumCount),,,,,"
Write-Host -ForegroundColor Green "`nScript complete. Processed $count folders. Results output to $Output"
 
