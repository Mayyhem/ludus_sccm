# Shared Windows PowerShell 5.1 helpers. Importing this module does not collect
# data, create files, or change SCCM. The calling role chooses each operation.
Set-StrictMode -Version Latest
$script:SccmLogPath = $null

function Set-SccmLog {
    param([Parameter(Mandatory)][string]$Path)
    $script:SccmLogPath = $Path
    $directory = Split-Path -Parent $Path
    [void][System.IO.Directory]::CreateDirectory($directory)
}

function Write-SccmLog {
    param([Parameter(Mandatory)][string]$Message, [string]$Level = 'INFO')
    $line = '{0} {1} {2}' -f [DateTime]::UtcNow.ToString('s'), $Level, $Message
    Write-Information $line -InformationAction Continue
    if ($script:SccmLogPath) {
        Add-Content -LiteralPath $script:SccmLogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    # Without a configured file, the caller still receives information output.
}

function Stop-SccmWork {
    param([Parameter(Mandatory)][string]$Message)
    Write-SccmLog $Message 'ERROR'
    $failure = New-Object System.InvalidOperationException($Message)
    $failure.Data['SccmFatal'] = $true
    throw $failure
}

function Wait-SccmCondition {
    param(
        [Parameter(Mandatory)][scriptblock]$Test,
        [Parameter(Mandatory)][string]$Description,
        [int]$TimeoutMinutes = 180,
        [int]$PollSeconds = 30,
        [switch]$RetryReadErrors
    )
    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    do {
        try {
            if (& $Test) {
                Write-SccmLog "Ready: $Description"
                return
            }
            Write-SccmLog "Waiting: $Description"
        } catch {
            if ($_.Exception.Data.Contains('SccmFatal')) { throw }
            if (-not $RetryReadErrors) { throw }
            Write-SccmLog "Read failed while waiting for ${Description}: $($_.Exception.Message)" 'WARNING'
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            Stop-SccmWork "Timed out: $Description. Review the deployment log, CMUpdate.log, ConfigMgrPrereq.log, sitecomp.log, and failovermgr.log."
        }
        Start-Sleep -Seconds $PollSeconds
    } while ($true)
}

function Invoke-SccmRemote {
    param([string]$ComputerName, [scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())
    if (($ComputerName -split '\.')[0] -ieq $env:COMPUTERNAME -or $ComputerName -in @('.', 'localhost')) {
        Write-SccmLog "Running a local check on $ComputerName" 'DEBUG'
        return & $ScriptBlock @ArgumentList
    }
    Write-SccmLog "Running a Windows management operation on $ComputerName"
    Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
}

function Get-SccmProviderData {
    param([string]$Provider, [string]$SiteCode, [string]$ClassName, [string]$Filter = '')
    $session = New-CimSession -ComputerName $Provider -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop
    try {
        $parameters = @{CimSession = $session; Namespace = "root\SMS\site_$SiteCode"; ClassName = $ClassName; ErrorAction = 'Stop'}
        if ($Filter) { $parameters.Filter = $Filter }
        # No filter means every row in this particular provider class is needed.
        Get-CimInstance @parameters
    } finally {
        Remove-CimSession $session
    }
}

function Connect-SccmSite {
    param([string]$SiteCode, [string]$Provider)
    $modulePath = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
    if (-not (Test-Path -LiteralPath $modulePath)) { Stop-SccmWork "Configuration Manager console module is missing: $modulePath" }
    Import-Module $modulePath -Force -Global -ErrorAction Stop
    if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        [void](New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Provider -Scope Global -ErrorAction Stop)
    }
    # Reusing the existing CMSite drive is routine and does not change a site.
    Set-Location "${SiteCode}:\"
}

function Get-SccmInstalledApplications {
    # Registry inventory avoids Win32_Product, whose query can repair MSI
    # installations and therefore is not a read-only version check.
    @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] })
}

function Assert-SccmMicrosoftSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        Stop-SccmWork "Installer does not have a valid Microsoft signature: $Path"
    }
    Write-SccmLog "Verified Microsoft signature: $Path"
}

