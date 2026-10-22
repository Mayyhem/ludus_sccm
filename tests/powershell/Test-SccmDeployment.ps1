# Offline behavior checks. No SCCM server, network access, or installer is used.
# Run from the repository: powershell.exe -NoProfile -File tests/powershell/Test-SccmDeployment.ps1
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '../../roles/sccm_common/files/SccmDeployment.psm1'
$module = Import-Module $modulePath -Force -PassThru
$script:checks = 0
function Assert-Result {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAILED: $Description" }
    $script:checks++
    Write-Host "PASS: $Description"
}

Assert-Result ((ConvertTo-SccmAdminShare 'server.example.test' 'D:\Program Files\ConfigMgr') -eq '\\server.example.test\D$\Program Files\ConfigMgr') 'Windows paths become the correct administrative share'
$rejected = $false
try { ConvertTo-SccmAdminShare 'server' '..\relative' } catch { $rejected = $true }
Assert-Result $rejected 'Relative installer paths are refused'

$stages = @(11..14 | ForEach-Object { [pscustomobject]@{StageId = $_; StageCompleted = 2} })
$stages += [pscustomobject]@{StageId = 15; StageCompleted = 0}
Assert-Result (Test-SccmPassiveReady $stages '5.00.9146.1000' '5.00.9146.1000') 'A passive server is ready without promotion'
$stages[3].StageCompleted = 1
Assert-Result (-not (Test-SccmPassiveReady $stages '5.00.9146.1000' '5.00.9146.1000')) 'Post-installation in progress is not success'
$stages[3].StageCompleted = 2
Assert-Result (-not (Test-SccmPassiveReady $stages '5.00.9141.1000' '5.00.9146.1000')) 'Completed stages cannot hide an old passive-server version'

Assert-Result (Test-SccmUpdateFailure 196607) 'Prerequisite errors count as failures'
Assert-Result (Test-SccmUpdateFailure 262143) 'Installation errors count as failures'
Assert-Result (Test-SccmUpdateInstalling 196610) 'Installation in progress can be resumed'
Assert-Result (-not (Test-SccmUpdateInstalling 196612)) 'Installed is distinct from in progress'

function New-Hotfix {
    param([string]$Name, [string]$Version, [int]$State = 262146, [string]$Superseded = '')
    [pscustomobject]@{Name = $Name; FullVersion = $Version; State = $State; UpdateType = 2; MinCMVersion = '5.00.9146.1000'; MaxCMVersion = '5.00.9146.9999'; SupersededByNameList = $Superseded; DateReleased = [datetime]'2026-10-01'}
}
$old = New-Hotfix 'Old fix' '5.00.9146.1001' 262146 'New fix'
$new = New-Hotfix 'New fix' '5.00.9146.1002'
Assert-Result ((Select-SccmHotfix @($old, $new) '5.00.9146.1000').Name -eq 'New fix') 'An available superseding fix is selected'
Assert-Result ((Select-SccmHotfix @($old) '5.00.9146.1000').Name -eq 'Old fix') 'An unavailable replacement does not hide the only applicable fix'
$new.State = 196612
Assert-Result ($null -eq (Select-SccmHotfix @($new) '5.00.9146.1002')) 'An installed fix is not installed again'
$new.State = 262146
$new.FullVersion = '5.00.9141.1002'
Assert-Result ($null -eq (Select-SccmHotfix @($new) '5.00.9146.1000')) 'Fixes from another release are excluded'

$resource = [pscustomobject]@{Name = 'PS1-DEV'; FullDomainName = 'mayyhem.com'; ResourceNames = @('ps1-dev.mayyhem.com')}
Assert-Result ((Get-SccmResourceComputerName $resource) -eq 'ps1-dev.mayyhem.com') 'A discovered computer name is used instead of its domain'
$resource.ResourceNames = @()
Assert-Result ((Get-SccmResourceComputerName $resource) -eq 'PS1-DEV.mayyhem.com') 'A missing DNS resource name is formed from computer and domain'
$location = Get-SccmDatabaseLocation ([pscustomobject]@{SQLServerName = 'secondary'; SQLDatabaseName = 'CONFIGMGRSEC\CM_SEC'})
Assert-Result ($location.Server -eq 'secondary\CONFIGMGRSEC' -and $location.Database -eq 'CM_SEC') 'Secondary SQL instance and database are separated correctly'

