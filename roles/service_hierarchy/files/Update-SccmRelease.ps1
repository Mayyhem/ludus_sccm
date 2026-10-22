[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkDirectory,
    [Parameter(Mandatory)][string]$Provider,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][int]$TargetBuild,
    [Parameter(Mandatory)][string]$TargetRelease,
    [bool]$AllowWarnings = $false,
    [int]$TimeoutMinutes = 180
)
$ErrorActionPreference = 'Stop'
Import-Module "$WorkDirectory\SccmDeployment.psm1" -Force
Set-SccmLog "$WorkDirectory\hierarchy-update.log"
try {
    Connect-SccmSite $SiteCode $Provider
    $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site')
    $root = @($sites | Where-Object SiteCode -eq $SiteCode)[0]
    if ($root.ReportingSiteCode -or $root.Type -notin @(2, 4)) { Stop-SccmWork 'Hierarchy servicing must run at CAS or a standalone primary.' }
    $primaries = @($sites | Where-Object Type -in @(2, 4))
    Invoke-CMSiteUpdateCheck -ErrorAction Stop | Out-Null
    $hasChanged = $false
    $pending = @($primaries | Where-Object { ([version]$_.Version).Build -lt $TargetBuild })
    $active = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackages' | Where-Object { Test-SccmUpdateInstalling $_.State })
    if (@($active | Where-Object { ([version]$_.FullVersion).Build -ne $TargetBuild -or $_.UpdateType -ne 0 }).Count) {
        Stop-SccmWork 'A different update is already running. Finish that update before starting this release hop.'
    }
    if ($pending.Count -or $active.Count) {
        Wait-SccmCondition -Description "SCCM $TargetRelease becomes available in the normal update catalog" -TimeoutMinutes $TimeoutMinutes -Test {
            $matches = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackages' | Where-Object {
                $_.UpdateType -eq 0 -and ([version]$_.FullVersion).Build -eq $TargetBuild -and $_.State -notin @(393213, 393214)
            })
            return $matches.Count -gt 0
        }
        $package = Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackages' | Where-Object {
            $_.UpdateType -eq 0 -and ([version]$_.FullVersion).Build -eq $TargetBuild -and $_.State -notin @(393213, 393214)
        } | Sort-Object @{Expression = {[version]$_.FullVersion}} -Descending | Select-Object -First 1
        if (-not (Test-SccmUpdateInstalling $package.State) -and $package.State -ne 196612) {
            Assert-SccmUpdateReadiness $sites
            Assert-SccmReplication $Provider $SiteCode
            $definitions = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SiteDefinition')
            $backups = @()
            foreach ($site in $sites) {
                $definition = @($definitions | Where-Object SiteCode -eq $site.SiteCode)[0]
                $database = Get-SccmDatabaseLocation $definition
                $backups += Backup-SccmDatabase $database.Server $database.Database
                Set-SccmSqlCompatibility $database.Server
                if ($site.Type -in @(2, 4)) {
                    $recoverySource = ConvertTo-SccmAdminShare $site.ServerName "$($site.InstallDir)\cd.latest"
                    $recoveryDestination = "$WorkDirectory\recovery\$($site.SiteCode)\$($site.Version)"
                    [void][IO.Directory]::CreateDirectory($recoveryDestination)
                    Copy-Item -Path "$recoverySource\*" -Destination $recoveryDestination -Recurse -Force -ErrorAction Stop
                    Write-SccmLog "Saved $($site.SiteCode) CD.Latest recovery files."
                }
            }
            $backups | ConvertTo-Json -Depth 4 | Set-Content "$WorkDirectory\database-backups.json" -Encoding UTF8
        } else {
            Write-SccmLog 'Resuming an update already in progress; no new recovery copy is made from partially updated files.'
        }
        Install-SccmUpdatePackage $Provider $SiteCode $package $AllowWarnings $TimeoutMinutes
        $hasChanged = $true
    } else {
        Write-SccmLog "CAS and primary sites already meet the $TargetRelease release build."
    }
    Wait-SccmCondition -Description "all primary sites reach build $TargetBuild" -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $current = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' | Where-Object Type -in @(2, 4))
        return @($current | Where-Object { $_.Status -ne 1 -or ([version]$_.Version).Build -lt $TargetBuild }).Count -eq 0
    }
    $sites = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site')
    foreach ($secondary in @($sites | Where-Object Type -eq 1)) {
        $parent = @($sites | Where-Object SiteCode -eq $secondary.ReportingSiteCode)[0]
        if (([version]$parent.Version).Build -ge 9141) {
            $secondaryDefinition = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SiteDefinition' "SiteCode='$($secondary.SiteCode)'")[0]
            $sqlParts = [string]$secondaryDefinition.SQLDatabaseName -split '\\'
            if ($sqlParts.Count -eq 2) {
                Upgrade-SccmSecondarySql $secondary.ServerName $parent.ServerName $parent.InstallDir $WorkDirectory $secondary.SiteCode $sqlParts[0]
            } else {
                Write-SccmLog 'The secondary uses a full default SQL instance; its version is checked by SCCM setup.'
            }
        } else {
            Write-SccmLog 'Historical parent media does not supply SQL 2022 Express; SQL support will be checked by setup.'
        }
    }
    Complete-SccmSecondaryUpdates $Provider $SiteCode $TimeoutMinutes
    $roles = @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SysResUse' | Where-Object RoleName -eq 'SMS Site Server')
    foreach ($role in $roles) {
        $site = @($sites | Where-Object SiteCode -eq $role.SiteCode)[0]
        $server = ([string]$role.NetworkOSPath).Trim('\')
        if ($server -ine $site.ServerName -and ($server -split '\.')[0] -ine ($site.ServerName -split '\.')[0]) {
            $passiveProvider = Get-SccmSiteProvider $Provider $SiteCode $site.SiteCode
            Wait-SccmPassiveReady $passiveProvider $site.SiteCode $server $TimeoutMinutes
        }
        # The active site is verified by its site state, not passive HA stages.
    }
    Wait-SccmCondition -Description 'replication returns to ready after the release update' -TimeoutMinutes $TimeoutMinutes -RetryReadErrors -Test {
        $links = @(Get-SccmProviderData $Provider $SiteCode 'SMS_ReplicationLinkStatus')
        return @($links | Where-Object { $_.InitializationStatus -ne 6 -or $_.FailedSyncs -gt 0 -or $_.DegradedSyncs -gt 0 }).Count -eq 0
    }
    return @{Changed = $hasChanged; Release = $TargetRelease; Build = $TargetBuild}
} catch {
    Write-SccmLog "Release servicing failed: $($_.Exception.Message)" 'ERROR'
    throw
} finally {
    Set-Location $env:SystemDrive\
}