function Invoke-SccmInstaller {
    param([string]$Path, [string]$Arguments, [int[]]$AcceptedExitCodes = @(0, 3010))
    Assert-SccmMicrosoftSignature $Path
    Write-SccmLog "Starting installer $Path"
    if ([IO.Path]::GetExtension($Path) -ieq '.msi') {
        $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/i `"$Path`" $Arguments" -WindowStyle Hidden -PassThru -Wait
    } else {
        $process = Start-Process -FilePath $Path -ArgumentList $Arguments -WindowStyle Hidden -PassThru -Wait
    }
    if ($process.ExitCode -notin $AcceptedExitCodes) { Stop-SccmWork "Installer $Path failed with exit code $($process.ExitCode)." }
    Write-SccmLog "Installer finished with exit code $($process.ExitCode): $Path"
    return ($process.ExitCode -eq 3010)
}

function Remove-SccmPrerequisitePackage {
    param([psobject]$Application)
    Write-SccmLog "Removing incompatible prerequisite $($Application.DisplayName) $($Application.DisplayVersion)"
    if ($Application.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') {
        $process = Start-Process "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $($Application.PSChildName) /qn /norestart" -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) { Stop-SccmWork "Cannot remove prerequisite $($Application.DisplayName): exit $($process.ExitCode)." }
        return ($process.ExitCode -eq 3010)
    }
    # ADK and WinPE are bundle installers, rather than ordinary MSI products.
    $match = [regex]::Match([string]$Application.UninstallString, '^"(?<path>[^"\r\n]+\.exe)"')
    if (-not $match.Success) { Stop-SccmWork "Cannot safely identify the uninstaller for $($Application.DisplayName). Remove it manually and rerun." }
    return Invoke-SccmInstaller -Path $match.Groups['path'].Value -Arguments '/uninstall /quiet /norestart'
}

function Install-SccmPrerequisites {
    param([string]$WorkDirectory, [bool]$PrepareAdk = $false)
    $hasChanged = $false
    $needsRestart = $false
    $dotnet = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop
    if ($dotnet.Release -lt 528040) { Stop-SccmWork '.NET Framework 4.8 is required. Install it and restart this server before rerunning.' }
    $applications = Get-SccmInstalledApplications
    $driver = @($applications | Where-Object DisplayName -eq 'Microsoft ODBC Driver 18 for SQL Server')
    if ($driver.Count -ne 1 -or $driver[0].DisplayVersion -ne '18.6.2.1') {
        $needsRestart = (Invoke-SccmInstaller "$WorkDirectory\vc-2022-x64.exe" '/install /quiet /norestart' @(0, 1638, 3010)) -or $needsRestart
        foreach ($application in $driver) { $needsRestart = (Remove-SccmPrerequisitePackage $application) -or $needsRestart }
        $needsRestart = (Invoke-SccmInstaller "$WorkDirectory\odbc-18.6.2.1.msi" 'IACCEPTMSODBCSQLLICENSETERMS=YES /qn /norestart') -or $needsRestart
        $hasChanged = $true
    } else {
        Write-SccmLog 'ODBC 18.6.2.1 is already installed.'
    }
    if ($PrepareAdk) {
        $adk = @($applications | Where-Object DisplayName -eq 'Windows Assessment and Deployment Kit')
        $pe = @($applications | Where-Object DisplayName -like 'Windows Assessment and Deployment Kit Windows Preinstallation Environment*')
        $hasCorrectAdk = $adk.Count -eq 1 -and $adk[0].DisplayVersion -eq '10.1.26100.9457'
        $hasCorrectPe = $pe.Count -eq 1 -and $pe[0].DisplayVersion -like '10.1.26100.*'
        if (-not $hasCorrectAdk -or -not $hasCorrectPe) {
            foreach ($application in $pe) { $needsRestart = (Remove-SccmPrerequisitePackage $application) -or $needsRestart }
            foreach ($application in $adk) { $needsRestart = (Remove-SccmPrerequisitePackage $application) -or $needsRestart }
            $needsRestart = (Invoke-SccmInstaller "$WorkDirectory\adk-10.1.26100.9457.exe" '/quiet /norestart /ceip off /features OptionId.DeploymentTools OptionId.UserStateMigrationTool') -or $needsRestart
            $needsRestart = (Invoke-SccmInstaller "$WorkDirectory\winpe-10.1.26100.exe" '/quiet /norestart /ceip off /features OptionId.WindowsPreinstallationEnvironment') -or $needsRestart
            $hasChanged = $true
        } else {
            Write-SccmLog 'The supported ADK and WinPE add-on are already installed.'
        }
    } else {
        Write-SccmLog 'This role does not need the ADK.'
    }
    $verified = @(Get-SccmInstalledApplications | Where-Object DisplayName -eq 'Microsoft ODBC Driver 18 for SQL Server')
    if ($verified.Count -ne 1 -or $verified[0].DisplayVersion -ne '18.6.2.1') { Stop-SccmWork 'ODBC installation did not produce the expected version.' }
    if ($PrepareAdk) {
        $installed = @(Get-SccmInstalledApplications)
        $verifiedAdk = @($installed | Where-Object { $_.DisplayName -eq 'Windows Assessment and Deployment Kit' -and $_.DisplayVersion -eq '10.1.26100.9457' })
        $verifiedPe = @($installed | Where-Object { $_.DisplayName -like 'Windows Assessment and Deployment Kit Windows Preinstallation Environment*' -and $_.DisplayVersion -like '10.1.26100.*' })
        if ($verifiedAdk.Count -ne 1 -or $verifiedPe.Count -ne 1) { Stop-SccmWork 'ADK or WinPE installation did not produce the expected supported versions.' }
        Write-SccmLog 'Verified installed ADK and WinPE versions.'
    }
    # Hosts without ADK responsibilities were already explained above.
    return @{Changed = $hasChanged; RebootRequired = $needsRestart}
}