$fatalReachedCaller = $false
try {
    Wait-SccmCondition -Description 'deliberate fatal failure' -RetryReadErrors -TimeoutMinutes 0 -PollSeconds 0 -Test { Stop-SccmWork 'Stop immediately' }
} catch { $fatalReachedCaller = $_.Exception.Message -eq 'Stop immediately' }
Assert-Result $fatalReachedCaller 'Fatal update failures are never retried as transient read errors'
$timedOut = $false
try { Wait-SccmCondition -Description 'never ready' -TimeoutMinutes 0 -PollSeconds 0 -Test { $false } } catch { $timedOut = $_.Exception.Message -like 'Timed out:*' }
Assert-Result $timedOut 'An unfinished operation has a bounded wait'

# Replace all external operations inside the module with local fixtures. These
# scenarios exercise the real update controller, including its stop conditions.
foreach ($scenario in @('success', 'warnings', 'errors', 'resume')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:fixtureState = 327682
        $script:installCalls = 0
        $script:downloadCalls = 0
        $script:prereqCalls = 0
        $script:fixtureScenario = $scenario
        function Get-SccmUpdateByGuid { return [pscustomobject]@{State = $script:fixtureState} }
        function Invoke-CMSiteUpdateDownload { param($Name, [switch]$Force, $ErrorAction) $script:downloadCalls++; $script:fixtureState = 262146 }
        function Invoke-CMSiteUpdatePrerequisiteCheck {
            param($Name, $ErrorAction)
            $script:prereqCalls++
            $script:fixtureState = switch ($script:fixtureScenario) { 'warnings' {131075} 'errors' {196607} default {131074} }
        }
        function Set-SccmWarningPolicy { }
        function Install-CMSiteUpdate { param($Name, [switch]$Force, $ErrorAction) $script:installCalls++; $script:fixtureState = 196612 }
        function Get-SccmProviderData {
            param($Provider, $SiteCode, $ClassName, $Filter)
            if ($ClassName -eq 'SMS_Site') { return [pscustomobject]@{SiteCode = 'CAS'; Type = 4} }
            return [pscustomobject]@{SiteCode = 'CAS'; State = 196612}
        }
        $initialState = 327682
        if ($scenario -eq 'resume') { $initialState = 196610; $script:fixtureState = 196612 }
        $package = [pscustomobject]@{PackageGuid = 'offline-fixture'; Name = 'Fixture update'; State = $initialState}
        $failure = $null
        try { Install-SccmUpdatePackage 'unused' 'CAS' $package $false 0 } catch { $failure = $_.Exception.Message }
        return @{Failure = $failure; Installs = $script:installCalls; Downloads = $script:downloadCalls; Prerequisites = $script:prereqCalls}
    } $scenario
    switch ($scenario) {
        'success' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Installs -eq 1 -and $outcome.Downloads -eq 1 -and $outcome.Prerequisites -eq 1) 'A new update downloads, checks prerequisites, and installs once' }
        'warnings' { Assert-Result ($outcome.Failure -like '*prerequisite warnings*' -and $outcome.Installs -eq 0) 'Prerequisite warnings block installation by default' }
        'errors' { Assert-Result ($outcome.Failure -like '*prerequisite check failed*' -and $outcome.Installs -eq 0) 'Prerequisite errors stop before installation' }
        'resume' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Installs -eq 0 -and $outcome.Downloads -eq 0 -and $outcome.Prerequisites -eq 0) 'An active update is observed without duplicate setup requests' }
    }
}
Write-Host "Passed $script:checks offline PowerShell behavior checks."
