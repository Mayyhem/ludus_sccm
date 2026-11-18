# Shared Windows PowerShell 5.1 helpers. Importing this module does not collect
# data, create files, or change SCCM. The calling role chooses each operation.
Set-StrictMode -Version Latest
$script:SccmLogPath = $null

function Set-SccmLog {
    param([Parameter(Mandatory)][string]$Path, [switch]$OnlyIfUnset)
    if ($OnlyIfUnset -and $script:SccmLogPath) { return }
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

function Request-SccmCatalogCheck {
    try {
        Invoke-CMSiteUpdateCheck -ErrorAction Stop | Out-Null
        Write-SccmLog 'Requested normal update catalog synchronization.'
        return $true
    } catch {
        if ($_.Exception.Message -match '\bStill checking for updates\b') {
            Write-SccmLog 'Normal update catalog synchronization is already running; waiting for its results.'
            return $false
        }
        throw
    }
}

function Get-SccmBootTimeUtc {
    return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
}

function Get-SccmPendingRestartRequests {
    $path = Join-Path $PSScriptRoot 'pending-deployment-restarts.json'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $boot = Get-SccmBootTimeUtc
    $records = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    foreach ($record in @($records)) {
        if ($null -ne $record -and $record.BootTimeUtc -eq $boot) { $record }
    }
}

function New-SccmRestartRequest {
    param([string]$Computer, [string]$Kind, [string]$Version = '', [string]$SiteCode = '', [string]$PackageGuid = '', [switch]$Persist)
    $request = @{Computer = $Computer; Kind = $Kind; Version = $Version; SiteCode = $SiteCode; PackageGuid = $PackageGuid; BootTimeUtc = (Get-SccmBootTimeUtc)}
    if ($Persist) {
        # This is the automation's own journal, never a vendor queue or status.
        $previous = @(Get-SccmPendingRestartRequests | Where-Object Kind -ne $Kind)
        ConvertTo-Json -InputObject @($previous + @($request)) -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'pending-deployment-restarts.json') -Encoding UTF8
    }
    return $request
}

function Stop-SccmForRestart {
    param([object[]]$Requests, [string]$Message)
    if (-not $Requests.Count) { Stop-SccmWork 'A restart was requested without an identified target.' }
    Write-SccmLog $Message
    $failure = New-Object System.InvalidOperationException($Message)
    $failure.Data['SccmFatal'] = $true
    $failure.Data['SccmRestartRequestsJson'] = ConvertTo-Json -InputObject @($Requests) -Depth 6 -Compress
    throw $failure
}