function ConvertTo-SccmAdminShare {
    param([string]$ComputerName, [string]$Path)
    $match = [regex]::Match($Path, '^(?<drive>[A-Za-z]):\\(?<tail>.*)$')
    if (-not $match.Success) { Stop-SccmWork "Expected an absolute Windows drive path, got $Path" }
    return '\\{0}\{1}$\{2}' -f $ComputerName, $match.Groups['drive'].Value, $match.Groups['tail'].Value
}

function Get-SccmHostSiteState {
    param([string]$ComputerName)
    Invoke-SccmRemote $ComputerName {
        $setup = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\SMS\Setup' -ErrorAction Stop
        $service = Get-Service SMS_EXECUTIVE -ErrorAction Stop
        [pscustomobject]@{Version = [string]$setup.'Full Version'; ServiceStatus = [string]$service.Status}
    }
}

function Test-SccmPassiveReady {
    param([object[]]$Stages, [string]$InstalledVersion, [string]$ExpectedVersion)
    $requiredStages = @($Stages | Where-Object { $_.StageId -in @(11, 12, 13, 14) })
    # Stage 15 is promotion, which must remain unrequested on a passive server.
    return $requiredStages.Count -eq 4 -and
        @($requiredStages | Where-Object StageCompleted -ne 2).Count -eq 0 -and
        [version]$InstalledVersion -ge [version]$ExpectedVersion
}

function Wait-SccmSiteReady {
    param([string]$Provider, [string]$ParentSiteCode, [string]$SiteCode, [string]$Server, [int]$TimeoutMinutes = 180)
    Wait-SccmCondition -Description "site $SiteCode on $Server has finished installation" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $sites = @(Get-SccmProviderData $Provider $ParentSiteCode 'SMS_Site' "SiteCode='$SiteCode'")
        if ($sites.Count -ne 1 -or $sites[0].Status -ne 1) { return $false }
        $actual = Get-SccmHostSiteState $Server
        return $actual.ServiceStatus -eq 'Running' -and [version]$actual.Version -ge [version]$sites[0].Version
    }
}

function Wait-SccmPassiveReady {
    param([string]$Provider, [string]$SiteCode, [string]$Server, [int]$TimeoutMinutes = 180)
    Wait-SccmCondition -Description "passive server $Server is installed and ready" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $stages = @(Get-SccmProviderData $Provider $SiteCode 'SMS_HA_SiteServerTopLevelMonitoring' "SiteServerName='$Server'")
        $site = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' "SiteCode='$SiteCode'")[0]
        $actual = Get-SccmHostSiteState $Server
        return Test-SccmPassiveReady $stages $actual.Version $site.Version
    }
}

