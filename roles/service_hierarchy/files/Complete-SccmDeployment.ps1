[CmdletBinding()]
param(
    [string]$WorkDirectory, [string]$Provider, [string]$SiteCode,
    [int]$TargetBuild, [int]$TimeoutMinutes = 180, [int]$ClientTimeoutMinutes = 90,
    [string[]]$AdditionalComputers = @()
)
$ErrorActionPreference = 'Stop'
Import-Module "$WorkDirectory\SccmDeployment.psm1" -Force
Set-SccmLog "$WorkDirectory\deployment-verification.log"
$report = @{StartedUtc = [DateTime]::UtcNow.ToString('s'); Complete = $false; Changed = $false; Sites = @(); Roles = @(); Clients = @(); Consoles = @(); BootImages = @(); Failures = @(); UnreachableClients = @()}
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
        return $health.Count -gt 0 -and @($health | Where-Object { $_.Status -ne 0 -or $_.AvailabilityState -ne 4 }).Count -eq 0
    }
    $siteSystems = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SiteSystemSummarizer' | Where-Object Role -in @('SMS Management Point', 'SMS Distribution Point', 'SMS Site Server'))
    foreach ($system in $siteSystems) {
        $isReady = $system.Status -eq 0 -and $system.AvailabilityState -eq 4
        $report.Roles += @{Site = $system.SiteCode; Role = $system.Role; System = $system.SiteSystem; Ready = $isReady; Status = $system.Status; Availability = $system.AvailabilityState}
        if (-not $isReady) { $report.Failures += "Site role is not healthy: $($system.Role) $($system.SiteSystem)" }
    }
    foreach ($role in @($roles | Where-Object RoleName -eq 'SMS Provider')) {
        $server = ([string]$role.NetworkOSPath).Trim('\')
        $identification = @(Get-SccmProviderData $server $role.SiteCode 'SMS_Identification')[0]
        if ($identification.SMSBuildNumber -ne $TargetBuild) { $report.Failures += "Provider $server reports unexpected site build $($identification.SMSBuildNumber)." }
    }
    # Registered clients are the scope. Unmanaged computers are not silently
    # enrolled, which would override the lab's client-push exclusions.
    $resources = @(Get-SccmProviderData $Provider $SiteCode 'SMS_R_System' | Where-Object { $_.Client -eq 1 -and $_.Obsolete -eq 0 })
    $computerNames = @(@($roles | ForEach-Object { ([string]$_.NetworkOSPath).Trim('\') }) + @($resources | ForEach-Object { Get-SccmResourceComputerName $_ }) + $AdditionalComputers | Where-Object { $_ } | Sort-Object -Unique)
    $primaries = @($sites | Where-Object Type -eq 2)
    $clientSources = @{}
    foreach ($site in $primaries) {
        $msi = ConvertTo-SccmAdminShare $site.ServerName "$($site.InstallDir)\Client\x64\client.msi"
        $clientSources[$site.SiteCode] = @{Version = (Get-SccmMsiVersion $msi); Server = $site.ServerName; InstallDir = $site.InstallDir}
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
            Copy-Item "$WorkDirectory\SccmDeployment.psm1" "$remoteDirectory\SccmDeployment.psm1" -Force
            $state = Invoke-SccmRemote $computer {
                param($directory)
                Import-Module "$directory\SccmDeployment.psm1" -Force
                Set-SccmLog "$directory\client-and-console.log"
                $console = Get-SccmConsoleVersion
                $client = Get-Service CcmExec -ErrorAction SilentlyContinue
                $clientVersion = $null
                $assignedSite = $null
                if ($client) {
                    $instance = Get-CimInstance -Namespace root\ccm -ClassName SMS_Client -ErrorAction Stop
                    $clientVersion = [string]$instance.ClientVersion
                    $assignedSite = (Invoke-CimMethod -Namespace root\ccm -ClassName SMS_Client -MethodName GetAssignedSite -ErrorAction Stop).sSiteCode
                }
                # A site system may have a console without being a client.
                return @{ConsoleVersion = $console; ClientVersion = $clientVersion; AssignedSite = $assignedSite}
            } @($WorkDirectory)
            $owner = @($sites | Where-Object SiteCode -eq $state.AssignedSite | Select-Object -First 1)
            if (-not $owner.Count) { $owner = @($sites | Where-Object { ($_.ServerName -split '\.')[0] -ieq ($computer -split '\.')[0] } | Select-Object -First 1) }
            if (-not $owner.Count) { $owner = @($primaries | Select-Object -First 1) }
            if (-not $owner.Count) { Stop-SccmWork "No owning site can be established for $computer." }
            $owningSite = $owner[0]
            if ($state.ConsoleVersion) {
                $ownerProviders = @($roles | Where-Object { $_.SiteCode -eq $owningSite.SiteCode -and $_.RoleName -eq 'SMS Provider' })
                if (-not $ownerProviders.Count) { Stop-SccmWork "No provider exists for console source site $($owningSite.SiteCode)." }
                $consoleProvider = ([string]$ownerProviders[0].NetworkOSPath).Trim('\')
                $identification = @(Get-SccmProviderData $consoleProvider $owningSite.SiteCode 'SMS_Identification')[0]
                $expectedConsole = [string]$identification.SMSAvailableConsoleVersion
                if ([version]$state.ConsoleVersion -ne [version]$expectedConsole) {
                    if ([version]$state.ConsoleVersion -gt [version]$expectedConsole) { Stop-SccmWork "Console on $computer is newer than selected site media; downgrading it is not supported." }
                    $source = ConvertTo-SccmAdminShare $owningSite.ServerName "$($owningSite.InstallDir)\tools\ConsoleSetup"
                    [void][IO.Directory]::CreateDirectory("$remoteDirectory\ConsoleSetup")
                    Copy-Item "$source\*" "$remoteDirectory\ConsoleSetup" -Recurse -Force
                    Invoke-SccmRemote $computer {
                        param($directory, $siteServer)
                        Import-Module "$directory\SccmDeployment.psm1" -Force
                        Set-SccmLog "$directory\client-and-console.log"
                        [void](Invoke-SccmInstaller "$directory\ConsoleSetup\ConsoleSetup.exe" "/q DefaultSiteServerName=$siteServer")
                    } @($WorkDirectory, $owningSite.ServerName)
                    $report.Changed = $true
                } else { Write-SccmLog "Console on $computer is already current." }
                $consoleVersion = Invoke-SccmRemote $computer { param($directory) Import-Module "$directory\SccmDeployment.psm1" -Force; Get-SccmConsoleVersion } @($WorkDirectory)
                if ([version]$consoleVersion -ne [version]$expectedConsole) { Stop-SccmWork "Console on $computer did not reach $expectedConsole." }
                $report.Consoles += @{Computer = $computer; Version = $consoleVersion; Expected = $expectedConsole; Ready = $true}
            }
            # A machine without an installed console is deliberately not given one.
            if ($state.ClientVersion) {
                if (-not $clientSources.ContainsKey([string]$state.AssignedSite)) { Stop-SccmWork "Client $computer has unknown assigned site $($state.AssignedSite)." }
                $clientSource = $clientSources[[string]$state.AssignedSite]
                if ([version]$state.ClientVersion -ne [version]$clientSource.Version) {
                    if ([version]$state.ClientVersion -gt [version]$clientSource.Version) { Stop-SccmWork "Client $computer is newer than the selected production source; downgrading it is not supported." }
                    $source = ConvertTo-SccmAdminShare $clientSource.Server "$($clientSource.InstallDir)\Client"
                    [void][IO.Directory]::CreateDirectory("$remoteDirectory\Client")
                    Copy-Item "$source\*" "$remoteDirectory\Client" -Recurse -Force
                    Invoke-SccmRemote $computer {
                        param($directory, $siteServer, $code)
                        Import-Module "$directory\SccmDeployment.psm1" -Force
                        Set-SccmLog "$directory\client-and-console.log"
                        # Copy all source files first so this remote process
                        # does not need to pass credentials to a third host.
                        [void](Invoke-SccmInstaller "$directory\Client\ccmsetup.exe" "/source:`"$directory\Client`" SMSSITECODE=$code" @(0, 8))
                    } @($WorkDirectory, $clientSource.Server, $state.AssignedSite)
                    $report.Changed = $true
                    Wait-SccmCondition -Description "client $computer reaches $($clientSource.Version)" -TimeoutMinutes $ClientTimeoutMinutes -RetryReadErrors -Test {
                        $actual = Invoke-SccmRemote $computer { (Get-CimInstance -Namespace root\ccm -ClassName SMS_Client -ErrorAction Stop).ClientVersion }
                        return [version]$actual -eq [version]$clientSource.Version
                    }
                } else { Write-SccmLog "Client $computer is already current." }
                $report.Clients += @{Computer = $computer; Site = $state.AssignedSite; Version = $clientSource.Version; Ready = $true}
            }
        } catch {
            Write-SccmLog "Component update failed on ${computer}: $($_.Exception.Message)" 'ERROR'
            $report.Failures += "${computer}: $($_.Exception.Message)"
        }
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
        $providerRole = @($roles | Where-Object { $_.SiteCode -eq $primary.SiteCode -and $_.RoleName -eq 'SMS Provider' })[0]
        $primaryProvider = ([string]$providerRole.NetworkOSPath).Trim('\')
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
    $report.Complete = $report.Failures.Count -eq 0
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
