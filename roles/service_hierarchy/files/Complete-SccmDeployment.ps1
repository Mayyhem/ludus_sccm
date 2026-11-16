[CmdletBinding()]
param(
    [string]$WorkDirectory, [string]$Provider, [string]$SiteCode,
    [int]$TargetBuild, [int]$TimeoutMinutes = 180, [int]$ClientTimeoutMinutes = 90,
    [string[]]$AdditionalComputers = @(),
    [bool]$CheckpointForReboot = $false
)
$ErrorActionPreference = 'Stop'
Import-Module "$WorkDirectory\SccmDeployment.psm1" -Force
Set-SccmLog "$WorkDirectory\deployment-verification.log"
$report = @{StartedUtc = [DateTime]::UtcNow.ToString('s'); Complete = $false; Changed = $false; Sites = @(); Roles = @(); Clients = @(); Consoles = @(); BootImages = @(); Failures = @(); UnreachableClients = @(); RebootRequests = @()}
try {
    Connect-SccmSite $SiteCode $Provider
    $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site')
    $rootVersion = [version](@($sites | Where-Object SiteCode -eq $SiteCode)[0].Version)
    $roles = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SysResUse')
    foreach ($site in $sites) {
        if (([version]$site.Version).Build -ne $TargetBuild -or [version]$site.Version -ne $rootVersion -or $site.Status -ne 1) { Stop-SccmWork "Site $($site.SiteCode) has unexpected version/readiness: $($site.Version), status $($site.Status); expected $rootVersion." }
        Wait-SccmSiteReady $Provider $SiteCode $site.SiteCode $site.ServerName $TimeoutMinutes
        $report.Sites += @{Site = $site.SiteCode; Server = $site.ServerName; Version = $site.Version; Ready = $true}
    }
    foreach ($role in @($roles | Where-Object RoleName -eq 'SMS Site Server')) {
        $site = @($sites | Where-Object SiteCode -eq $role.SiteCode)[0]
        $server = ([string]$role.NetworkOSPath).Trim('\')
        if (($server -split '\.')[0] -ine ($site.ServerName -split '\.')[0]) {
            $passiveProvider = Get-SccmSiteProvider $Provider $SiteCode $site.SiteCode
            Wait-SccmPassiveReady $passiveProvider $site.SiteCode $server $TimeoutMinutes
        }
        # Active servers were checked above; passive servers need HA readiness.
    }
    Wait-SccmCondition -Description 'site servers, management points and distribution points report healthy' -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $health = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SiteSystemSummarizer' | Where-Object Role -in @('SMS Management Point', 'SMS Distribution Point', 'SMS Site Server'))
        if (-not $health.Count -or @($health | Where-Object { -not (Test-SccmStorageSummaryReady $_) }).Count) { return $false }
        foreach ($mp in @($roles | Where-Object RoleName -eq 'SMS Management Point')) {
            $mpServer = ([string]$mp.NetworkOSPath).Trim('\')
            if (-not (Test-SccmManagementPointEndpoint $mpServer)) { return $false }
        }
        return $true
    }
    $siteSystems = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SiteSystemSummarizer' | Where-Object Role -in @('SMS Management Point', 'SMS Distribution Point', 'SMS Site Server'))
    foreach ($system in $siteSystems) {
        $isReady = Test-SccmStorageSummaryReady $system
        $report.Roles += @{Site = $system.SiteCode; Role = $system.Role; System = $system.SiteSystem; Ready = $isReady; Status = $system.Status; Availability = $system.AvailabilityState}
        if (-not $isReady) { $report.Failures += "Site role is not healthy: $($system.Role) $($system.SiteSystem)" }
    }
    foreach ($role in @($roles | Where-Object RoleName -eq 'SMS Provider')) {
        $server = ([string]$role.NetworkOSPath).Trim('\')
        # Read each provider on its own host: passive and remote provider
        # servers need not accept remote WMI from the top-level site.
        $build = Invoke-SccmRemote $server {
            param($code)
            (Get-CimInstance -Namespace "root\SMS\site_$code" -ClassName SMS_Identification -ErrorAction Stop).SMSBuildNumber
        } @($role.SiteCode)
        if ($build -ne $TargetBuild) { $report.Failures += "Provider $server reports unexpected site build $build." }
    }
    # Registered clients are the scope. Unmanaged computers are not silently
    # enrolled, which would override the lab's client-push exclusions.
    $resources = @(Get-SccmProviderData $Provider $SiteCode 'SMS_R_System' | Where-Object { $_.Client -eq 1 -and $_.Obsolete -eq 0 })
    $computerNames = @(@($roles | ForEach-Object { ([string]$_.NetworkOSPath).Trim('\') }) + @($resources | ForEach-Object { Get-SccmResourceComputerName $_ }) + $AdditionalComputers | Where-Object { $_ } | Sort-Object -Unique)
    $primaries = @($sites | Where-Object Type -eq 2)
    $clientSources = @{}
    foreach ($site in $primaries) {
        $msi = ConvertTo-SccmAdminShare $site.ServerName "$($site.InstallDir)\Client\x64\client.msi"
        $providerRoles = @($roles | Where-Object { $_.SiteCode -eq $site.SiteCode -and $_.RoleName -eq 'SMS Provider' })
        if (-not $providerRoles.Count) { Stop-SccmWork "No provider exists for production client baseline $($site.SiteCode)." }
        $clientProvider = Select-SccmSiteProvider $providerRoles $site.ServerName
        $version = Get-SccmProductionClientVersion $clientProvider $site.SiteCode $msi
        $clientSources[$site.SiteCode] = @{Version = $version; Server = $site.ServerName; InstallDir = $site.InstallDir}
    }
    foreach ($computer in $computerNames) {
        try {
            $probe = Invoke-SccmRemote $computer { $env:COMPUTERNAME }
        } catch {
            Write-SccmLog "Unreachable management endpoint ${computer}: $($_.Exception.Message)" 'WARNING'
            if (@($roles | Where-Object { ([string]$_.NetworkOSPath).Trim('\') -ieq $computer }).Count) { $report.Failures += "Site system $computer is unreachable." }
            $report.UnreachableClients += $computer
            continue
        }
        try {
            $remoteDirectory = ConvertTo-SccmAdminShare $computer $WorkDirectory
            [void][IO.Directory]::CreateDirectory($remoteDirectory)
            if (($computer -split '\.')[0] -ine $env:COMPUTERNAME) {
                Copy-SccmFile -LiteralPath "$WorkDirectory\SccmDeployment.psm1" -Destination "$remoteDirectory\SccmDeployment.psm1"
            }
            $state = Invoke-SccmRemote $computer {
                param($directory)
                Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
                Import-Module "$directory\SccmDeployment.psm1"
                Set-SccmLog "$directory\client-and-console.log" -OnlyIfUnset
                $console = Get-SccmConsoleVersion
                $client = Get-SccmInstalledClient
                $clientVersion = $null
                $assignedSite = $null
                if ($client) {
                    $clientVersion = [string]$client.ClientVersion
                    $assignedSite = (Invoke-CimMethod -Namespace root\ccm -ClassName SMS_Client -MethodName GetAssignedSite -ErrorAction Stop).sSiteCode
                }
                # A site system may have a console without being a client.
                return @{ConsoleVersion = $console; ClientVersion = $clientVersion; AssignedSite = $assignedSite; PendingRestarts = @(Get-SccmPendingRestartRequests)}
            } @($WorkDirectory)
            $owner = @($sites | Where-Object SiteCode -eq $state.AssignedSite | Select-Object -First 1)
            if (-not $owner.Count) { $owner = @($sites | Where-Object { ($_.ServerName -split '\.')[0] -ieq ($computer -split '\.')[0] } | Select-Object -First 1) }
            if (-not $owner.Count) { $owner = @($primaries | Select-Object -First 1) }
            if (-not $owner.Count) { Stop-SccmWork "No owning site can be established for $computer." }
            $owningSite = $owner[0]
            if ($state.ConsoleVersion) {
                $ownerProviders = @($roles | Where-Object { $_.SiteCode -eq $owningSite.SiteCode -and $_.RoleName -eq 'SMS Provider' })
                if (-not $ownerProviders.Count) { Stop-SccmWork "No provider exists for console source site $($owningSite.SiteCode)." }
                $consoleProvider = Select-SccmSiteProvider $ownerProviders $owningSite.ServerName
                $identification = @(Get-SccmProviderData $consoleProvider $owningSite.SiteCode 'SMS_Identification')[0]
                $expectedConsole = [string]$identification.SMSAvailableConsoleVersion
                $pendingConsole = @($state.PendingRestarts | Where-Object Kind -eq 'Console')
                if ($pendingConsole.Count) {
                    if (-not $CheckpointForReboot -or $pendingConsole.Count -ne 1 -or $pendingConsole[0].Version -ne $expectedConsole) { Stop-SccmWork "Console on $computer has an unresolved restart checkpoint." }
                    $pendingConsole[0].Computer = $computer
                    $report.RebootRequests += $pendingConsole[0]
                    $report.Consoles += @{Computer=$computer;Version=[string]$state.ConsoleVersion;Expected=$expectedConsole;Ready=$false;RebootRequired=$true}
                    continue
                }
                if ([version]$state.ConsoleVersion -ne [version]$expectedConsole) {
                    if ([version]$state.ConsoleVersion -gt [version]$expectedConsole) { Stop-SccmWork "Console on $computer is newer than selected site media; downgrading it is not supported." }
                    $source = ConvertTo-SccmAdminShare $owningSite.ServerName "$($owningSite.InstallDir)\tools\ConsoleSetup"
                    [void][IO.Directory]::CreateDirectory("$remoteDirectory\ConsoleSetup")
                    Copy-SccmFile -Path "$source\*" -Destination "$remoteDirectory\ConsoleSetup" -Recurse
                    $consoleRestart = Invoke-SccmRemote $computer {
                        param($directory, $siteServer, $code, $version)
                        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
                        Import-Module "$directory\SccmDeployment.psm1"
                        Set-SccmLog "$directory\client-and-console.log" -OnlyIfUnset
                        $targetDirectory = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Configuration Manager\AdminConsole'
                        $reboot = Invoke-SccmInstaller -Path "$directory\ConsoleSetup\ConsoleSetup.exe" -Arguments "/q `"TargetDir=$targetDirectory`" DefaultSiteServerName=$siteServer" -TimeoutMinutes 30
                        if ($reboot) { return New-SccmRestartRequest $env:COMPUTERNAME Console $version $code -Persist }
                    } @($WorkDirectory, $owningSite.ServerName, $owningSite.SiteCode, $expectedConsole)
                    $report.Changed = $true
                    if ($consoleRestart) {
                        if (-not $CheckpointForReboot) { Stop-SccmWork "Console on $computer requires a restart." }
                        $consoleRestart.Computer = $computer
                        $report.RebootRequests += $consoleRestart
                        $report.Consoles += @{Computer=$computer;Version=[string]$state.ConsoleVersion;Expected=$expectedConsole;Ready=$false;RebootRequired=$true}
                        continue
                    }
                } else { Write-SccmLog "Console on $computer is already current." }
                $consoleVersion = Invoke-SccmRemote $computer { param($directory) Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop; Import-Module "$directory\SccmDeployment.psm1"; Get-SccmConsoleVersion } @($WorkDirectory)
                if ([version]$consoleVersion -ne [version]$expectedConsole) { Stop-SccmWork "Console on $computer did not reach $expectedConsole." }
                $report.Consoles += @{Computer = $computer; Version = [string]$consoleVersion; Expected = $expectedConsole; Ready = $true}
            }
            # A machine without an installed console is deliberately not given one.
            if ($state.ClientVersion) {
                if (-not $clientSources.ContainsKey([string]$state.AssignedSite)) { Stop-SccmWork "Client $computer has unknown assigned site $($state.AssignedSite)." }
                $clientSource = $clientSources[[string]$state.AssignedSite]
                $clientVersion = [string]$state.ClientVersion
                $setupRuns = 0
                while ($true) {
                    $launchedUtc = $null
                    if ([version]$clientVersion -ne [version]$clientSource.Version) {
                        if ([version]$clientVersion -gt [version]$clientSource.Version) { Stop-SccmWork "Client $computer is newer than the selected production source; downgrading it is not supported." }
                        if (-not $setupRuns) {
                            $source = ConvertTo-SccmAdminShare $clientSource.Server "$($clientSource.InstallDir)\Client"
                            [void][IO.Directory]::CreateDirectory("$remoteDirectory\Client")
                            Copy-SccmFile -Path "$source\*" -Destination "$remoteDirectory\Client" -Recurse
                        }
                        $setupRuns++
                        $launchedUtc = Invoke-SccmRemote $computer {
                            param($directory, $siteServer, $code)
                            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
                            Import-Module "$directory\SccmDeployment.psm1"
                            Set-SccmLog "$directory\client-and-console.log" -OnlyIfUnset
                            # Guest clock, compared below with the guest's setup log.
                            $started = [DateTime]::UtcNow
                            # Copy all source files first so this remote process
                            # does not need to pass credentials to a third host.
                            [void](Invoke-SccmInstaller "$directory\Client\ccmsetup.exe" "/source:`"$directory\Client`" SMSSITECODE=$code" @(0, 8))
                            return $started.ToString('o')
                        } @($WorkDirectory, $clientSource.Server, $state.AssignedSite) | Select-Object -Last 1
                        $report.Changed = $true
                    } else { Write-SccmLog "Client $computer is already current." }
                    $clientCheckpoint = @{State=$null; Rerun=$false}
                    Wait-SccmCondition -Description "client $computer reaches a completed installation checkpoint" -TimeoutMinutes $ClientTimeoutMinutes -RetryReadErrors -Test {
                        $actual = Invoke-SccmRemote $computer {
                            param($directory)
                            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
                            Import-Module "$directory\SccmDeployment.psm1"
                            Get-SccmClientState
                        } @($WorkDirectory)
                        $clientCheckpoint.State = $actual
                        if ($CheckpointForReboot -and $actual.RebootRequired -and -not $actual.SetupRunning -and $actual.Version -and (-not $actual.AssignedSite -or $actual.AssignedSite -eq $state.AssignedSite) -and [version]$actual.Version -le [version]$clientSource.Version) { return $true }
                        # Native setup applies only the client patches valid for
                        # the installed level; a later one can need another run.
                        if ($launchedUtc -and -not $actual.SetupRunning -and -not $actual.RebootRequired -and $actual.SetupExitCode -eq 0 -and $actual.SetupFinishedUtc -and
                            [DateTime]::Parse($actual.SetupFinishedUtc).ToUniversalTime() -gt [DateTime]::Parse($launchedUtc).ToUniversalTime() -and
                            $actual.Version -and [version]$actual.Version -lt [version]$clientSource.Version -and $actual.Service -eq 'Running') { $clientCheckpoint.Rerun = $true; return $true }
                        return Test-SccmClientReady $actual $clientSource.Version $state.AssignedSite
                    }
                    if (-not $clientCheckpoint.Rerun) { break }
                    $clientVersion = [string]$clientCheckpoint.State.Version
                    if ($setupRuns -ge 3) { Stop-SccmWork "Client $computer finished setup at $clientVersion after $setupRuns runs; expected $($clientSource.Version)." }
                    Write-SccmLog "Client $computer finished setup at $clientVersion below $($clientSource.Version); running setup again for the remaining client patches."
                }
                if ($clientCheckpoint.State.RebootRequired) {
                    $report.RebootRequests += @{Computer=$computer;Kind='Client';Version=[string]$clientCheckpoint.State.Version;DesiredVersion=[string]$clientSource.Version;SiteCode=[string]$state.AssignedSite;BootTimeUtc=[string]$clientCheckpoint.State.BootTimeUtc;PackageGuid=''}
                    $report.Clients += @{Computer=$computer;Site=$state.AssignedSite;Version=[string]$clientCheckpoint.State.Version;Expected=[string]$clientSource.Version;Ready=$false;RebootRequired=$true}
                } else {
                    $report.Clients += @{Computer = $computer; Site = $state.AssignedSite; Version = $clientSource.Version; Ready = $true}
                }
            }
        } catch {
            Write-SccmLog "Component update failed on ${computer}: $($_.Exception.Message)" 'ERROR'
            $report.Failures += "${computer}: $($_.Exception.Message)"
        }
    }
    if ($report.RebootRequests.Count) {
        if ($report.Failures.Count -or $report.UnreachableClients.Count) { Stop-SccmWork 'Component failures must be resolved before restarting checkpointed guests. See deployment-report.json.' }
        Write-SccmLog "Completion paused at $($report.RebootRequests.Count) native guest restart checkpoints. Ansible will restart and resume."
        return $report
    }
    # A successful previous run can verify existing boot-image distribution
    # without recreating images every time the playbooks are rerun.
    $journalPath = "$WorkDirectory\boot-image-journal.json"
    $oldJournal = @{}
    if (Test-Path -LiteralPath $journalPath) {
        $old = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        foreach ($entry in @($old)) {
            if ($null -ne $entry) { $oldJournal[[string]$entry.PackageID] = $entry }
            # An empty journal contains no completed distribution to reuse.
        }
    }
    foreach ($primary in $primaries) {
        $primaryProvider = Select-SccmSiteProvider @($roles | Where-Object { $_.SiteCode -eq $primary.SiteCode -and $_.RoleName -eq 'SMS Provider' }) $primary.ServerName
        Connect-SccmSite $primary.SiteCode $primaryProvider
        $images = @(Get-SccmProviderData $primaryProvider $primary.SiteCode 'SMS_BootImagePackage')
        foreach ($image in $images) {
            $distribution = @(Get-SccmProviderData $primaryProvider $primary.SiteCode 'SMS_PackageStatusDistPointsSummarizer' "PackageID='$($image.PackageID)'")
            if (-not $distribution.Count) { Write-SccmLog "Boot image $($image.PackageID) is not distributed and is not in the lab's deployed-image scope."; continue }
            $fingerprint = [string]$primary.Version + ':' + [string]$clientSources[$primary.SiteCode].Version
            $hasPrevious = $oldJournal.ContainsKey([string]$image.PackageID) -and $oldJournal[[string]$image.PackageID].Fingerprint -eq $fingerprint
            $expectedSource = [int]$image.SourceVersion
            if (-not $hasPrevious) {
                $expectedSource++
                Update-CMDistributionPoint -BootImageId $image.PackageID -ReloadBootImage -Confirm:$false -ErrorAction Stop | Out-Null
                $report.Changed = $true
                Write-SccmLog "Requested refreshed boot image $($image.PackageID), source version at least $expectedSource."
            } else { Write-SccmLog "Verifying boot image $($image.PackageID) from the previous completed run." }
            Wait-SccmCondition -Description "boot image $($image.PackageID) is updated on every assigned distribution point" -TimeoutMinutes $TimeoutMinutes -Test {
                $current = @(Get-SccmProviderData $primaryProvider $primary.SiteCode 'SMS_PackageStatusDistPointsSummarizer' "PackageID='$($image.PackageID)'")
                return $current.Count -ge $distribution.Count -and @($current | Where-Object { $_.State -ne 0 -or $_.SourceVersion -lt $expectedSource }).Count -eq 0
            }
            $report.BootImages += @{PackageID = $image.PackageID; Fingerprint = $fingerprint; SourceVersion = $expectedSource; Ready = $true}
        }
    }
    ConvertTo-Json -InputObject @($report.BootImages) -Depth 5 | Set-Content $journalPath -Encoding UTF8
    Assert-SccmReplication $Provider $SiteCode
    $report.Complete = $report.Failures.Count -eq 0 -and $report.UnreachableClients.Count -eq 0
    if (-not $report.Complete) { Stop-SccmWork 'Some components failed verification. See deployment-report.json for the complete list.' }
    return $report
} catch {
    Write-SccmLog "Final verification failed: $($_.Exception.Message)" 'ERROR'
    $report.Failures += $_.Exception.Message
    throw
} finally {
    $report.FinishedUtc = [DateTime]::UtcNow.ToString('s')
    $report | ConvertTo-Json -Depth 10 | Set-Content "$WorkDirectory\deployment-report.json" -Encoding UTF8
    Set-Location $env:SystemDrive\
}