function Get-SccmSiteProvider {
    param([string]$Provider, [string]$RootSiteCode, [string]$TargetSiteCode)
    if ($RootSiteCode -eq $TargetSiteCode) { return $Provider }
    $matches = @(Get-SccmProviderData $Provider $RootSiteCode 'SMS_SCI_SysResUse' | Where-Object { $_.SiteCode -eq $TargetSiteCode -and $_.RoleName -eq 'SMS Provider' })
    if (-not $matches.Count) { Stop-SccmWork "No SMS Provider was found for site $TargetSiteCode." }
    Write-SccmLog "Using the provider registered for site $TargetSiteCode."
    return ([string]$matches[0].NetworkOSPath).Trim('\')
}

function Assert-SccmUpdateReadiness {
    param([object[]]$Sites)
    foreach ($site in $Sites) {
        if ($site.Status -ne 1) { Stop-SccmWork "Site $($site.SiteCode) is not active. Finish its existing installation or update before starting another." }
        $state = Invoke-SccmRemote $site.ServerName {
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
            $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
            return @{FreeBytes = $disk.FreeSpace; PendingRestart = $pending}
        }
        if ($state.PendingRestart) { Stop-SccmWork "Site server $($site.ServerName) needs a Windows restart before servicing." }
        if ($state.FreeBytes -lt 50GB) { Stop-SccmWork "Site server $($site.ServerName) needs at least 50 GB free on its system disk for this lab's update and recovery media." }
        Write-SccmLog "Site $($site.SiteCode) passes active-state, free-space and pending-restart checks."
    }
}

function Test-SccmUpdateFailure {
    param([int]$State)
    return $State -in @(327679, 393215, 131071, 196607, 262143, 262142)
}

function Test-SccmUpdateInstalling {
    param([int]$State)
    return $State -ge 196609 -and $State -le 196629 -and $State -ne 196612
}

function Select-SccmHotfix {
    param([object[]]$Packages, [string]$CurrentVersion)
    $current = [version]$CurrentVersion
    $eligible = @($Packages | Where-Object {
        $_.UpdateType -eq 2 -and $_.State -notin @(196612, 393213, 393214) -and
        [version]$_.FullVersion -ge $current -and ([version]$_.FullVersion).Build -eq $current.Build -and
        $current -ge [version]$_.MinCMVersion -and $current -le [version]$_.MaxCMVersion
    })
    # Only skip a superseded fix when its replacement is actually available.
    # An unavailable replacement must not hide the only applicable fix.
    $eligibleNames = @($eligible | ForEach-Object Name)
    $eligible | Where-Object {
        $replacements = @(([string]$_.SupersededByNameList -split ';') | Where-Object { $_ -and $_ -in $eligibleNames })
        $replacements.Count -eq 0
    } | Sort-Object @{Expression = {[version]$_.FullVersion}}, DateReleased | Select-Object -First 1
}

function Assert-SccmReplication {
    param([string]$Provider, [string]$SiteCode)
    $links = @(Get-SccmProviderData $Provider $SiteCode 'SMS_ReplicationLinkStatus')
    $unhealthy = @($links | Where-Object { $_.InitializationStatus -ne 6 -or $_.FailedSyncs -gt 0 -or $_.DegradedSyncs -gt 0 })
    if ($unhealthy.Count) { Stop-SccmWork "Database replication has $($unhealthy.Count) unready groups. Review Replication Link Analyzer before another update." }
    Write-SccmLog "Database replication is ready ($($links.Count) groups)."
}

function Invoke-SccmSqlQuery {
    param([string]$Server, [string]$Query)
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Data Source=$Server;Initial Catalog=master;Integrated Security=SSPI;Connect Timeout=20;Application Name=LudusSccmDeployment"
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 120
        $table = New-Object System.Data.DataTable
        $reader = $command.ExecuteReader()
        try {
            if ($reader.FieldCount -gt 0) { $table.Load($reader) }
            # ALTER statements intentionally have no result table.
        } finally { $reader.Dispose() }
        return ,$table
    } finally { $connection.Dispose() }
}

function Set-SccmSqlCompatibility {
    param([string]$Server, [switch]$IncludeModel)
    $filter = "name LIKE 'CM[_]%'"
    if ($IncludeModel) { $filter += " OR name = 'model'" }
    # Only the dedicated site databases (and optionally the fresh-install
    # template database) are changed; SQL's other databases are left alone.
    $query = "SELECT name, compatibility_level FROM sys.databases WHERE ($filter) AND compatibility_level > 150"
    $databases = Invoke-SccmSqlQuery $Server $query
    foreach ($database in $databases.Rows) {
        $safeName = ([string]$database.name).Replace(']', ']]')
        Write-SccmLog "Setting [$safeName] on $Server to supported compatibility level 150."
        Invoke-SccmSqlCommand $Server "ALTER DATABASE [$safeName] SET COMPATIBILITY_LEVEL = 150"
    }
}