function Get-SccmSiteRestartRequests {
    param([object[]]$Sites, [object[]]$States, [string]$PackageGuid)
    foreach ($state in @($States | Where-Object State -eq 196613)) {
        $site = @($Sites | Where-Object SiteCode -eq $state.SiteCode)
        if ($site.Count -ne 1) { Stop-SccmWork 'Cannot identify the site that requested a restart.' }
        $boot = Invoke-SccmRemote $site[0].ServerName { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o') }
        @{Computer = [string]$site[0].ServerName; Kind = 'SiteUpdate'; Version = [string]$site[0].Version; SiteCode = [string]$site[0].SiteCode; PackageGuid = $(if($PackageGuid){$PackageGuid}else{[string]$state.PackageGuid}); BootTimeUtc = [string]$boot}
    }
}

function Test-SccmGuestRestart {
    param([hashtable]$Request)
    if (([string]$Request.Computer -split '\.')[0] -ine $env:COMPUTERNAME) { Stop-SccmWork 'Restart target does not match this guest.' }
    if ($Request.Kind -notin @('Client','Console','SiteUpdate','WindowsPrerequisite')) { Stop-SccmWork 'Unknown restart checkpoint kind.' }
    if ([string]$Request.Computer -like '*.*') {
        $domain = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Domain
        if (([string]$Request.Computer -split '\.',2)[1] -ine $domain) { Stop-SccmWork 'Restart target domain does not match this guest.' }
    }
    if (@(Get-Process ccmsetup,srvboot,setup,setupwpf -ErrorAction SilentlyContinue).Count -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress')) {
        Stop-SccmWork 'Native installation work is active; refusing a guest restart.'
    }
    $boot = Get-SccmBootTimeUtc
    if (-not $Request.BootTimeUtc) { Stop-SccmWork 'A restart request has no boot identity.' }
    if ($boot -ne $Request.BootTimeUtc) { return @{Computer=$env:COMPUTERNAME;NeedsRestart=$false;AlreadyRebooted=$true} }
    $needed = $false
    switch ($Request.Kind) {
        Client {
            $state = Get-SccmClientState
            if ($state.Version -ne $Request.Version -or ($state.AssignedSite -and $state.AssignedSite -ne $Request.SiteCode)) { Stop-SccmWork 'Client identity/version changed after its restart checkpoint.' }
            $needed = $state.RebootRequired -and -not $state.SetupRunning
        }
        Console {
            $pending = @(Get-SccmPendingRestartRequests | Where-Object { $_.Kind -eq 'Console' -and $_.Version -eq $Request.Version })
            if ([version](Get-SccmConsoleVersion) -ne [version]$Request.Version) { Stop-SccmWork 'The installed console does not match its restart checkpoint.' }
            $needed = $pending.Count -eq 1
        }
        SiteUpdate {
            if ($Request.SiteCode -notmatch '^[A-Z0-9]{3}$') { Stop-SccmWork 'Invalid restart site code.' }
            $guid = ([guid]$Request.PackageGuid).ToString()
            $states = @(Get-CimInstance -Namespace "root\SMS\site_$($Request.SiteCode)" -ClassName SMS_CM_UpdatePackageSiteStatus -Filter "PackageGuid='$guid'" -ErrorAction Stop | Where-Object SiteCode -eq $Request.SiteCode)
            $needed = $states.Count -eq 1 -and $states[0].State -eq 196613
        }
        WindowsPrerequisite {
            $needed = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        }
    }
    if (-not $needed) { Stop-SccmWork 'The recorded native restart checkpoint is no longer present; refusing an unproven restart.' }
    return @{Computer=$env:COMPUTERNAME;Kind=$Request.Kind;NeedsRestart=$true;AlreadyRebooted=$false}
}

function Test-SccmGuestAfterRestart {
    param([hashtable]$Request)
    if (([string]$Request.Computer -split '\.')[0] -ine $env:COMPUTERNAME) { Stop-SccmWork 'Wrong guest after restart.' }
    if ((Get-SccmBootTimeUtc) -eq $Request.BootTimeUtc) { return $false }
    switch ($Request.Kind) {
        Client {
            $state = Get-SccmClientState
            return $state.Service -eq 'Running' -and $state.AssignedSite -eq $Request.SiteCode -and -not $state.SetupRunning -and -not $state.RebootRequired
        }
        Console { return [version](Get-SccmConsoleVersion) -eq [version]$Request.Version }
        SiteUpdate {
            $guid = ([guid]$Request.PackageGuid).ToString()
            $states = @(Get-CimInstance -Namespace "root\SMS\site_$($Request.SiteCode)" -ClassName SMS_CM_UpdatePackageSiteStatus -Filter "PackageGuid='$guid'" -ErrorAction Stop | Where-Object SiteCode -eq $Request.SiteCode)
            return (Get-Service SMS_EXECUTIVE -ErrorAction Stop).Status -eq 'Running' -and $states.Count -eq 1 -and $states[0].State -ne 196613
        }
        WindowsPrerequisite {
            return -not (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -and
                -not (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        }
        default { Stop-SccmWork 'Unknown post-restart checkpoint kind.' }
    }
}

function Update-SccmServicingConsole {
    param([string]$Provider, [string]$SiteCode, [int]$TimeoutMinutes = 180)
    # Read the expected version with CIM before importing console assemblies.
    # Console upgrades run in a separate Ansible PowerShell process from cmdlets.
    $identification = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Identification')
    $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' "SiteCode='$SiteCode'")
    if ($identification.Count -ne 1 -or -not $identification[0].SMSAvailableConsoleVersion -or $sites.Count -ne 1) {
        Stop-SccmWork 'Cannot establish the servicing console version and owning site.'
    }
    $site = $sites[0]
    if (($site.ServerName -split '\.')[0] -ine $env:COMPUTERNAME) { Stop-SccmWork 'Update the servicing console only on its owning site server.' }
    $expected = [version]$identification[0].SMSAvailableConsoleVersion
    $installed = Get-SccmConsoleVersion
    if (-not $installed) { Stop-SccmWork 'The site server has no installed servicing console. Install its baseline console first.' }
    if ([version]$installed -gt $expected) { Stop-SccmWork 'The servicing console is newer than this site; automatic console downgrade is not supported.' }
    if ([version]$installed -eq $expected) {
        $pending = @(Get-SccmPendingRestartRequests | Where-Object Kind -eq 'Console')
        return @{Changed = $false; Version = [string]$expected; RebootRequired = ($pending.Count -gt 0); RebootRequests = $pending}
    }
    Wait-SccmCondition -Description 'the local site finishes servicing before its console is updated' -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $states = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackageSiteStatus' | Where-Object SiteCode -eq $SiteCode)
        $requests = @(Get-SccmSiteRestartRequests @($site) $states '')
        if ($requests.Count) { Stop-SccmForRestart $requests 'The site needs a restart before updating its console.' }
        if (@($states | Where-Object { Test-SccmUpdateInstalling $_.State }).Count) { return $false }
        $actual = Get-SccmHostSiteState $env:COMPUTERNAME
        return $actual.ServiceStatus -eq 'Running' -and [version]$actual.Version -ge [version]$site.Version
    }
    $source = Join-Path $site.InstallDir 'tools\ConsoleSetup\ConsoleSetup.exe'
    $targetDirectory = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Configuration Manager\AdminConsole'
    $reboot = Invoke-SccmInstaller -Path $source -Arguments "/q `"TargetDir=$targetDirectory`" DefaultSiteServerName=$($site.ServerName)" -TimeoutMinutes 30
    if ($reboot) {
        $request = New-SccmRestartRequest $site.ServerName Console ([string]$expected) $SiteCode -Persist
        return @{Changed = $true; Version = [string]$expected; RebootRequired = $true; RebootRequests = @($request)}
    }
    $actualConsole = Get-SccmConsoleVersion
    if ([version]$actualConsole -ne $expected) { Stop-SccmWork "The servicing console did not reach $expected. Review ConfigMgrAdminUISetup.log." }
    Write-SccmLog "Servicing console updated to $expected."
    return @{Changed = $true; Version = [string]$expected; RebootRequired = $false}
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

function Get-SccmMediaExtractionArguments {
    param([psobject]$VersionInfo, [string]$Directory)
    # Current baseline downloads use the vendor's embedded 7-Zip extractor.
    # Its switches differ from the older Microsoft self-extracting media.
    if ($VersionInfo.ProductName -eq '7-Zip' -and $VersionInfo.FileDescription -eq '7z SFX') {
        # These archives contain SMSSETUP at their root. Older media creates
        # cd.retail.LN itself; keep the same media path for both formats.
        return "-y -o`"$(Join-Path $Directory 'cd.retail.LN')`""
    }
    return "/s -d`"$Directory`""
}

function Invoke-SccmInstaller {
    param([string]$Path, [string]$Arguments, [int[]]$AcceptedExitCodes = @(0, 3010), [ValidateRange(0, 1440)][int]$TimeoutMinutes = 0)
    Assert-SccmMicrosoftSignature $Path
    Write-SccmLog "Starting installer $Path"
    $start = @{FilePath = $Path; ArgumentList = $Arguments; WindowStyle = 'Hidden'; PassThru = $true; Wait = ($TimeoutMinutes -eq 0)}
    if ([IO.Path]::GetExtension($Path) -ieq '.msi') {
        $start.FilePath = "$env:SystemRoot\System32\msiexec.exe"
        $start.ArgumentList = "/i `"$Path`" $Arguments"
    }
    $process = Start-Process @start
    if ($TimeoutMinutes -gt 0) {
        if (-not $process.WaitForExit($TimeoutMinutes * 60000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Stop-SccmWork "Installer $Path timed out after $TimeoutMinutes minutes. Check its log and command-line switches before rerunning."
        }
        $process.Refresh()
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

function Get-SccmVisualCppRuntimeVersion {
    param([ValidateSet('x86', 'x64')][string]$Architecture)
    $versions = @(
        foreach ($root in @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')) {
            $runtime = Get-ItemProperty -LiteralPath "$root\Microsoft\VisualStudio\14.0\VC\Runtimes\$Architecture" -ErrorAction SilentlyContinue
            if ($runtime -and $runtime.Installed -eq 1) { [version]([string]$runtime.Version).TrimStart('v') }
        }
    )
    if ($versions.Count) { return ($versions | Sort-Object -Descending | Select-Object -First 1) }
    return $null
}

function Install-SccmPrerequisites {
    param([string]$WorkDirectory, [bool]$PrepareAdk = $false)
    $hasChanged = $false
    $needsRestart = $false
    $dotnet = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop
    if ($dotnet.Release -lt 528040) { Stop-SccmWork '.NET Framework 4.8 is required. Install it and restart this server before rerunning.' }
    # OLE DB 19's x64 package also installs x86 binaries. Check both runtimes
    # independently of ODBC, including when the ODBC driver is already current.
    foreach ($architecture in @('x64', 'x86')) {
        $package = "$WorkDirectory\vc-2022-$architecture.exe"
        $expected = [version](Get-Item -LiteralPath $package).VersionInfo.FileVersion
        $installed = Get-SccmVisualCppRuntimeVersion $architecture
        if ($null -eq $installed -or $installed -lt $expected) {
            $needsRestart = (Invoke-SccmInstaller $package '/install /quiet /norestart' @(0, 1638, 3010)) -or $needsRestart
            $hasChanged = $true
        }
        $verified = Get-SccmVisualCppRuntimeVersion $architecture
        if ($null -eq $verified -or $verified -lt $expected) { Stop-SccmWork "Visual C++ $architecture installation did not register the required runtime version $expected." }
        Write-SccmLog "Verified Visual C++ $architecture runtime $verified."
    }
    $applications = Get-SccmInstalledApplications
    $driver = @($applications | Where-Object DisplayName -eq 'Microsoft ODBC Driver 18 for SQL Server')
    if ($driver.Count -ne 1 -or $driver[0].DisplayVersion -ne '18.6.2.1') {
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

function Copy-SccmFile {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'LiteralPath')][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$Recurse
    )
    # UNC paths inherit the current provider unless explicitly qualified.
    # Servicing keeps a CMSite drive current for Configuration Manager cmdlets.
    $copy = @{Destination = "Microsoft.PowerShell.Core\FileSystem::$Destination"; Force = $true; ErrorAction = 'Stop'}
    if ($PSCmdlet.ParameterSetName -eq 'LiteralPath') {
        $copy.LiteralPath = "Microsoft.PowerShell.Core\FileSystem::$LiteralPath"
    } else {
        $copy.Path = "Microsoft.PowerShell.Core\FileSystem::$Path"
    }
    if ($Recurse) { $copy.Recurse = $true }
    Microsoft.PowerShell.Management\Copy-Item @copy
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
    param(
        [string]$Provider, [string]$SiteCode, [string]$Server,
        [int]$TimeoutMinutes = 180,
        [ValidateRange(0, 3600)][int]$ValidationGraceSeconds = 300
    )
    $validation = @{FirstFailureSeconds = $null}
    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    Wait-SccmCondition -Description "passive server $Server is installed and ready" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $stages = @(Get-SccmProviderData $Provider $SiteCode 'SMS_HA_SiteServerTopLevelMonitoring' "SiteServerName='$Server'")
        $failed = @($stages | Where-Object { $_.StageId -in @(11, 12, 13, 14) -and $_.StageCompleted -eq 3 })
        if ($failed.Count) {
            $details = @(Get-SccmProviderData $Provider $SiteCode 'SMS_HA_SiteServerDetailedMonitoring' "SiteServerName='$Server'" | Where-Object { $_.StageId -in @(11, 12, 13, 14) -and $_.Applicable -eq 1 -and $_.IsComplete -eq 3 })
            $names = @($details | ForEach-Object SubStageName) -join ', '
            $installed = @($stages | Where-Object { $_.StageId -in @(11, 12, 13) -and $_.StageCompleted -eq 2 })
            # Native site validation (0xe000c) retries every minute. Initial
            # site-key distribution can briefly fail after installation finishes.
            # Wait for the vendor's result; never change its key or HA status.
            $siteValidation = @($details | Where-Object {
                $_.PSObject.Properties.Name -contains 'SubStageid' -and [int]$_.SubStageid -eq 0xe000c -and $_.StageId -eq 14
            })
            if ($failed.Count -eq 1 -and $failed[0].StageId -eq 14 -and
                $installed.Count -eq 3 -and $details.Count -eq 1 -and $siteValidation.Count -eq 1) {
                if ($null -eq $validation.FirstFailureSeconds) { $validation.FirstFailureSeconds = $elapsed.Elapsed.TotalSeconds }
                if (($elapsed.Elapsed.TotalSeconds - $validation.FirstFailureSeconds) -ge $ValidationGraceSeconds) {
                    Stop-SccmWork "Passive server $Server native site validation remained failed for $ValidationGraceSeconds seconds: $names. Review failovermgr.log; no recovery or status changes were submitted."
                }
                Write-SccmLog "Passive server $Server native site validation is not ready: $names. Waiting up to $ValidationGraceSeconds seconds for its native recheck." 'WARNING'
                return $false
            }
            Stop-SccmWork "Passive server $Server reports a failed installation stage: $names. Review failovermgr.log on the active and passive servers before retrying."
        }
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
    $site = @(Get-SccmProviderData $Provider $RootSiteCode 'SMS_Site' "SiteCode='$TargetSiteCode'")[0]
    Write-SccmLog "Using the provider registered for site $TargetSiteCode."
    return Select-SccmSiteProvider $matches $site.ServerName
}

function Select-SccmSiteProvider {
    param([object[]]$ProviderRoles, [string]$SiteServer)
    # A site can register providers on its passive and remote provider servers
    # too, in no meaningful order. Those hosts need not accept remote WMI from
    # other sites, so use the provider on the active site server when it has one.
    $servers = @($ProviderRoles | ForEach-Object { ([string]$_.NetworkOSPath).Trim('\') })
    $active = @($servers | Where-Object { $SiteServer -and ($_ -split '\.')[0] -ieq ($SiteServer -split '\.')[0] })
    if ($active.Count) { return $active[0] }
    return $servers[0]
}

function Get-SccmSiteCommunicationState {
    param([string]$Provider, [string]$SiteCode)
    $components = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_Component' "SiteCode='$SiteCode'" |
        Where-Object ComponentName -eq 'SMS_SITE_COMPONENT_MANAGER')
    if ($components.Count -ne 1) { Stop-SccmWork "Cannot uniquely read communication settings for site $SiteCode." }
    $state = @($components[0].Props | Where-Object PropertyName -eq 'IISSSLState')
    if ($state.Count -ne 1) { Stop-SccmWork "Site $SiteCode does not expose its communication flags." }
    return [uint32]$state[0].Value
}

function Set-SccmCasGeneratedCertificates {
    param([string]$SiteCode, [uint32]$ExpectedState, [bool]$Preview = $true)
    # Set-CMSite in the 2509 module skips SetClientCommunicationProperties for
    # Type 4. Use the documented site-control SDK for the CAS configuration.
    $components = @(Get-CMSiteComponent -SiteCode $SiteCode -ComponentName 'SMS_SITE_COMPONENT_MANAGER' -ErrorAction Stop)
    if ($components.Count -ne 1) { Stop-SccmWork "Cannot uniquely select the CAS site-control component for $SiteCode." }
    $component = $components[0]
    $component.Get()
    if ($component.SiteCode -ne $SiteCode -or $component.ComponentName -ne 'SMS_SITE_COMPONENT_MANAGER' -or $component.FileType -ne 2) {
        Stop-SccmWork 'Unexpected CAS site-control component identity.'
    }
    $properties = $component.EmbeddedProperties
    if (-not $properties.ContainsKey('IISSSLState')) { Stop-SccmWork 'CAS communication flags are missing from the SDK object.' }
    $before = [uint32]$properties['IISSSLState']['Value'].IntegerValue
    if ($before -ne $ExpectedState) { Stop-SccmWork 'CAS communication flags changed since the configuration preview.' }
    if ($Preview -or ($before -band 1024) -ne 0) { return $false }
    $properties['IISSSLState']['Value'].IntegerValue = $before -bor 1024
    $component.EmbeddedProperties = $properties
    $component.Put()
    return $true
}

function Enable-SccmEnhancedHttp {
    param([string]$Provider, [string]$SiteCode, [bool]$Preview = $false)
    $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' | Where-Object Type -in @(2, 4))
    if (-not $sites.Count -or @($sites | Where-Object Status -ne 1).Count) {
        Stop-SccmWork 'Enhanced HTTP configuration requires active CAS/primary sites.'
    }
    $distributionPoints = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SysResUse' |
        Where-Object RoleName -eq 'SMS Distribution Point')
    foreach ($dp in $distributionPoints) {
        if (@($dp.Props | Where-Object { $_.PropertyName -eq 'IsAnonymousEnabled' -and $_.Value -ne 0 }).Count) {
            Stop-SccmWork 'Enhanced HTTP requires anonymous distribution-point access to be disabled. Review that setting explicitly.'
        }
    }
    $changed = $false
    $results = @()
    try {
        foreach ($site in $sites) {
            $code = [string]$site.SiteCode
            $siteProvider = Get-SccmSiteProvider $Provider $SiteCode $code
            $before = Get-SccmSiteCommunicationState $siteProvider $code
            # Read the native bit for idempotence; save through native configuration APIs.
            $enabled = ($before -band 1024) -ne 0
            $httpsOnly = ($before -band 1) -ne 0
            $needsChange = -not ($enabled -or $httpsOnly)
            if ($needsChange -and $Preview -and $site.Type -eq 4) {
                Connect-SccmSite $code $siteProvider
                [void](Set-SccmCasGeneratedCertificates $code $before $true)
            }
            if ($needsChange -and -not $Preview) {
                $active = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackages' |
                    Where-Object { Test-SccmUpdateInstalling $_.State })
                if ($active.Count) { Stop-SccmWork 'Finish the running update before changing site communication settings.' }
                Connect-SccmSite $code $siteProvider
                if ($site.Type -eq 4) {
                    [void](Set-SccmCasGeneratedCertificates $code $before $false)
                } else {
                    Set-CMSite -SiteCode $code -UseSmsGeneratedCert $true -ErrorAction Stop
                }
                Wait-SccmCondition -Description "Enhanced HTTP enabled at $code" -TimeoutMinutes 5 -Test {
                    return ((Get-SccmSiteCommunicationState $siteProvider $code) -band 1024) -ne 0
                }
                $after = Get-SccmSiteCommunicationState $siteProvider $code
                # The native cmdlet also normalizes HTTP mode bits 64/128.
                # Preserve PKI, revocation and all flags outside that native mask.
                if (($after -band (-bnot 1216)) -ne ($before -band (-bnot 1216))) {
                    Stop-SccmWork "Unexpected communication flag changes at $code. Review the native site settings."
                }
                $changed = $true
                Write-SccmLog "Enabled Configuration Manager generated HTTP certificates at site $code."
            }
            $results += @{SiteCode = $code; PreviouslyEnabled = $enabled; HttpsOnly = $httpsOnly; WouldEnable = $needsChange; Preview = $Preview}
        }
        return @{Changed = $changed; Sites = $results}
    } finally { Connect-SccmSite $SiteCode $Provider }
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
        if ($state.PendingRestart) {
            $request = Invoke-SccmRemote $site.ServerName {
                param($computer, $code, $version)
                @{Computer = $computer; Kind = 'WindowsPrerequisite'; SiteCode = $code; Version = $version; PackageGuid = ''; BootTimeUtc = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')}
            } @($site.ServerName, $site.SiteCode, $site.Version)
            Stop-SccmForRestart @($request) "Site server $($site.ServerName) needs a Windows restart before servicing."
        }
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

function Test-SccmUpdatePreparationStarted {
    param([int]$State)
    # Content replication belongs to an existing prerequisite request. A
    # completed check can also have refreshed maintenance source files.
    return $State -in @(65537, 65538, 131073, 131074, 131075)
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
    param([string]$Provider, [string]$SiteCode, [int]$TimeoutMinutes = 60, [int]$PollSeconds = 60)
    # Shortly after site installation or a site property change, a few groups
    # can briefly report failed or degraded syncs and then settle without any
    # repair. Wait for native replication to settle; persistent problems fail.
    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    do {
        $links = @(Get-SccmProviderData $Provider $SiteCode 'SMS_ReplicationLinkStatus')
        $unhealthy = @($links | Where-Object { $_.InitializationStatus -ne 6 -or $_.FailedSyncs -gt 0 -or $_.DegradedSyncs -gt 0 })
        if (-not $unhealthy.Count) {
            Write-SccmLog "Database replication is ready ($($links.Count) groups)."
            return
        }
        $names = ($unhealthy | ForEach-Object {
            '{0}->{1} {2} (initialization {3}, failed {4}, degraded {5})' -f $_.ParentSite, $_.ChildSite, $_.ReplicationGroup, $_.InitializationStatus, $_.FailedSyncs, $_.DegradedSyncs
        }) -join '; '
        if ([DateTime]::UtcNow -ge $deadline) {
            Stop-SccmWork "Database replication has $($unhealthy.Count) unready groups after $TimeoutMinutes minutes: $names. Review Replication Link Analyzer before another update."
        }
        Write-SccmLog "Waiting for $($unhealthy.Count) unready replication groups: $names" 'WARNING'
        Start-Sleep -Seconds $PollSeconds
    } while ($true)
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

function Get-SccmUpdateCommandObject {
    param([string]$PackageGuid)
    # Early and broad releases can share a display name. Bind native actions to
    # the already selected GUID rather than submitting a name-based request.
    $matches = @(Get-CMSiteUpdate -Fast -ErrorAction Stop | Where-Object PackageGuid -eq $PackageGuid)
    if ($matches.Count -ne 1) { Stop-SccmWork "Cannot uniquely select update $PackageGuid for its native action." }
    return $matches[0]
}

function Install-SccmUpdatePackage {
    param([string]$Provider, [string]$SiteCode, [psobject]$Package, [bool]$AllowWarnings, [int]$TimeoutMinutes = 180, [int]$CatalogRetryMinutes = 10)
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
            return $state -in @(327682, 262145, 262146) -or (Test-SccmUpdatePreparationStarted $state)
        }
        $current = Get-SccmUpdateByGuid $Provider $SiteCode $guid
        if ($current.State -eq 327682) {
            Write-SccmLog "Requesting download of $packageName."
            Invoke-CMSiteUpdateDownload -InputObject (Get-SccmUpdateCommandObject $guid) -Force -ErrorAction Stop | Out-Null
        }
        # Already downloading/downloaded packages are resumed rather than reset.
        # The service connection point fetches queued downloads only when it
        # syncs. A request queued just after a sync can otherwise wait hours for
        # an unrelated one, so while the package is still only available, ask
        # for the console's normal Check for Updates at the native interval.
        $catalogRetry = @{Next = [DateTime]::UtcNow.AddMinutes($CatalogRetryMinutes)}
        Wait-SccmCondition -Description "$packageName download finishes" -TimeoutMinutes $TimeoutMinutes -Test {
            $state = (Get-SccmUpdateByGuid $Provider $SiteCode $guid).State
            if (Test-SccmUpdateFailure $state) { Stop-SccmWork "$packageName download failed: state $state" }
            if ($state -eq 327682 -and [DateTime]::UtcNow -ge $catalogRetry.Next) {
                $catalogRetry.Next = [DateTime]::UtcNow.AddMinutes($CatalogRetryMinutes)
                try {
                    if (Request-SccmCatalogCheck) { Write-SccmLog "$packageName is still queued; requested a catalog check so the service connection point fetches it." }
                } catch {
                    Write-SccmLog "Catalog check request failed while $packageName is queued: $($_.Exception.Message)" 'WARNING'
                }
            }
            return $state -eq 262146 -or (Test-SccmUpdatePreparationStarted $state)
        }
        $current = Get-SccmUpdateByGuid $Provider $SiteCode $guid
        if (-not (Test-SccmUpdatePreparationStarted $current.State)) {
            Write-SccmLog "Running prerequisites for $packageName."
            Invoke-CMSiteUpdatePrerequisiteCheck -InputObject (Get-SccmUpdateCommandObject $guid) -ErrorAction Stop | Out-Null
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
        $nativePackage = Get-SccmUpdateCommandObject $guid
        if ($current.State -notin @(131074, 131075) -or $nativePackage.State -notin @(131074, 131075)) {
            Stop-SccmWork "$packageName prerequisite result changed before installation. Review its native status."
        }
        if ($nativePackage.State -eq 131075 -and -not $AllowWarnings) {
            Stop-SccmWork "$packageName has prerequisite warnings. Review ConfigMgrPrereq.log before continuing."
        }
        # In the native installer this switch maps to PrereqFlag 2: continue on
        # warnings. It cannot override the completed-prerequisite guards above;
        # Configuration Manager still blocks prerequisite errors during setup.
        Install-CMSiteUpdate -InputObject $nativePackage -SkipPrerequisiteCheck:$AllowWarnings -Force -ErrorAction Stop | Out-Null
    }
    Wait-SccmCondition -Description "$packageName installs at all CAS/primary sites" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $current = Get-SccmUpdateByGuid $Provider $SiteCode $guid
        if (Test-SccmUpdateFailure $current.State) { Stop-SccmWork "$packageName failed during installation: state $($current.State)" }
        $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' | Where-Object Type -in @(2, 4))
        $states = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackageSiteStatus' "PackageGuid='$guid'")
        $requests = @(Get-SccmSiteRestartRequests $sites $states $guid)
        if ($requests.Count) { Stop-SccmForRestart $requests "$packageName requires a native site restart." }
        if ($current.State -eq 196613) { Stop-SccmWork 'The package requests a restart but no affected site can be identified.' }
        foreach ($site in $sites) {
            $status = @($states | Where-Object SiteCode -eq $site.SiteCode)
            if ($status.Count -ne 1 -or $status[0].State -ne 196612) { return $false }
        }
        return $current.State -eq 196612
    }
}

function New-SccmManagementConnection {
    param([string]$Provider, [string]$SiteCode)
    $bin = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Configuration Manager\AdminConsole\bin'
    [void][Reflection.Assembly]::LoadFrom("$bin\Microsoft.ConfigurationManagement.ManagementProvider.dll")
    [void][Reflection.Assembly]::LoadFrom("$bin\AdminUI.WqlQueryEngine.dll")
    $values = [Microsoft.ConfigurationManagement.ManagementProvider.SmsNamedValuesDictionary]::new()
    $connection = [Microsoft.ConfigurationManagement.ManagementProvider.WqlQueryEngine.WqlConnectionManager]::new($values)
    try {
        [void]$connection.Connect($Provider)
        if ([string]$values['ConnectedSiteCode'] -ine $SiteCode) { Stop-SccmWork 'The recovery management connection is not to the expected parent site.' }
        return ,$connection
    } catch { $connection.Dispose(); throw }
}

function Get-SccmSecondaryMissingUpdatePackages {
    param([string]$Provider, [string]$ParentCode, [string]$SecondaryCode)
    $definitions = @(Get-SccmProviderData $Provider $ParentCode 'SMS_SCI_SiteDefinition')
    $locations = @{}
    foreach ($code in @($ParentCode, $SecondaryCode)) {
        $definition = @($definitions | Where-Object SiteCode -eq $code)
        if ($definition.Count -ne 1) { Stop-SccmWork 'Cannot compare installed updates without unique database definitions.' }
        $locations[$code] = Get-SccmDatabaseLocation $definition[0]
        if ($locations[$code].Database -notmatch '^CM_[A-Za-z0-9]{3}$' -or $code -notmatch '^[A-Za-z0-9]{3}$') { Stop-SccmWork 'Unexpected update-history database identity.' }
    }
    $histories = @{}
    foreach ($code in @($ParentCode, $SecondaryCode)) {
        $location = $locations[$code]
        $history = Invoke-SccmSqlQuery $location.Server "SELECT p.PackageGuid FROM [$($location.Database)].dbo.CM_UpdatePackageSiteStatus p INNER JOIN [$($location.Database)].dbo.SC_SiteDefinition s ON s.SiteNumber=p.SiteNumber WHERE s.SiteCode='$code' AND p.State=196612"
        $histories[$code] = @($history.Rows | ForEach-Object { [string]$_.PackageGuid })
    }
    if (-not $histories[$ParentCode].Count) { Stop-SccmWork 'Parent installed-update history changed; recheck it before secondary recovery.' }
    return @($histories[$ParentCode] | Where-Object { $_ -notin $histories[$SecondaryCode] })
}

function Request-SccmSecondaryUpdateRecovery {
    param([string]$Provider, [string]$ParentCode, [string]$SecondaryCode,
        [string]$Server, [string]$ExpectedVersion, [bool]$Preview = $true)
    # Same-build fixes use the documented Recover Secondary Site workflow.
    # Invoke-CMSecondarySiteUpgrade only accepts a lower BuildNumber. Preview
    # returns before backups or provider writes; it never relies on WhatIf.
    if ($ParentCode -notmatch '^[A-Za-z0-9]{3}$' -or $SecondaryCode -notmatch '^[A-Za-z0-9]{3}$') { Stop-SccmWork 'Invalid recovery site code.' }
    $sites = @(Get-SccmProviderData $Provider $ParentCode 'SMS_Site')
    $parent = @($sites | Where-Object SiteCode -eq $ParentCode)
    $secondary = @($sites | Where-Object SiteCode -eq $SecondaryCode)
    if ($parent.Count -ne 1 -or $secondary.Count -ne 1 -or $parent[0].Type -ne 2 -or
        $parent[0].Status -ne 1 -or [version]$parent[0].Version -ne [version]$ExpectedVersion -or
        $secondary[0].Type -ne 1 -or $secondary[0].Status -ne 1 -or $secondary[0].ReportingSiteCode -ine $ParentCode -or
        $secondary[0].ServerName -ine $Server -or $secondary[0].SecondarySiteCMUpdateStatus -ne 0 -or
        ([version]$secondary[0].Version).Build -ne ([version]$ExpectedVersion).Build -or
        [version]$secondary[0].Version -gt [version]$ExpectedVersion) { Stop-SccmWork 'Secondary recovery identity, version or idle update status changed.' }
    $active = @(Get-SccmProviderData $Provider $ParentCode 'SMS_CM_UpdatePackageSiteStatus' | Where-Object { Test-SccmUpdateInstalling $_.State })
    if ($active.Count) { Stop-SccmWork 'A site update is active; do not request secondary recovery.' }
    $links = @(Get-SccmProviderData $Provider $ParentCode 'SMS_ReplicationLinkStatus' | Where-Object { $_.ChildSite -eq $SecondaryCode -and $_.ParentSite -eq $ParentCode })
    if (-not $links.Count -or @($links | Where-Object { $_.InitializationStatus -ne 6 -or $_.FailedSyncs -gt 0 -or $_.DegradedSyncs -gt 0 }).Count) { Stop-SccmWork 'Secondary replication must finish initialization before update recovery.' }
    $hostState = Get-SccmHostSiteState $Server
    if ($hostState.ServiceStatus -ne 'Running' -or [version]$hostState.Version -ne [version]$secondary[0].Version) { Stop-SccmWork 'The secondary host does not match its active provider version.' }
    $installing = Invoke-SccmRemote $Server { return @(Get-Process setup,setupwpf,SMS_BOOTSTRAP,msiexec -ErrorAction SilentlyContinue).Count -gt 0 }
    if ($installing) { Stop-SccmWork 'Native secondary setup is already active.' }
    $definitions = @(Get-SccmProviderData $Provider $ParentCode 'SMS_SCI_SiteDefinition' "SiteCode='$SecondaryCode'")
    if ($definitions.Count -ne 1) { Stop-SccmWork 'No unique secondary database definition exists.' }
    $database = Get-SccmDatabaseLocation $definitions[0]
    if ($database.Database -ine "CM_$SecondaryCode" -or ($database.Server -split '[\\.]')[0] -ine ($Server -split '\.')[0]) { Stop-SccmWork 'Secondary database identity does not match its server.' }
    $missing = @(Get-SccmSecondaryMissingUpdatePackages $Provider $ParentCode $SecondaryCode)
    if (-not $missing.Count) {
        Write-SccmLog "Secondary $SecondaryCode has the installed packages locally; waiting for its native parent report without another recovery."
        return @{Site=$SecondaryCode;Server=$Server;Submitted=$false;Preview=$Preview;WaitingForParentReport=$true;Backup=$null}
    }
    $connection = New-SccmManagementConnection $Provider $ParentCode
    try {
        $path = 'SMS_SCI_SiteDefinition.FileType=2,ItemName="Site Definition",ItemType="Site Definition",SiteCode="' + $SecondaryCode + '"'
        $definition = $connection.GetInstance($path)
        $properties = $definition.EmbeddedProperties
        if (-not $properties.ContainsKey('Requested Status') -or $properties['Requested Status']['Value1'].StringValue -ne '1') { Stop-SccmWork 'Another secondary request is pending; recovery was not submitted.' }
        if ($properties.ContainsKey('Setup Source Directory')) { Stop-SccmWork 'Automatic update recovery requires files copied from the current parent; review the custom setup source first.' }
        $result = @{Site=$SecondaryCode;Server=$Server;Operation='1011';Submitted=$false;Preview=$Preview;Backup=$null;MissingPackages=$missing}
        if ($Preview) { return $result }
        $backup = Backup-SccmDatabase $database.Server $database.Database
        if (-not $backup.BackupPath -or $backup.Database -ine $database.Database) { Stop-SccmWork 'A verified secondary backup is required before recovery.' }
        $result.Backup = $backup
        $definition.Get()
        $properties = $definition.EmbeddedProperties
        if (-not $properties.ContainsKey('Requested Status') -or $properties['Requested Status']['Value1'].StringValue -ne '1' -or
            $properties.ContainsKey('Setup Source Directory')) { Stop-SccmWork 'The secondary request changed during backup; recovery was not submitted.' }
        # Match the console's pending recovery request. SCCM owns service stops,
        # database reinitialization and all resulting status/package records.
        $request = $properties['Requested Status']
        $request['Value1'].StringValue = '2'
        $request['Value2'].StringValue = '1011'
        if (-not $properties.ContainsKey('PreReq Check')) {
            $check = $connection.CreateEmbeddedObjectInstance('SMS_EmbeddedProperty')
            $check['PropertyName'].StringValue = 'PreReq Check'
            $properties.Add('PreReq Check', $check)
        }
        $properties['PreReq Check']['Value'].IntegerValue = 1
        $properties['PreReq Check']['Value1'].StringValue = ''
        $properties['PreReq Check']['Value2'].StringValue = ''
        $definition.EmbeddedProperties = $properties
        [void]$definition.Put()
        $result.Submitted = $true
        Write-SccmLog "Requested native update recovery for secondary $SecondaryCode; verified backup: $($backup.BackupPath)."
        return $result
    } finally { $connection.Dispose() }
}

function Complete-SccmSecondaryUpdates {
    param([string]$Provider, [string]$SiteCode, [int]$TimeoutMinutes = 180, [int]$StalledMinutes = 20)
    $changed = $false
    $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site')
    foreach ($secondary in @($sites | Where-Object Type -eq 1)) {
        $parent = @($sites | Where-Object SiteCode -eq $secondary.ReportingSiteCode)[0]
        $parentProviders = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SysResUse' | Where-Object { $_.SiteCode -eq $parent.SiteCode -and $_.RoleName -eq 'SMS Provider' })
        if (-not $parentProviders.Count) { Stop-SccmWork "No SMS Provider was found for parent $($parent.SiteCode)." }
        $parentProvider = Select-SccmSiteProvider $parentProviders $parent.ServerName
        if (([version]$secondary.Version).Build -lt ([version]$parent.Version).Build -and
            $secondary.Status -in @(1,7) -and $secondary.SecondarySiteCMUpdateStatus -in @(0,1)) {
            Connect-SccmSite $parent.SiteCode $parentProvider
            Write-SccmLog "Requesting secondary upgrade $($secondary.SiteCode) under $($parent.SiteCode)."
            Invoke-CMSecondarySiteUpgrade -SecondarySiteCode $secondary.SiteCode -Force -ErrorAction Stop | Out-Null
            $changed = $true
        } elseif ($secondary.Status -eq 1 -and $secondary.SecondarySiteCMUpdateStatus -eq 0 -and
            ([version]$secondary.Version).Build -eq ([version]$parent.Version).Build) {
            Wait-SccmCondition -Description "secondary $($secondary.SiteCode) replication initializes before update recovery" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
                $links = @(Get-SccmProviderData $parentProvider $parent.SiteCode 'SMS_ReplicationLinkStatus' | Where-Object { $_.ChildSite -eq $secondary.SiteCode -and $_.ParentSite -eq $parent.SiteCode })
                return $links.Count -gt 0 -and @($links | Where-Object { $_.InitializationStatus -ne 6 -or $_.FailedSyncs -gt 0 -or $_.DegradedSyncs -gt 0 }).Count -eq 0
            }
            # Re-read after initialization: a new site's package report may
            # already have arrived without needing recovery.
            $current = @(Get-SccmProviderData $parentProvider $parent.SiteCode 'SMS_Site' "SiteCode='$($secondary.SiteCode)'")[0]
            if ($current.Status -eq 1 -and $current.SecondarySiteCMUpdateStatus -eq 0) {
                # A secondary never receives a same-build hotfix by itself;
                # submit native Recover Secondary Site and wait below.
                $request = Request-SccmSecondaryUpdateRecovery $parentProvider $parent.SiteCode $secondary.SiteCode $secondary.ServerName $parent.Version $false
                $changed = $changed -or $request.Submitted
            }
        } else {
            Write-SccmLog "Secondary $($secondary.SiteCode) is current or already processing an upgrade (status $($secondary.SecondarySiteCMUpdateStatus))."
        }
        # SCCM can restart the secondary's components before its setup finishes;
        # the replication sender then stops and the parent never receives the
        # package report. Once setup has exited and links to the parent stay
        # unhealthy, restart SMS_EXECUTIVE on the secondary once.
        $stall = @{Since = $null; Restarted = $false}
        Wait-SccmCondition -Description "secondary $($secondary.SiteCode) matches parent $($parent.SiteCode)" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
            $current = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' "SiteCode='$($secondary.SiteCode)'")[0]
            if ($current.Status -eq 1 -and [version]$current.Version -ge [version]$parent.Version -and $current.SecondarySiteCMUpdateStatus -eq 1) { return $true }
            if ($stall.Restarted -or $current.Status -ne 1) { return $false }
            $links = @(Get-SccmProviderData $parentProvider $parent.SiteCode 'SMS_ReplicationLinkStatus' | Where-Object { $_.ChildSite -eq $secondary.SiteCode -and $_.ParentSite -eq $parent.SiteCode })
            $setup = Invoke-SccmRemote $secondary.ServerName { return @(Get-Process setup,setupwpf,SMS_BOOTSTRAP -ErrorAction SilentlyContinue).Count -gt 0 }
            if ($setup -or -not @($links | Where-Object { $_.FailedSyncs -gt 0 -or $_.DegradedSyncs -gt 0 }).Count) { $stall.Since = $null; return $false }
            if ($null -eq $stall.Since) { $stall.Since = [DateTime]::UtcNow; return $false }
            if ([DateTime]::UtcNow - $stall.Since -lt [TimeSpan]::FromMinutes($StalledMinutes)) { return $false }
            $stall.Restarted = $true
            Write-SccmLog "Secondary $($secondary.SiteCode) links to $($parent.SiteCode) stayed unhealthy for $StalledMinutes minutes after setup; restarting SMS_EXECUTIVE once."
            Invoke-SccmRemote $secondary.ServerName {
                Restart-Service SMS_EXECUTIVE -Force -ErrorAction Stop
                (Get-Service SMS_EXECUTIVE).WaitForStatus('Running', [TimeSpan]::FromMinutes(20))
            }
            return $false
        }
        Wait-SccmSiteReady $Provider $SiteCode $secondary.SiteCode $secondary.ServerName $TimeoutMinutes
    }
    Connect-SccmSite $SiteCode $Provider
    return $changed
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
    Remove-SccmOlderDatabaseBackups (($Server -split '\\')[0]) $backupDirectory $Database $destination
    return @{Server = $Server; Database = $Database; BackupPath = $destination}
}

function Remove-SccmOlderDatabaseBackups {
    param([string]$ComputerName, [string]$BackupDirectory, [string]$Database, [string]$KeepPath)
    # Keep only the newest verified lab backup of each database; every
    # servicing step otherwise adds another full copy. Other backups are
    # never touched, and a failed cleanup never blocks servicing.
    try {
        $share = 'Microsoft.PowerShell.Core\FileSystem::' + (ConvertTo-SccmAdminShare $ComputerName $BackupDirectory.TrimEnd('\'))
        $keep = Split-Path -Leaf $KeepPath
        $pattern = '^' + [regex]::Escape($Database) + '_ludus_[0-9]{17}\.bak$'
        foreach ($old in @(Get-ChildItem -LiteralPath $share -File -ErrorAction Stop | Where-Object { $_.Name -match $pattern -and $_.Name -ne $keep })) {
            Remove-Item -LiteralPath $old.FullName -Force -ErrorAction Stop
            Write-SccmLog "Removed older lab backup $($old.Name) from $ComputerName."
        }
    } catch {
        Write-SccmLog "Could not remove older lab backups of $Database on ${ComputerName}: $($_.Exception.Message)" 'WARNING'
    }
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
    # A UNC path otherwise resolves through CMSite when its drive is current.
    if (-not (Test-Path -LiteralPath "Microsoft.PowerShell.Core\FileSystem::$source") -or ([version](Get-Item -LiteralPath "Microsoft.PowerShell.Core\FileSystem::$source").VersionInfo.FileVersion).Major -ne 16) {
        Stop-SccmWork "Secondary $Server needs SQL 2022 Express, but parent media does not contain it: $source. Update the parent to 2509 first; for a historical target, upgrade secondary SQL separately before rerunning."
    }
    $definition = @{Server = "$Server\$InstanceName"; Database = "CM_$SecondarySiteCode"}
    Write-SccmLog "Preparing the existing $InstanceName instance on $Server for an in-place SQL upgrade."
    [void](Backup-SccmDatabase $definition.Server $definition.Database)
    $destination = ConvertTo-SccmAdminShare $Server $WorkDirectory
    [void][IO.Directory]::CreateDirectory($destination)
    Copy-SccmFile -LiteralPath "$WorkDirectory\SccmDeployment.psm1" -Destination "$destination\SccmDeployment.psm1"
    Copy-SccmFile -LiteralPath $source -Destination "$destination\sql2022-express.exe"
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

function Test-SccmStorageSummaryReady {
    param([object]$Summary)
    # This class describes storage health. AvailabilityState has an unspecified
    # default of zero, including for healthy MPs; don't invent a required enum.
    if ($null -eq $Summary -or $null -eq $Summary.Status -or $Summary.Status -ne 0) { return $false }
    return $null -eq $Summary.DownSince -or $Summary.DownSince -is [DBNull] -or [string]::IsNullOrWhiteSpace([string]$Summary.DownSince)
}

function Test-SccmManagementPointEndpoint {
    param([string]$Server)
    if ($Server -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { Stop-SccmWork 'Invalid management-point server name.' }
    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://$Server/sms_mp/.sms_aut?mplist" -TimeoutSec 30 -ErrorAction Stop
    return $response.StatusCode -eq 200 -and [string]$response.Content -match '(?i)<MPList\b|<MP\b'
}

function Get-SccmProductionClientVersion {
    param([string]$Provider, [string]$SiteCode, [string]$MsiPath)
    $baseline = @(Get-SccmProviderData $Provider $SiteCode 'SMS_ClientBaseline' 'BaselineType=1')
    if ($baseline.Count -ne 1 -or -not $baseline[0].ClientVersion) { Stop-SccmWork 'No unique production client baseline is available.' }
    $version = [version]$baseline[0].ClientVersion
    $msiVersion = [version](Get-SccmMsiVersion $MsiPath)
    if ($version.Build -ne $msiVersion.Build -or $version -lt $msiVersion) { Stop-SccmWork 'Production client baseline and local MSI media do not match the same release.' }
    return [string]$baseline[0].ClientVersion
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
        [void]$view.Execute()
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
    # The MSI inventory can retain its original revision after console files
    # are installed. Native console setup records its actual product version
    # separately: baseline 2509 has MSI 1000 and AdminConsoleVersion 1200.
    $native = @(
        foreach ($path in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\ConfigMgr10\Setup',
                            'HKLM:\SOFTWARE\Microsoft\ConfigMgr10\Setup')) {
            $setup = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
            if ($setup -and $setup.AdminConsoleVersion) { $setup }
        }
    )
    if ($native.Count -ne 1 -or -not $native[0].'UI Installation Directory') {
        Stop-SccmWork 'The installed console has no unique native AdminConsoleVersion and installation directory. Review its setup log.'
    }
    $binary = Join-Path $native[0].'UI Installation Directory' 'bin\Microsoft.ConfigurationManagement.exe'
    if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { Stop-SccmWork 'The registered console executable is missing.' }
    $version = [version]$native[0].AdminConsoleVersion
    $msi = [version]$consoles[0].DisplayVersion
    if ($version.Major -ne $msi.Major -or $version.Minor -ne $msi.Minor -or $version -lt $msi) {
        Stop-SccmWork 'Native console version and installed MSI inventory are inconsistent. Review its setup log.'
    }
    return [string]$native[0].AdminConsoleVersion
}

function Get-SccmInstalledClient {
    try {
        return Get-CimInstance -Namespace root\ccm -ClassName SMS_Client -ErrorAction Stop
    } catch {
        # An MP can run CcmExec from SMS_CCM without an installed client.
        # Access, transport and provider failures must still be reported.
        if ([string]$_.Exception.NativeErrorCode -in @('InvalidClass', 'InvalidNamespace')) { return $null }
        throw
    }
}

function Get-SccmClientState {
    $client = Get-CimInstance -Namespace root\ccm -ClassName SMS_Client -ErrorAction Stop
    $service = Get-Service CcmExec -ErrorAction Stop
    $assigned = (Invoke-CimMethod -Namespace root\ccm -ClassName SMS_Client -MethodName GetAssignedSite -ErrorAction Stop).sSiteCode
    $setupRunning = @(Get-Process ccmsetup -ErrorAction SilentlyContinue).Count -gt 0
    $rebootRequired = $false
    $bootTimeUtc = ''
    $setupExitCode = $null
    $setupFinishedUtc = ''
    $log = Join-Path $env:windir 'ccmsetup\Logs\ccmsetup.log'
    if (-not $setupRunning -and (Test-Path -LiteralPath $log)) {
        $tail = @(Get-Content -LiteralPath $log -Tail 100)
        $exitLine = @($tail | Select-String 'CcmSetup is exiting with return code [0-9]+' | Select-Object -Last 1)
        # The launcher also logs an exit right after starting the setup
        # service; only the service run deletes that service before exiting.
        if ($exitLine.Count -and [string]$exitLine[0] -match 'CcmSetup is exiting with return code ([0-9]+)\]') {
            $code = [int]$Matches[1]
            $index = $exitLine[0].LineNumber - 1
            if (@($tail[[Math]::Max(0, $index - 15)..$index] | Where-Object { $_ -match 'Successfully deleted the ccmsetup service' }).Count) {
                $setupExitCode = $code
                $setupFinishedUtc = (Get-Item -LiteralPath $log).LastWriteTimeUtc.ToString('o')
            }
        }
        if ($exitLine.Count -and [string]$exitLine[0] -match 'CcmSetup is exiting with return code 7\]') {
            # File and boot times use the same guest clock. An old setup result
            # must not request another restart after that guest has rebooted.
            $boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
            $rebootRequired = (Get-Item -LiteralPath $log).LastWriteTime -ge $boot
            $bootTimeUtc = $boot.ToUniversalTime().ToString('o')
        }
    }
    return @{Version = [string]$client.ClientVersion; AssignedSite = [string]$assigned; Service = [string]$service.Status; SetupRunning = $setupRunning; RebootRequired = $rebootRequired; BootTimeUtc = $bootTimeUtc; SetupExitCode = $setupExitCode; SetupFinishedUtc = $setupFinishedUtc}
}

function Test-SccmClientReady {
    param([object]$State, [string]$Version, [string]$SiteCode)
    if ($null -eq $State) { return $false }
    if ($State.RebootRequired) { Stop-SccmWork 'Native client setup requires a guest restart. Restart this computer and rerun completion.' }
    return $State.Version -and [version]$State.Version -eq [version]$Version -and $State.AssignedSite -eq $SiteCode -and $State.Service -eq 'Running' -and -not $State.SetupRunning
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
