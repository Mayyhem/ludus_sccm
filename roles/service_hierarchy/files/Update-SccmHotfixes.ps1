[CmdletBinding()]
param(
    [string]$WorkDirectory, [string]$Provider, [string]$SiteCode,
    [bool]$AllowWarnings = $false, [int]$TimeoutMinutes = 180,
    [int]$CatalogSettleSeconds = 120
)
$ErrorActionPreference = 'Stop'
Import-Module "$WorkDirectory\SccmDeployment.psm1" -Force
Set-SccmLog "$WorkDirectory\hierarchy-update.log"
try {
    Connect-SccmSite $SiteCode $Provider
    $applied = @()
    $quietScans = 0
    for ($round = 0; $round -lt 50; $round++) {
        Invoke-CMSiteUpdateCheck -ErrorAction Stop | Out-Null
        Write-SccmLog 'Waiting for normal catalog synchronization and applicability checks.'
        Start-Sleep -Seconds $CatalogSettleSeconds
        $site = @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' "SiteCode='$SiteCode'")[0]
        $packages = @(Get-SccmProviderData $Provider $SiteCode 'SMS_CM_UpdatePackages')
        # CAS can report Installed before child primaries finish. Rejoin the
        # newest installed fix's hierarchy wait rather than declaring success.
        $installedCurrent = @($packages | Where-Object { $_.UpdateType -eq 2 -and $_.State -eq 196612 -and [version]$_.FullVersion -eq [version]$site.Version })
        foreach ($installed in $installedCurrent) {
            Install-SccmUpdatePackage $Provider $SiteCode $installed $AllowWarnings $TimeoutMinutes
            Complete-SccmSecondaryUpdates $Provider $SiteCode $TimeoutMinutes
        }
        $unfinished = @($packages | Where-Object { $_.UpdateType -eq 2 -and (Test-SccmUpdateInstalling $_.State) })
        foreach ($running in $unfinished) {
            Write-SccmLog "Finishing already running hotfix $($running.Name) before selecting another."
            Install-SccmUpdatePackage $Provider $SiteCode $running $AllowWarnings $TimeoutMinutes
            $applied += [string]$running.PackageGuid
            Complete-SccmSecondaryUpdates $Provider $SiteCode $TimeoutMinutes
        }
        if ($unfinished.Count) { $quietScans = 0; continue }
        $package = Select-SccmHotfix $packages $site.Version
        if ($null -eq $package) {
            $quietScans++
            Write-SccmLog "No applicable unsuperseded registered hotfix remains (quiet scan $quietScans of 2)."
            if ($quietScans -ge 2) { return @{Changed = ($applied.Count -gt 0); AppliedHotfixes = $applied} }
            continue
        }
        $quietScans = 0
        if ($package.PackageGuid -in $applied) { Stop-SccmWork 'A completed hotfix is still offered as pending. Review the catalog rather than repeating it.' }
        # Preserve verified database recovery material before each new fix.
        if (-not (Test-SccmUpdateInstalling $package.State)) {
            Assert-SccmUpdateReadiness @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site')
            $backups = @()
            foreach ($definition in @(Get-SccmProviderData $Provider $SiteCode 'SMS_SCI_SiteDefinition')) {
                $database = Get-SccmDatabaseLocation $definition
                $backups += Backup-SccmDatabase $database.Server $database.Database
            }
            ConvertTo-Json -InputObject $backups -Depth 4 | Set-Content "$WorkDirectory\hotfix-database-backups.json" -Encoding UTF8
            foreach ($currentSite in @(Get-SccmProviderData $Provider $SiteCode 'SMS_Site' | Where-Object Type -in @(2, 4))) {
                $source = ConvertTo-SccmAdminShare $currentSite.ServerName "$($currentSite.InstallDir)\cd.latest"
                $destination = "$WorkDirectory\recovery\$($currentSite.SiteCode)\$($currentSite.Version)"
                [void][IO.Directory]::CreateDirectory($destination)
                Copy-Item "$source\*" $destination -Recurse -Force -ErrorAction Stop
                Write-SccmLog "Saved recovery media before $($package.Name)."
            }
        }
        Install-SccmUpdatePackage $Provider $SiteCode $package $AllowWarnings $TimeoutMinutes
        $applied += [string]$package.PackageGuid
        Complete-SccmSecondaryUpdates $Provider $SiteCode $TimeoutMinutes
        Assert-SccmReplication $Provider $SiteCode
    }
    Stop-SccmWork 'Hotfix discovery exceeded 50 rounds. Review supersedence and applicability before continuing.'
} catch {
    Write-SccmLog "Hotfix servicing failed: $($_.Exception.Message)" 'ERROR'
    throw
} finally { Set-Location $env:SystemDrive\ }