function Invoke-SccmSqlCommand {
    param([string]$Server, [string]$CommandText)
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = "Data Source=$Server;Initial Catalog=master;Integrated Security=SSPI;Connect Timeout=20;Application Name=LudusSccmDeployment"
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 3600
        $command.CommandText = $CommandText
        [void]$command.ExecuteNonQuery()
    } finally { $connection.Dispose() }
}

function Get-SccmUpdateByGuid {
    param([string]$Provider, [string]$SiteCode, [string]$PackageGuid)
    $packages = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackages' "PackageGuid='$PackageGuid'")
    if ($packages.Count -ne 1) { Stop-SccmWork "Update $PackageGuid is no longer uniquely visible. Review Updates and Servicing before rerunning." }
    return $packages[0]
}

function Set-SccmWarningPolicy {
    param([string]$Provider, [string]$SiteCode, [string]$PackageGuid, [bool]$AllowWarnings)
    $session = New-CimSession -ComputerName $Provider -SessionOption (New-CimSessionOption -Protocol Dcom) -ErrorAction Stop
    try {
        $package = Get-CimInstance -CimSession $session -Namespace "root\SMS\site_$SiteCode" -ClassName SMS_CM_UpdatePackages -Filter "PackageGuid='$PackageGuid'" -ErrorAction Stop
        $flag = 0
        if ($AllowWarnings) { $flag = 2 }
        # Flag 2 only permits warnings. Prerequisite errors still stop setup.
        $result = Invoke-CimMethod -CimSession $session -InputObject $package -MethodName SetIgnorePrereqWarning -Arguments @{flag = [uint32]$flag} -ErrorAction Stop
        if ($result.ReturnValue -ne 0) { Stop-SccmWork "Cannot set the prerequisite warning policy for $PackageGuid." }
        Write-SccmLog "Prerequisite warning policy for ${PackageGuid}: allow=$AllowWarnings"
    } finally { Remove-CimSession $session }
}

function Install-SccmUpdatePackage {
    param([string]$Provider, [string]$SiteCode, [psobject]$Package, [bool]$AllowWarnings, [int]$TimeoutMinutes = 180)
    $guid = [string]$Package.PackageGuid
    $packageName = [string]$Package.Name
    Write-SccmLog "Processing $packageName ($guid), state $($Package.State)."
    if (Test-SccmUpdateFailure $Package.State) {
        Stop-SccmWork "$packageName has failed (state $($Package.State)). Correct the error and use the console's supported retry action; do not reset database state by hand."
    }
    if ($Package.State -eq 196612 -or (Test-SccmUpdateInstalling $Package.State)) {
        Write-SccmLog 'An update is installed at CAS or is already running. Waiting for the hierarchy without starting it again.'
    } else {
        Wait-SccmCondition -Description "$packageName applicability is ready" -TimeoutMinutes $TimeoutMinutes -Test {
            $state = (Get-SccmUpdateByGuid $Provider $SiteCode $guid).State
            if (Test-SccmUpdateFailure $state) { Stop-SccmWork "$packageName failed while checking applicability: state $state" }
            return $state -in @(327682, 262145, 262146, 131073, 131074, 131075)
        }
        $current = Get-SccmUpdateByGuid $Provider $SiteCode $guid
        if ($current.State -eq 327682) {
            Write-SccmLog "Requesting download of $packageName."
            Invoke-CMSiteUpdateDownload -Name $packageName -Force -ErrorAction Stop | Out-Null
        }
        # Already downloading/downloaded packages are resumed rather than reset.
        Wait-SccmCondition -Description "$packageName download finishes" -TimeoutMinutes $TimeoutMinutes -Test {
            $state = (Get-SccmUpdateByGuid $Provider $SiteCode $guid).State
            if (Test-SccmUpdateFailure $state) { Stop-SccmWork "$packageName download failed: state $state" }
            return $state -in @(262146, 131073, 131074, 131075)
        }
        $current = Get-SccmUpdateByGuid $Provider $SiteCode $guid
        if ($current.State -ne 131073) {
            Write-SccmLog "Running prerequisites for $packageName."
            Invoke-CMSiteUpdatePrerequisiteCheck -Name $packageName -ErrorAction Stop | Out-Null
        }
        # An already running prerequisite check is allowed to finish.
        Wait-SccmCondition -Description "$packageName prerequisites finish" -TimeoutMinutes $TimeoutMinutes -Test {
            $state = (Get-SccmUpdateByGuid $Provider $SiteCode $guid).State
            if (Test-SccmUpdateFailure $state) { Stop-SccmWork "$packageName prerequisite check failed: state $state" }
            return $state -in @(131074, 131075)
        }
        $current = Get-SccmUpdateByGuid $Provider $SiteCode $guid
        if ($current.State -eq 131075 -and -not $AllowWarnings) {
            Stop-SccmWork "$packageName has prerequisite warnings. Review ConfigMgrPrereq.log. Only after review, set ludus_sccm_allow_prerequisite_warnings: true to continue."
        }
        Set-SccmWarningPolicy $Provider $SiteCode $guid $AllowWarnings
        Install-CMSiteUpdate -Name $packageName -Force -ErrorAction Stop | Out-Null
    }
    Wait-SccmCondition -Description "$packageName installs at all CAS/primary sites" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $current = Get-SccmUpdateByGuid $Provider $SiteCode $guid
        if (Test-SccmUpdateFailure $current.State) { Stop-SccmWork "$packageName failed during installation: state $($current.State)" }
        if ($current.State -eq 196613) { Stop-SccmWork "$packageName requires a server restart. Restart the affected site in the lab, then rerun." }
        $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' | Where-Object Type -in @(2, 4))
        $states = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackageSiteStatus' "PackageGuid='$guid'")
        foreach ($site in $sites) {
            $status = @($states | Where-Object SiteCode -eq $site.SiteCode)
            if ($status.Count -ne 1 -or $status[0].State -ne 196612) { return $false }
        }
        return $current.State -eq 196612
    }
}

