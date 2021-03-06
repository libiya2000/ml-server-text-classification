

[CmdletBinding()]
param(
[parameter(Mandatory=$false, Position=1)]
[ValidateNotNullOrEmpty()] 
[string]$serverName,

[parameter(Mandatory=$false, Position=2)]
[ValidateNotNullOrEmpty()] 
[string]$username,

[parameter(Mandatory=$false, Position=3)]
[ValidateNotNullOrEmpty()] 
[string]$password,

[parameter(Mandatory=$false, Position=4)]
[ValidateNotNullOrEmpty()] 
[string]$Prompt
)


###Check to see if user is Admin

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] "Administrator")
        
if ($isAdmin -eq 'True')
{
# {
#     ##Check to see is Advanced Analytics is installed
# $Query = 
#     "SELECT CASE WHEN SERVERPROPERTY('IsAdvancedAnalyticsInstalled') = 1 THEN 'Yes' ELSE 'No' END"
#     $IsAdv = Invoke-Sqlcmd -Query $Query 
#     $IsAdv  = $IsAdv.Item(0)
#     if($IsAdv -eq 'No') 
#     {
#     Write-Host
#     ("To run this solution , Please install SQLAdvanced Analytics")
#     Start-Sleep -s 20
#     }
#     ELSE 
# {
 #   Write-Host ("Advanced Analytics is present, set up can continue")

$startTime = Get-Date

$setupLog = "c:\tmp\text_setup_log.txt"
Start-Transcript -Path $setupLog -Append
$startTime = Get-Date
Write-Host  
("Start time:$startTime")

#$Prompt= if ($Prompt -match '^y(es)?$') {'Y'} else {'N'}
$Prompt = 'N'





##Change Values here for Different Solutions 
$SolutionName = "TextClassification"
$SolutionFullName = "ml-server-text-classification"
$Shortcut = "SolutionHelp.url"

### DON'T FORGET TO CHANGE TO MASTER LATER...
$Branch = "master" 
$InstallR = 'Yes'  ## If Solution has a R Version this should be 'Yes' Else 'No'
$InstallPy = 'Yes' ## If Solution has a Py Version this should be 'Yes' Else 'No'
$SampleWeb = 'No' ## If Solution has a Sample Website  this should be 'Yes' Else 'No' 
$EnableFileStream = 'No' ## If Solution Requires FileStream DB this should be 'Yes' Else 'No' 
$UsePowerBI = 'No' ## If Solution uses PowerBI
$Prompt = 'N'
$MixedAuth = 'No'
$InstallPowerShellUpdate = 'No'

###These probably don't need to change , but make sure files are placed in the correct directory structure 
$solutionTemplateName = "Solutions"
$solutionTemplatePath = "C:\" + $solutionTemplateName
$checkoutDir = $SolutionName
$SolutionPath = $solutionTemplatePath + '\' + $checkoutDir
$desktop = "C:\Users\Public\Desktop\"
$scriptPath = $SolutionPath + "\Resources\ActionScripts\"
$SolutionData = $SolutionPath + "\Data\"

###If not run as DSVM , prompt for UI and PW 

if ($SampleWeb -eq "Yes")             
    {    
    if([string]::IsNullOrEmpty($username)) 
        {
        $Credential = $Host.ui.PromptForCredential("Need credentials", "Please supply an user name and password to configure SQL for mixed mode authentication.", "", "")
        $username = $credential.Username
        $password = $credential.GetNetworkCredential().password 
        }  
    }

##########################################################################
#Clone Data from GIT
##########################################################################

$clone = "git clone --branch $Branch --single-branch https://github.com/Microsoft/$SolutionFullName $solutionPath"

if (Test-Path $SolutionPath) 
    {
    (Write-Host "Solution has already been cloned")
    }
else 
    {
    Invoke-Expression $clone
    }

If ($InstalR -eq 'Yes')
    {
    Write-Host 
    ("Installing R Packages")
    Set-Location "C:\Solutions\$SolutionName\Resources\ActionScripts\"
# install R Packages
    Rscript install.R 
    }


##Check DSVM Version 
Set-Location $scriptPath
invoke-expression .\CheckDSVMVersion.bat




#################################################################
##DSVM Does not have SQLServer Powershell Module Install or Update 
#################################################################


if ($InstallPowerShellUpdate -eq 'Yes')
    {


    if (Get-Module -ListAvailable -Name SQLServer) 
        {
        Write-Host 
        ("Updating SQLServer Power Shell Module")
        Update-Module -Name "SQLServer" -MaximumVersion 21.0.17199
        Import-Module -Name SqlServer -MaximumVersion 21.0.17199 -Force
        }
    Else 
        {
        Write-Host 
        ("Installing SQLServer Power Shell Module")
        Install-Module -Name SqlServer -RequiredVersion 21.0.17199 -Scope AllUsers -AllowClobber -Force}
        Import-Module -Name SqlServer -MaximumVersion 21.0.17199 -Force 
        }

## if FileStreamDB is Required Alter Firewall ports for 139 and 445
if ($EnableFileStream -eq 'Yes')
    {
    netsh advfirewall firewall add rule name="Open Port 139" dir=in action=allow protocol=TCP localport=139
    netsh advfirewall firewall add rule name="Open Port 445" dir=in action=allow protocol=TCP localport=445
    Write-Host 
    ("Firewall has been opened for filestream access")
    }

############################################################################################
#Configure SQL to Run our Solutions 
############################################################################################


$Query = "SELECT SERVERPROPERTY('ServerName')"
$si = invoke-sqlcmd -Query $Query
$si = $si.Item(0)

$serverName = if([string]::IsNullOrEmpty($servername)) {$si} Else {$ServerName}
Write-Host 
("Servername set to $serverName")

### Change Authentication From Windows Auth to Mixed Mode 
If ($MixedAuth -eq 'Yes')
    {
    Write-Host 
    ("Changing SQL Authentication to Mixed Mode")
    Invoke-Sqlcmd -Query "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2;" -ServerInstance "LocalHost" 

    $Query = "CREATE LOGIN $username WITH PASSWORD=N'$password', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF"
    Invoke-Sqlcmd -Query $Query -ErrorAction SilentlyContinue

    $Query = "ALTER SERVER ROLE [sysadmin] ADD MEMBER $username"
    Invoke-Sqlcmd -Query $Query -ErrorAction SilentlyContinue
    }

### Allow Running of External Scripts , this is to allow R Services to Connect to SQL
    Write-Host 
    ("Configuring SQL to allow running of External Scripts")
    Invoke-Sqlcmd -Query "EXEC sp_configure  'external scripts enabled', 1"

### Force Change in SQL Policy on External Scripts 
    Invoke-Sqlcmd -Query "RECONFIGURE WITH OVERRIDE" 
    Write-Host 
    ("SQL Server Configured to allow running of External Scripts")

### Enable FileStreamDB if Required by Solution 
if ($EnableFileStream -eq 'Yes') 
    {
    $instance = "MSSQLSERVER"
    $wmi = Get-WmiObject -Namespace "ROOT\Microsoft\SqlServer\ComputerManagement14" -Class FilestreamSettings | where-object {$_.InstanceName -eq $instance}
    $wmi.EnableFilestream(3, $instance) 
    Restart-Service -Name "MSSQ*" -Force

#Import-Module "sqlps" -DisableNameChecking
    Invoke-Sqlcmd "EXEC sp_configure filestream_access_level, 2"
    Invoke-Sqlcmd "RECONFIGURE WITH OVERRIDE"
    Stop-Service "MSSQ*"
    Start-Service "MSSQ*"
    }
ELSE
    { 
    Write-Host 
    ("Restarting SQL Services")
    ### Changes Above Require Services to be cycled to take effect 
    ### Stop the SQL Service and Launchpad wild cards are used to account for named instances  
    Restart-Service -Name "MSSQ*" -Force
}


###Install SQL CU 

Write-Host 
("Checking SQL CU Version If Behind install Latest CU")

$Query = "SELECT CASE 
WHEN  
    (RIGHT(CAST(SERVERPROPERTY('ProductUpdateLevel') as varchar),1) >= 1)
    AND 
    (SELECT Left(CAST(SERVERPROPERTY('productversion') as varchar),2))>= 14
THEN 1 
ELSE 0 
END "
$RequireCuUpdate = Invoke-Sqlcmd -Query $Query
$RequireCuUpdate = $RequireCuUpdate.Item(0)

##$RequireCuUpdate = "1"

IF ($RequireCuUpdate -eq 0) 
    {
    WRITE-Host 
    ("Downloading Latest CU")

##cu1 
##    Start-BitsTransfer -Source "http://download.windowsupdate.com/d/msdownload/update/software/updt/2017/12/sqlserver2017-kb4038634-x64_a75ab79103d72ce094866404607c2e84ae777d43.exe" -Destination c:\tmp\sqlserver2017CU1.exe

##cu3  
 ## Start-BitsTransfer -Source "http://download.windowsupdate.com/d/msdownload/update/software/updt/2018/01/sqlserver2017-kb4052987-x64_a533b82e49cb9a5eea52cd2339db18aa4017587b.exe" -Destination c:\tmp\sqlserver2017CU3.exe 

##CU4 
    Start-BitsTransfer -Source "http://download.windowsupdate.com/c/msdownload/update/software/updt/2018/03/sqlserver2017-kb4056498-x64_d1f84e3cfbda5006301c8e569a66a982777a8a75.exe" -Destination c:\tmp\sqlserver2017CU4.exe   
    $CU = "sqlserver2017CU4.exe"
    Write-Host 
    ("CU has been Downloaded now to install , go have a cocktail as this takes a while")
  
    Invoke-Expression "c:\tmp\$CU  /q /IAcceptSQLServerLicenseTerms /IACCEPTPYTHONLICENSETERMS /IACCEPTROPENLICENSETERMS /Action=Patch /InstanceName=MSSQLSERVER /FEATURES=SQLEngine,ADVANCEDANALYTICS,SQL_INST_MR,SQL_INST_MPY"    
 
   Write-Host 
    ("CU Install has commenced")
    Write-Host 
    ("Powershell time to take a nap")
    Start-Sleep -s 1000
    Write-Host 
    ("Powershell nap time is over")
    ###Unbind Python 
    Set-Location $scriptPath
    invoke-expression ".\UpdateMLServer.bat"
    Write-Host "ML Server has been updated"
    }
ELSE 
    {
    Write-Host 
    ("CU is Current")
    }

####Run Configure SQL to Create Databases and Populate with needed Data
    $ConfigureSql = "C:\Solutions\$SolutionName\Resources\ActionScripts\ConfigureSQL.ps1  $ServerName $SolutionName $InstallPy $InstallR $EnableFileStream"
    Invoke-Expression $ConfigureSQL 
    Write-Host 
    ("Done with configuration changes to SQL Server")

If ($UsePowerBI -eq 'Yes') 
{
    Write-Host 
    ("This Solutions employees Power BI reports, so we need to install the latest version of Power BI")
    # Download PowerBI Desktop installer
    Start-BitsTransfer -Source "https://go.microsoft.com/fwlink/?LinkId=521662&clcid=0x409" -Destination powerbi-desktop.msi

    # Silently install PowerBI Desktop
    msiexec.exe /i powerbi-desktop.msi /qn /norestart  ACCEPT_EULA=1

    if (!$?) 
    {
    Write-Host -ForeGroundColor Red 
    ("Error installing Power BI Desktop. Please install latest Power BI manually.")
    }
}

##Create Shortcuts and Autostart Help File 
    Copy-Item "$ScriptPath\$Shortcut" C:\Users\Public\Desktop\
    Copy-Item "$ScriptPath\$Shortcut" "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\"
    Write-Host 
    ("Help Files Copied to Desktop")

$WsShell = New-Object -ComObject WScript.Shell
$shortcut = $WsShell.CreateShortcut($desktop + $checkoutDir + ".lnk")
$shortcut.TargetPath = $solutionPath
$shortcut.Save()

# install modules for sample website
if($SampleWeb  -eq "Yes")
{
Set-Location $SolutionPath\Website\
.\npm install
(Get-Content $SolutionPath\Website\server.js).replace('XXYOURSQLPW', $password) | Set-Content $SolutionPath\Website\server.js
(Get-Content $SolutionPath\Website\server.js).replace('XXYOURSQLUSER', $username) | Set-Content $SolutionPath\Website\server.js
}

##Launch HelpURL 
Start-Process "https://microsoft.github.io/$SolutionFullName/"



$endTime = Get-Date

Write-Host 
("$SolutionFullName Workflow Finished Successfully!")

$Duration = New-TimeSpan -Start $StartTime -End $EndTime 
Write-Host 
("Total Deployment Time = $Duration") 

Stop-Transcript

    ## Close Powershell if not run on 
    if ($baseurl)
    {Exit-PSHostProcess
    EXIT}

}
#} uncomment this brace if we look for advanced anaytics 
ELSE
    {
    Write-Host 
    ("To install this Solution you need to run Powershell as an Administrator. This program will close automatically in 20 seconds")
    Start-Sleep -s 20
    Exit-PSHostProcess
    EXIT 
    }