function Complete-SccmSecondaryUpdates {
    param([string]$Provider, [string]$SiteCode, [int]$TimeoutMinutes = 180)
    $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site')
    foreach ($secondary in @($sites | Where-Object Type -eq 1)) {
        $parent = @($sites | Where-Object SiteCode -eq $secondary.ReportingSiteCode)[0]
        $parentProviders = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SysResUse' | Where-Object { $_.SiteCode -eq $parent.SiteCode -and $_.RoleName -eq 'SMS Provider' })
        if (-not $parentProviders.Count) { Stop-SccmWork "No SMS Provider was found for parent $($parent.SiteCode)." }
        $parentProvider = ([string]$parentProviders[0].NetworkOSPath).Trim('\')
        if (([version]$secondary.Version -lt [version]$parent.Version -or $secondary.SecondarySiteCMUpdateStatus -ne 1) -and $secondary.SecondarySiteCMUpdateStatus -in @(1, 2)) {
            Connect-SccmSite $parent.SiteCode $parentProvider
            Write-SccmLog "Requesting secondary upgrade $($secondary.SiteCode) under $($parent.SiteCode)."
            Invoke-CMSecondarySiteUpgrade -SecondarySiteCode $secondary.SiteCode -Force -ErrorAction Stop | Out-Null
        } else {
            Write-SccmLog "Secondary $($secondary.SiteCode) is current or already processing an upgrade (status $($secondary.SecondarySiteCMUpdateStatus))."
        }
        Wait-SccmCondition -Description "secondary $($secondary.SiteCode) matches parent $($parent.SiteCode)" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
            $current = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' "SiteCode='$($secondary.SiteCode)'")[0]
            return $current.Status -eq 1 -and [version]$current.Version -ge [version]$parent.Version -and $current.SecondarySiteCMUpdateStatus -eq 1
        }
        Wait-SccmSiteReady $Provider $SiteCode $secondary.SiteCode $secondary.ServerName $TimeoutMinutes
    }
    Connect-SccmSite $SiteCode $Provider
}

function Get-SccmDatabaseLocation {
    param([psobject]$Definition)
    $parts = [string]$Definition.SQLDatabaseName -split '\\'
    $server = [string]$Definition.SQLServerName
    if ($parts.Count -eq 2) { $server += '\' + $parts[0] }
    # Primary/CAS default instances have just the database name.
    return @{Server = $server; Database = $parts[-1]}
}

function Backup-SccmDatabase {
    param([string]$Server, [string]$Database)
    if ($Database -notmatch '^CM_[A-Za-z0-9]{3}$') { Stop-SccmWork "Unexpected site database name $Database." }
    $pathResult = Invoke-SccmSqlQuery $Server "DECLARE @path nvarchar(4000); EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', @path OUTPUT; SELECT @path AS BackupDirectory;"
    $backupDirectory = [string]$pathResult.Rows[0].BackupDirectory
    if (-not $backupDirectory) { Stop-SccmWork "SQL Server $Server did not report a writable default backup directory." }
    $destination = $backupDirectory.TrimEnd('\') + '\' + $Database + '_ludus_' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff') + '.bak'
    $safePath = $destination.Replace("'", "''")
    Write-SccmLog "Backing up $Database on $Server to $destination."
    Invoke-SccmSqlCommand $Server "BACKUP DATABASE [$Database] TO DISK = N'$safePath' WITH COPY_ONLY, CHECKSUM; RESTORE VERIFYONLY FROM DISK = N'$safePath' WITH CHECKSUM;"
    return @{Server = $Server; Database = $Database; BackupPath = $destination}
}

function Upgrade-SccmSecondarySql {
    param([string]$Server, [string]$ParentServer, [string]$ParentInstallDirectory, [string]$WorkDirectory, [string]$SecondarySiteCode = 'SEC', [string]$InstanceName = 'CONFIGMGRSEC')
    if ($InstanceName -notmatch '^[A-Za-z][A-Za-z0-9_]{0,15}$' -or $SecondarySiteCode -notmatch '^[A-Za-z0-9]{3}$') { Stop-SccmWork 'Secondary SQL instance and site names are invalid.' }
    $source = ConvertTo-SccmAdminShare $ParentServer "$ParentInstallDirectory\cd.latest\redist\SQLEXPR_x64_ENU.exe"
    $state = Invoke-SccmSqlQuery "$Server\$InstanceName" "SELECT CONVERT(nvarchar(100), SERVERPROPERTY('ProductVersion')) AS Version"
    if (([version]$state.Rows[0].Version).Major -ge 14) {
        Write-SccmLog "Secondary SQL on $Server already meets the supported SQL 2017-or-newer floor."
        return
    }
    if (-not (Test-Path -LiteralPath $source) -or ([version](Get-Item -LiteralPath $source).VersionInfo.FileVersion).Major -ne 16) {
        Stop-SccmWork "Secondary $Server needs SQL 2022 Express, but parent media does not contain it: $source. Update the parent to 2509 first; for a historical target, upgrade secondary SQL separately before rerunning."
    }
    $definition = @{Server = "$Server\$InstanceName"; Database = "CM_$SecondarySiteCode"}
    Write-SccmLog "Preparing the existing $InstanceName instance on $Server for an in-place SQL upgrade."
    [void](Backup-SccmDatabase $definition.Server $definition.Database)
    $destination = ConvertTo-SccmAdminShare $Server $WorkDirectory
    [void][IO.Directory]::CreateDirectory($destination)
    Copy-Item -LiteralPath "$WorkDirectory\SccmDeployment.psm1" -Destination "$destination\SccmDeployment.psm1" -Force
    Copy-Item -LiteralPath $source -Destination "$destination\sql2022-express.exe" -Force
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $result = Invoke-SccmRemote $Server {
            param($directory, $instance)
            Import-Module "$directory\SccmDeployment.psm1" -Force
            Set-SccmLog "$directory\secondary-sql-upgrade.log"
            $versionTable = Invoke-SccmSqlQuery ".\$instance" "SELECT CONVERT(nvarchar(100), SERVERPROPERTY('ProductVersion')) AS Version"
            $version = [version]$versionTable.Rows[0].Version
            if ($version.Major -ge 16) { return @{Complete = $true; RebootRequired = $false} }
            $runningServices = @(Get-Service 'SMS*' | Where-Object Status -eq Running | ForEach-Object Name)
            foreach ($name in $runningServices) { Stop-Service $name -Force -ErrorAction Stop }
            try {
                if ($version.Major -eq 13 -and $version -lt [version]'13.0.6300.2') {
                    $patch = "$directory\sql2016-sp3.exe"
                    if (-not (Test-Path -LiteralPath $patch)) {
                        Write-SccmLog 'Downloading the official SQL 2016 SP3 package.'
                        Invoke-WebRequest -UseBasicParsing -Uri 'https://download.microsoft.com/download/a/7/7/a77b5753-8fe7-4804-bfc5-591d9a626c98/SQLServer2016SP3-KB5003279-x64-ENU.exe' -OutFile $patch -ErrorAction Stop
                    }
                    # The published hash protects this older package as well as
                    # the normal Microsoft signature check in the installer.
                    if ((Get-FileHash $patch -Algorithm SHA256).Hash -ne 'CAE75F65C7C3C263A7BDBAEF0F4AFD0AE49BAF57C08AB27141A7B26008658A91') { Stop-SccmWork 'SQL 2016 SP3 checksum mismatch.' }
                    $restart = Invoke-SccmInstaller $patch "/quiet /IAcceptSQLServerLicenseTerms /Action=Patch /InstanceName=$instance"
                    return @{Complete = $false; RebootRequired = $restart}
                }
                $extract = "$directory\sql2022-express"
                $setup = "$extract\setup.exe"
                if (-not (Test-Path -LiteralPath $setup)) { [void](Invoke-SccmInstaller "$directory\sql2022-express.exe" "/q /x:`"$extract`"") }
                $restart = Invoke-SccmInstaller $setup "/Q /ACTION=Upgrade /INSTANCENAME=$instance /IACCEPTSQLSERVERLICENSETERMS /UpdateEnabled=False"
                return @{Complete = $true; RebootRequired = $restart}
            } finally {
                foreach ($name in $runningServices) { Start-Service $name -ErrorAction Stop }
            }
        } @($WorkDirectory, $InstanceName)
        if ($result.RebootRequired) {
            Write-SccmLog "Restarting secondary $Server after the SQL prerequisite upgrade."
            Restart-Computer -ComputerName $Server -Force -Wait -For PowerShell -Timeout 900 -Delay 10 -ErrorAction Stop
        }
        Wait-SccmCondition -Description "secondary SQL on $Server is accepting connections" -TimeoutMinutes 15 -RetryReadErrors -Test {
            [void](Invoke-SccmSqlQuery "$Server\$InstanceName" 'SELECT 1 AS Ready')
            return $true
        }
        if ($result.Complete) {
            $verified = Invoke-SccmSqlQuery "$Server\$InstanceName" "SELECT CONVERT(nvarchar(100), SERVERPROPERTY('ProductVersion')) AS Version"
            if (([version]$verified.Rows[0].Version).Major -ne 16) { Stop-SccmWork "Secondary SQL upgrade did not produce SQL Server 2022 on $Server." }
            Write-SccmLog "Secondary SQL upgrade verified on $Server."
            return
        }
        Write-SccmLog 'SP3 is ready; proceeding to SQL 2022 Express.'
    }
    Stop-SccmWork "Secondary SQL upgrade did not finish after the expected steps on $Server."
}

function Get-SccmMsiVersion {
    param([string]$Path)
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $null
    $view = $null
    $record = $null
    try {
        $database = $installer.OpenDatabase($Path, 0)
        $view = $database.OpenView("SELECT Value FROM Property WHERE Property='ProductVersion'")
        $view.Execute()
        $record = $view.Fetch()
        if ($null -eq $record) { Stop-SccmWork "MSI ProductVersion is missing from $Path." }
        return [string]$record.StringData(1)
    } finally {
        foreach ($item in @($record, $view, $database, $installer)) {
            if ($null -ne $item) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item) }
            # A failed open may leave later COM objects unallocated.
        }
    }
}

function Get-SccmConsoleVersion {
    $consoles = @(Get-SccmInstalledApplications | Where-Object DisplayName -match '(Configuration Manager|Endpoint Configuration Manager) Console')
    if ($consoles.Count -eq 0) { return $null }
    # Multiple matching installed consoles are ambiguous and need review.
    if ($consoles.Count -ne 1) { Stop-SccmWork 'More than one Configuration Manager console installation was found.' }
    return [string]$consoles[0].DisplayVersion
}

function Get-SccmResourceComputerName {
    param([psobject]$Resource)
    # FullDomainName is the AD domain, not the computer's complete DNS name.
    # Prefer SCCM's discovered resource names, then form a name explicitly.
    $resourceNames = @($Resource.ResourceNames | Where-Object { $_ -and $_ -like '*.*' })
    if ($resourceNames.Count) { return [string]$resourceNames[0] }
    if ([string]$Resource.Name -like '*.*') { return [string]$Resource.Name }
    if ($Resource.FullDomainName) { return ([string]$Resource.Name + '.' + [string]$Resource.FullDomainName) }
    # Workgroup computers can only supply their short computer name.
    return [string]$Resource.Name
}

Export-ModuleMember -Function *-Sccm*
