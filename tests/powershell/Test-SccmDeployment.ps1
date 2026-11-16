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

foreach ($scenario in @('requested', 'busy', 'failure')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:catalogScenario = $scenario
        $script:catalogCalls = 0
        function Invoke-CMSiteUpdateCheck {
            param($ErrorAction)
            $script:catalogCalls++
            if ($script:catalogScenario -eq 'busy') { throw 'Error occurred while checking for updates: Still checking for updates. This can take a few minutes.' }
            if ($script:catalogScenario -eq 'failure') { throw 'The catalog service is unavailable.' }
        }
        $requested = $null; $failure = $null
        try { $requested = Request-SccmCatalogCheck } catch { $failure = $_.Exception.Message }
        return @{Requested = $requested; Failure = $failure; Calls = $script:catalogCalls}
    } $scenario
    switch ($scenario) {
        'requested' { Assert-Result ($outcome.Requested -eq $true -and $null -eq $outcome.Failure -and $outcome.Calls -eq 1) 'An idle catalog gets exactly one normal synchronization request' }
        'busy' { Assert-Result ($outcome.Requested -eq $false -and $null -eq $outcome.Failure -and $outcome.Calls -eq 1) 'An already running catalog check is observed without duplicate requests' }
        'failure' { Assert-Result ($outcome.Failure -eq 'The catalog service is unavailable.' -and $outcome.Calls -eq 1) 'Other catalog errors remain fatal rather than being treated as busy' }
    }
}

foreach ($scenario in @('missing-x86', 'older-x86', 'current', 'not-registered')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:runtimeScenario = $scenario
        $script:runtimeVersions = @{x64 = [version]'14.50.40000.0'; x86 = $null}
        if ($scenario -eq 'current') { $script:runtimeVersions.x86 = [version]'14.44.35211.0' }
        if ($scenario -eq 'older-x86') { $script:runtimeVersions.x86 = [version]'14.30.30000.0' }
        $script:installerCalls = @()
        function Get-ItemProperty { param($Path, $ErrorAction) return [pscustomobject]@{Release = 528040} }
        function Get-Item { param($LiteralPath) return [pscustomobject]@{VersionInfo = [pscustomobject]@{FileVersion = '14.44.35211.0'}} }
        function Get-SccmVisualCppRuntimeVersion { param($Architecture) return $script:runtimeVersions[$Architecture] }
        function Get-SccmInstalledApplications { return [pscustomobject]@{DisplayName = 'Microsoft ODBC Driver 18 for SQL Server'; DisplayVersion = '18.6.2.1'} }
        function Invoke-SccmInstaller {
            param($Path, $Arguments, $AcceptedExitCodes)
            $script:installerCalls += $Path
            if ($script:runtimeScenario -ne 'not-registered') { $script:runtimeVersions.x86 = [version]'14.44.35211.0' }
            return $true
        }
        $result = $null; $failure = $null
        try { $result = Install-SccmPrerequisites 'C:\fixture' } catch { $failure = $_.Exception.Message }
        return @{Result = $result; Failure = $failure; Calls = $script:installerCalls}
    } $scenario
    switch ($scenario) {
        'missing-x86' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Calls.Count -eq 1 -and $outcome.Calls[0] -eq 'C:\fixture\vc-2022-x86.exe' -and $outcome.Result.Changed -and $outcome.Result.RebootRequired) 'Missing x86 runtime is installed even with current ODBC, and its restart is retained' }
        'older-x86' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Calls.Count -eq 1 -and $outcome.Calls[0] -eq 'C:\fixture\vc-2022-x86.exe') 'An older x86 runtime is upgraded without reinstalling ODBC or downgrading newer x64' }
        'current' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Calls.Count -eq 0 -and -not $outcome.Result.Changed) 'Current runtimes and ODBC are reused unchanged' }
        'not-registered' { Assert-Result ($outcome.Failure -like '*did not register*' -and $outcome.Calls.Count -eq 1) 'An installer return alone cannot hide a missing runtime' }
    }
}
$module = Import-Module $modulePath -Force -PassThru

Assert-Result ((ConvertTo-SccmAdminShare 'server.example.test' 'D:\Program Files\ConfigMgr') -eq '\\server.example.test\D$\Program Files\ConfigMgr') 'Windows paths become the correct administrative share'
$rejected = $false
try { ConvertTo-SccmAdminShare 'server' '..\relative' } catch { $rejected = $true }
Assert-Result $rejected 'Relative installer paths are refused'

$sfx = [pscustomobject]@{ProductName = '7-Zip'; FileDescription = '7z SFX'}
Assert-Result ((Get-SccmMediaExtractionArguments $sfx 'C:\media cache\2509') -eq '-y -o"C:\media cache\2509\cd.retail.LN"') '7-Zip media extracts silently into the shared media layout, preserving spaces'
$legacy = [pscustomobject]@{ProductName = 'Microsoft extractor'; FileDescription = 'Self-extracting archive'}
Assert-Result ((Get-SccmMediaExtractionArguments $legacy 'C:\media cache\2403') -eq '/s -d"C:\media cache\2403"') 'Older media retains its existing extraction switches'

foreach ($scenario in @('completed', 'timeout', 'bad-exit')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:fixtureScenario = $scenario
        $script:stopped = @()
        $script:waitMilliseconds = 0
        function Assert-SccmMicrosoftSignature { param($Path) }
        function Start-Process {
            param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, [switch]$Wait)
            if ($Wait) { throw 'A bounded installer must use the timed process wait.' }
            $process = [pscustomobject]@{Id = 12345; ExitCode = $(if ($script:fixtureScenario -eq 'bad-exit') {7} else {0})}
            $process | Add-Member ScriptMethod WaitForExit { param($milliseconds) $script:waitMilliseconds = $milliseconds; return ($script:fixtureScenario -ne 'timeout') }
            $process | Add-Member ScriptMethod Refresh { }
            return $process
        }
        function Stop-Process { param($Id, [switch]$Force, $ErrorAction) $script:stopped += $Id }
        $failure = $null
        try { [void](Invoke-SccmInstaller -Path 'C:\fixture.exe' -Arguments '-y' -AcceptedExitCodes @(0) -TimeoutMinutes 30) } catch { $failure = $_.Exception.Message }
        return @{Failure = $failure; Stopped = $script:stopped; Wait = $script:waitMilliseconds}
    } $scenario
    switch ($scenario) {
        'completed' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Stopped.Count -eq 0 -and $outcome.Wait -eq 1800000) 'A bounded installer accepts successful completion without killing a process' }
        'timeout' { Assert-Result ($outcome.Failure -like '*timed out after 30 minutes*' -and $outcome.Stopped.Count -eq 1 -and $outcome.Stopped[0] -eq 12345) 'A stalled installer is stopped by its own process ID and fails clearly' }
        'bad-exit' { Assert-Result ($outcome.Failure -like '*exit code 7*' -and $outcome.Stopped.Count -eq 0) 'A bounded installer still rejects an unsuccessful exit code' }
    }
}
$module = Import-Module $modulePath -Force -PassThru

# Load only the policy helper definition; the Ansible entry point and AD queries
# are never executed by these offline checks.
$policyPath = Join-Path $PSScriptRoot '../../plugins/modules/force_gpupdate.ps1'
$tokens = $null; $parseErrors = $null
$policyAst = [System.Management.Automation.Language.Parser]::ParseFile($policyPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'The policy module does not parse.' }
$policyFunction = $policyAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ComputerPolicyRefresh' }, $true)
$policyOutcome = & {
    param($definition)
    . ([scriptblock]::Create($definition))
    $script:policyRemotes = @(); $script:policyExit = 0
    function Invoke-Command {
        param($ComputerName, $ScriptBlock, $ErrorAction)
        $script:policyRemotes += $ComputerName
        return [pscustomobject]@{Computer = $ComputerName; ExitCode = $script:policyExit; Output = 'fixture output'}
    }
    $local = Invoke-ComputerPolicyRefresh "$env:COMPUTERNAME.example.test" -Command { [pscustomobject]@{Computer = 'local-fixture'; ExitCode = 0; Output = 'local policy applied'} }
    $localRemoteCalls = $script:policyRemotes.Count
    $remote = Invoke-ComputerPolicyRefresh 'remote-fixture.example.test'
    $script:policyExit = 5
    $failure = $null
    try { Invoke-ComputerPolicyRefresh 'failed-fixture.example.test' } catch { $failure = $_.Exception.Message }
    return @{Local = $local; LocalRemoteCalls = $localRemoteCalls; Remote = $remote; Calls = $script:policyRemotes; Failure = $failure}
} $policyFunction.Extent.Text
Assert-Result ($policyOutcome.Local.Computer -eq 'local-fixture' -and $policyOutcome.LocalRemoteCalls -eq 0) 'Local computer policy refresh avoids remote scheduled tasks and remoting to itself'
Assert-Result ($policyOutcome.Remote.ExitCode -eq 0 -and $policyOutcome.Calls[0] -eq 'remote-fixture.example.test') 'Remote computer policy refresh uses the requested WinRM host'
Assert-Result ($policyOutcome.Failure -like '*failed-fixture.example.test*exit code 5*') 'A failed policy refresh reports its computer and exit code'

$stages = @(11..14 | ForEach-Object { [pscustomobject]@{StageId = $_; StageCompleted = 2} })
$stages += [pscustomobject]@{StageId = 15; StageCompleted = 0}
Assert-Result (Test-SccmPassiveReady $stages '5.00.9146.1000' '5.00.9146.1000') 'A passive server is ready without promotion'
$stages[3].StageCompleted = 1
Assert-Result (-not (Test-SccmPassiveReady $stages '5.00.9146.1000' '5.00.9146.1000')) 'Post-installation in progress is not success'
$stages[3].StageCompleted = 2
Assert-Result (-not (Test-SccmPassiveReady $stages '5.00.9141.1000' '5.00.9146.1000')) 'Completed stages cannot hide an old passive-server version'

$module = Import-Module $modulePath -Force -PassThru
$passiveFailure = & $module {
    function Get-SccmProviderData {
        param($Provider, $SiteCode, $ClassName, $Filter)
        if ($ClassName -eq 'SMS_HA_SiteServerTopLevelMonitoring') {
            return [pscustomobject]@{StageId = 14; StageCompleted = 3}
        }
        if ($ClassName -eq 'SMS_HA_SiteServerDetailedMonitoring') {
            return [pscustomobject]@{StageId = 14; Applicable = 1; IsComplete = 3; SubStageName = 'Validating access to remote site systems'}
        }
        throw 'A failed HA stage must stop before subsequent readiness reads'
    }
    try { Wait-SccmPassiveReady 'provider-fixture' 'PS1' 'passive-fixture' 0 } catch {
        return @{Message = $_.Exception.Message; Fatal = ($_.Exception.Data['SccmFatal'] -eq $true)}
    }
}
Assert-Result ($passiveFailure.Message -like '*Validating access to remote site systems*failovermgr.log*') 'A failed passive stage identifies its failed substep and diagnostic log'
Assert-Result $passiveFailure.Fatal 'A reported passive installation failure stops immediately instead of becoming a timeout'

foreach ($scenario in @('recovered', 'persistent', 'remote-failure', 'install-failure', 'missing-id', 'old-version', 'overall-timeout')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:passiveScenario = $scenario
        $script:passivePolls = 0
        $script:passiveHostReads = 0
        $script:passiveObservations = @()
        function Get-SccmProviderData {
            param($Provider, $SiteCode, $ClassName, $Filter)
            if ($ClassName -eq 'SMS_HA_SiteServerTopLevelMonitoring') {
                $script:passivePolls++
                $rows = @(11..14 | ForEach-Object { [pscustomobject]@{StageId = $_; StageCompleted = 2} })
                if ($script:passivePolls -eq 1 -or $script:passiveScenario -eq 'persistent') { $rows[3].StageCompleted = 3 }
                if ($script:passiveScenario -eq 'install-failure') { $rows[2].StageCompleted = 3 }
                return $rows
            }
            if ($ClassName -eq 'SMS_HA_SiteServerDetailedMonitoring') {
                $row = [pscustomobject]@{StageId = 14; Applicable = 1; IsComplete = 3; SubStageid = 0xe000c; SubStageName = 'Validating the site server'}
                if ($script:passiveScenario -eq 'missing-id') { $row.PSObject.Properties.Remove('SubStageid') }
                if ($script:passiveScenario -eq 'remote-failure') {
                    return @($row, [pscustomobject]@{StageId = 14; Applicable = 1; IsComplete = 3; SubStageid = 0xe000d; SubStageName = 'Validating access to remote site systems'})
                }
                if ($script:passiveScenario -eq 'install-failure') {
                    return @($row, [pscustomobject]@{StageId = 13; Applicable = 1; IsComplete = 3; SubStageid = 0xd0001; SubStageName = 'Installing passive files'})
                }
                return $row
            }
            if ($ClassName -eq 'SMS_Site') { return [pscustomobject]@{Version = '5.00.9146.1000'} }
            throw "Unexpected fixture provider read: $ClassName"
        }
        function Get-SccmHostSiteState {
            param($ComputerName)
            $script:passiveHostReads++
            $version = if ($script:passiveScenario -eq 'old-version') { '5.00.9141.1000' } else { '5.00.9146.1000' }
            return [pscustomobject]@{Version = $version; ServiceStatus = 'Running'}
        }
        if ($scenario -ne 'overall-timeout') {
            function Wait-SccmCondition {
                param($Test, $Description, $TimeoutMinutes, [switch]$RetryReadErrors)
                foreach ($poll in 1..2) {
                    $ready = [bool](& $Test)
                    $script:passiveObservations += $ready
                    if ($ready) { return }
                    if ($script:passiveScenario -eq 'persistent') { Start-Sleep -Milliseconds 1100 }
                }
                Stop-SccmWork 'Fixture reached incomplete native readiness.'
            }
        }
        $complete = $false; $failure = $null; $fatal = $false
        $timeout = if ($scenario -eq 'overall-timeout') { 0 } else { 180 }
        $grace = if ($scenario -eq 'persistent') { 1 } else { 300 }
        try { Wait-SccmPassiveReady 'provider-fixture' 'PS1' 'passive-fixture' $timeout $grace; $complete = $true }
        catch { $failure = $_.Exception.Message; $fatal = $_.Exception.Data['SccmFatal'] -eq $true }
        return @{Complete = $complete; Failure = $failure; Fatal = $fatal; Observations = @($script:passiveObservations); HostReads = $script:passiveHostReads; Polls = $script:passivePolls}
    } $scenario
    switch ($scenario) {
        'recovered' {
            Assert-Result ($outcome.Complete -and $outcome.Observations.Count -eq 2 -and -not $outcome.Observations[0] -and $outcome.Observations[1]) 'A transient native site-key validation failure waits for the next completed HA observation'
            Assert-Result ($outcome.HostReads -eq 1) 'Failed site validation never becomes readiness from an installed version alone'
        }
        'persistent' { Assert-Result (-not $outcome.Complete -and $outcome.Fatal -and $outcome.Failure -like '*native site validation remained failed*failovermgr.log*' -and $outcome.Polls -eq 2) 'Persistent native site validation failure stops after its bounded grace period' }
        'remote-failure' { Assert-Result ($outcome.Fatal -and $outcome.Polls -eq 1 -and $outcome.Failure -like '*Validating access to remote site systems*') 'A concurrent remote-access failure is not classified as transient site-key validation' }
        'install-failure' { Assert-Result ($outcome.Fatal -and $outcome.Polls -eq 1 -and $outcome.Failure -like '*Installing passive files*') 'Failed passive installation still stops immediately before validation grace' }
        'missing-id' { Assert-Result ($outcome.Fatal -and $outcome.Polls -eq 1 -and $outcome.HostReads -eq 0) 'An unknown validation identifier cannot enable the native retry grace' }
        'old-version' { Assert-Result (-not $outcome.Complete -and $outcome.Observations.Count -eq 2 -and -not $outcome.Observations[0] -and -not $outcome.Observations[1]) 'Recovered native validation still requires the expected installed passive version' }
        'overall-timeout' { Assert-Result (-not $outcome.Complete -and $outcome.Fatal -and $outcome.Failure -like '*Timed out: passive server*') 'The overall passive readiness timeout also bounds transient validation retries' }
    }
}
Import-Module $modulePath -Force

Assert-Result (Test-SccmUpdateFailure 196607) 'Prerequisite errors count as failures'
Assert-Result (Test-SccmUpdateFailure 262143) 'Installation errors count as failures'
Assert-Result (Test-SccmUpdateInstalling 196610) 'Installation in progress can be resumed'
Assert-Result (-not (Test-SccmUpdateInstalling 196612)) 'Installed is distinct from in progress'
Assert-Result (Test-SccmUpdatePreparationStarted 65537) 'Content replication retains the existing prerequisite request and recovery evidence'
Assert-Result (-not (Test-SccmUpdatePreparationStarted 262146)) 'A downloaded package can still receive its first prerequisite request'

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
foreach ($scenario in @('success', 'warnings', 'reviewed-warnings', 'errors', 'errors-allowed', 'changed-result', 'resume', 'content_resume', 'replicated_resume', 'prereq_resume', 'prereq_ready', 'prereq_warnings')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:fixtureState = 327682
        $script:warningSwitch = $null
        $script:installCalls = 0
        $script:downloadCalls = 0
        $script:prereqCalls = 0
        $script:fixtureScenario = $scenario
        $script:fixtureReads = 0
        function Get-SccmUpdateByGuid {
            $script:fixtureReads++
            if ($script:fixtureScenario -in @('content_resume', 'replicated_resume', 'prereq_resume') -and
                $script:fixtureState -ne 196612 -and $script:fixtureReads -ge 5) {
                $script:fixtureState = 131074
            }
            return [pscustomobject]@{State = $script:fixtureState}
        }
        function Invoke-CMSiteUpdateDownload { param($InputObject, [switch]$Force, $ErrorAction) if($InputObject.PackageGuid -ne 'offline-fixture'){throw 'Wrong update object.'} $script:downloadCalls++; $script:fixtureState = 262146 }
        function Invoke-CMSiteUpdatePrerequisiteCheck {
            param($InputObject, $ErrorAction) if($InputObject.PackageGuid -ne 'offline-fixture'){throw 'Wrong update object.'}
            $script:prereqCalls++
            $script:fixtureState = switch ($script:fixtureScenario) { 'warnings' {131075} 'reviewed-warnings' {131075} 'errors' {196607} 'errors-allowed' {196607} default {131074} }
        }
        function Get-CMSiteUpdate { param([switch]$Fast,$ErrorAction) return @([pscustomobject]@{PackageGuid='early-fixture';Name='Fixture update'},[pscustomobject]@{PackageGuid='offline-fixture';Name='Fixture update';State=$(if($script:fixtureScenario -eq 'changed-result'){196607}else{$script:fixtureState})}) }
        function Install-CMSiteUpdate { param($InputObject, [switch]$Force, [switch]$SkipPrerequisiteCheck, $ErrorAction) $script:warningSwitch=[bool]$SkipPrerequisiteCheck; if($InputObject.PackageGuid -ne 'offline-fixture'){throw 'Wrong update object.'} $script:installCalls++; $script:fixtureState = 196612 }
        function Get-SccmProviderData {
            param($Provider, $SiteCode, $ClassName, $Filter)
            if ($ClassName -eq 'SMS_Site') { return [pscustomobject]@{SiteCode = 'CAS'; Type = 4} }
            return [pscustomobject]@{SiteCode = 'CAS'; State = 196612}
        }
        $initialState = switch ($scenario) {
            'content_resume' {65537}
            'replicated_resume' {65538}
            'prereq_resume' {131073}
            'prereq_ready' {131074}
            'prereq_warnings' {131075}
            default {327682}
        }
        $script:fixtureState = $initialState
        if ($scenario -eq 'resume') { $initialState = 196610; $script:fixtureState = 196612 }
        $package = [pscustomobject]@{PackageGuid = 'offline-fixture'; Name = 'Fixture update'; State = $initialState}
        $failure = $null
        try { Install-SccmUpdatePackage 'unused' 'CAS' $package ($scenario -in @('reviewed-warnings','errors-allowed')) 0 } catch { $failure = $_.Exception.Message }
        return @{Failure = $failure; Installs = $script:installCalls; Downloads = $script:downloadCalls; Prerequisites = $script:prereqCalls; WarningSwitch=$script:warningSwitch}
    } $scenario
    switch ($scenario) {
        'success' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Installs -eq 1 -and $outcome.Downloads -eq 1 -and $outcome.Prerequisites -eq 1 -and $outcome.WarningSwitch -eq $false) 'A new update downloads, checks prerequisites, and installs once' }
        'reviewed-warnings' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Installs -eq 1 -and $outcome.WarningSwitch -eq $true) 'Reviewed completed warnings use the native continue-on-warning installer flag' }
        'errors-allowed' { Assert-Result ($outcome.Failure -like '*prerequisite check failed*' -and $outcome.Installs -eq 0) 'Allowing warnings never starts installation after prerequisite errors' }
        'changed-result' { Assert-Result ($outcome.Failure -like '*result changed before installation*' -and $outcome.Installs -eq 0) 'Changed native prerequisite results block installation at the final guard' }
        'warnings' { Assert-Result ($outcome.Failure -like '*prerequisite warnings*' -and $outcome.Installs -eq 0) 'Prerequisite warnings block installation by default' }
        'errors' { Assert-Result ($outcome.Failure -like '*prerequisite check failed*' -and $outcome.Installs -eq 0) 'Prerequisite errors stop before installation' }
        'resume' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Installs -eq 0 -and $outcome.Downloads -eq 0 -and $outcome.Prerequisites -eq 0) 'An active update is observed without duplicate setup requests' }
        {$_ -in @('content_resume', 'replicated_resume', 'prereq_resume', 'prereq_ready')} {
            Assert-Result ($null -eq $outcome.Failure -and $outcome.Installs -eq 1 -and $outcome.Downloads -eq 0 -and $outcome.Prerequisites -eq 0) "Preparation resumes from $scenario without another download or prerequisite request"
        }
        'prereq_warnings' { Assert-Result ($outcome.Failure -like '*prerequisite warnings*' -and $outcome.Installs -eq 0 -and $outcome.Prerequisites -eq 0) 'Previously completed prerequisite warnings still block installation without being rerun' }
    }
}

foreach ($scenario in @('enable-cas', 'enable-primary', 'already-enabled', 'preview', 'https-only', 'anonymous', 'active-update', 'missing-mode', 'unexpected-change')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:communicationScenario = $scenario
        $script:modes = @{CAS = 0; PS1 = 1248}
        if ($scenario -eq 'already-enabled') { $script:modes.CAS = 1216 }
        if ($scenario -eq 'enable-primary') { $script:modes.CAS = 1216; $script:modes.PS1 = 224 }
        if ($scenario -eq 'https-only') { $script:modes.CAS = 31 }
        $script:siteWrites = @(); $script:connections = @()
        function Get-SccmProviderData {
            param($Provider, $SiteCode, $ClassName, $Filter)
            switch ($ClassName) {
                SMS_Site { return @([pscustomobject]@{SiteCode='CAS';Type=4;Status=1},[pscustomobject]@{SiteCode='PS1';Type=2;Status=1}) }
                SMS_SCI_SysResUse {
                    if ($script:communicationScenario -eq 'anonymous') { return [pscustomobject]@{RoleName='SMS Distribution Point';Props=@([pscustomobject]@{PropertyName='IsAnonymousEnabled';Value=1})} }
                    return @()
                }
                SMS_CM_UpdatePackages {
                    if ($script:communicationScenario -eq 'active-update') { return [pscustomobject]@{State=196610} }
                    return @()
                }
                SMS_SCI_Component {
                    $props = @([pscustomobject]@{PropertyName='IISSSLState';Value=$script:modes[$SiteCode]})
                    if ($script:communicationScenario -eq 'missing-mode') { $props = @() }
                    return [pscustomobject]@{ComponentName='SMS_SITE_COMPONENT_MANAGER';Props=$props}
                }
            }
        }
        function Get-SccmSiteProvider { param($Provider,$RootSiteCode,$TargetSiteCode) return 'fixture-provider' }
        function Connect-SccmSite { param($SiteCode,$Provider) $script:connections += $SiteCode }
        function Set-SccmCasGeneratedCertificates {
            param($SiteCode,$ExpectedState,$Preview)
            if ($Preview) { return $false }
            $script:siteWrites += $SiteCode
            $script:modes[$SiteCode] = $ExpectedState -bor 1024
            if ($script:communicationScenario -eq 'unexpected-change') { $script:modes[$SiteCode] = $script:modes[$SiteCode] -bor 256 }
            return $true
        }
        function Set-CMSite {
            param($SiteCode,[bool]$UseSmsGeneratedCert,$ErrorAction)
            if($SiteCode -eq 'CAS'){throw 'The fixture cmdlet must not be used for CAS.'}
            if (-not $UseSmsGeneratedCert) { throw 'The fixture must never disable certificates.' }
            $script:siteWrites += $SiteCode
            $script:modes[$SiteCode] = $script:modes[$SiteCode] -bor 1216
            if ($script:communicationScenario -eq 'unexpected-change') { $script:modes[$SiteCode] = $script:modes[$SiteCode] -bor 256 }
        }
        $failure=$null; $result=$null
        try { $result=Enable-SccmEnhancedHttp 'fixture-root' CAS ($scenario -eq 'preview') } catch { $failure=$_.Exception.Message }
        return @{Failure=$failure;Result=$result;Writes=$script:siteWrites;Modes=$script:modes;Connections=$script:connections}
    } $scenario
    switch ($scenario) {
        'enable-cas' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Result.Changed -and $outcome.Writes.Count -eq 1 -and $outcome.Writes[0] -eq 'CAS' -and $outcome.Modes.PS1 -eq 1248) 'Enhanced HTTP changes only CAS when PS1 already has its certificate flag' }
        'enable-primary' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Result.Changed -and $outcome.Writes.Count -eq 1 -and $outcome.Writes[0] -eq 'PS1' -and $outcome.Modes.PS1 -eq 1248) 'Primary configuration uses the native cmdlet and retains revocation flags' }
        'already-enabled' { Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Result.Changed -and $outcome.Writes.Count -eq 0) 'Already configured sites remain unchanged' }
        'preview' { Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Result.Changed -and $outcome.Writes.Count -eq 0 -and $outcome.Modes.CAS -eq 0) 'Explicit Enhanced HTTP preview cannot call the mutating cmdlet' }
        'https-only' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Writes.Count -eq 0 -and $outcome.Modes.CAS -eq 31) 'HTTPS-only sites retain their existing communication mode' }
        'anonymous' { Assert-Result ($outcome.Failure -like '*anonymous distribution-point*' -and $outcome.Writes.Count -eq 0) 'Anonymous distribution-point access blocks automatic Enhanced HTTP changes' }
        'active-update' { Assert-Result ($outcome.Failure -like '*running update*' -and $outcome.Writes.Count -eq 0) 'Active installation blocks a new communication-setting change' }
        'missing-mode' { Assert-Result ($outcome.Failure -like '*communication flags*' -and $outcome.Writes.Count -eq 0 -and $outcome.Connections[-1] -eq 'CAS') 'Missing mode flags fail closed and restore the root site drive' }
        'unexpected-change' { Assert-Result ($outcome.Failure -like '*Unexpected communication flag changes*' -and $outcome.Connections[-1] -eq 'CAS') 'Unexpected native flag changes fail verification and restore the root site drive' }
    }
}

foreach ($scenario in @('missing', 'duplicate')) {
    $module=Import-Module $modulePath -Force -PassThru
    $failure=& $module {
        param($scenario)
        $script:selectionScenario=$scenario
        function Get-CMSiteUpdate {
            param([switch]$Fast,$ErrorAction)
            if($script:selectionScenario -eq 'duplicate'){return @([pscustomobject]@{PackageGuid='fixture'},[pscustomobject]@{PackageGuid='fixture'})}
            return [pscustomobject]@{PackageGuid='other-package'}
        }
        try{[void](Get-SccmUpdateCommandObject fixture);return $null}catch{return $_.Exception.Message}
    } $scenario
    Assert-Result ($failure -like '*Cannot uniquely select update*') "Native update action fails closed for $scenario GUID selection"
}

foreach ($scenario in @('preview', 'apply', 'already-enabled', 'race', 'wrong-identity', 'missing-flags')) {
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:casComponent=[pscustomobject]@{SiteCode='CAS';ComponentName='SMS_SITE_COMPONENT_MANAGER';FileType=2;PutCalls=0;EmbeddedProperties=@{IISSSLState=@{Value=[pscustomobject]@{IntegerValue=32}};Untouched=@{Value=[pscustomobject]@{IntegerValue=77}}}}
        $script:casComponent | Add-Member ScriptMethod Get { }
        $script:casComponent | Add-Member ScriptMethod Put { $this.PutCalls++ }
        if($scenario -eq 'already-enabled'){$script:casComponent.EmbeddedProperties.IISSSLState.Value.IntegerValue=1056}
        if($scenario -eq 'wrong-identity'){$script:casComponent.SiteCode='PS1'}
        if($scenario -eq 'missing-flags'){$script:casComponent.EmbeddedProperties.Remove('IISSSLState')}
        function Get-CMSiteComponent { param($SiteCode,$ComponentName,$ErrorAction) return $script:casComponent }
        $expected=32
        if($scenario -eq 'already-enabled'){$expected=1056}
        if($scenario -eq 'race'){$expected=0}
        $failure=$null; $changed=$null
        try{$changed=Set-SccmCasGeneratedCertificates CAS $expected ($scenario -eq 'preview')}catch{$failure=$_.Exception.Message}
        return @{Failure=$failure;Changed=$changed;Component=$script:casComponent}
    } $scenario
    switch($scenario){
        'preview' {Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Changed -and $outcome.Component.PutCalls -eq 0 -and $outcome.Component.EmbeddedProperties.IISSSLState.Value.IntegerValue -eq 32) 'CAS SDK preview leaves all properties and native Put untouched'}
        'apply' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Changed -and $outcome.Component.PutCalls -eq 1 -and $outcome.Component.EmbeddedProperties.IISSSLState.Value.IntegerValue -eq 1056 -and $outcome.Component.EmbeddedProperties.Untouched.Value.IntegerValue -eq 77) 'CAS SDK saves only the certificate bit and preserves other embedded properties'}
        'already-enabled' {Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Changed -and $outcome.Component.PutCalls -eq 0) 'CAS SDK idempotence avoids a repeated save'}
        'race' {Assert-Result ($outcome.Failure -like '*changed since*' -and $outcome.Component.PutCalls -eq 0) 'CAS SDK refuses concurrent mode changes'}
        'wrong-identity' {Assert-Result ($outcome.Failure -like '*Unexpected CAS*' -and $outcome.Component.PutCalls -eq 0) 'CAS SDK refuses an unexpected component identity'}
        'missing-flags' {Assert-Result ($outcome.Failure -like '*flags are missing*' -and $outcome.Component.PutCalls -eq 0) 'CAS SDK refuses missing flag metadata'}
    }
}

foreach ($scenario in @('baseline-native','current-native','absent','ambiguous-msi','missing-native','ambiguous-native','missing-path','missing-binary','other-release','older-native')) {
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:consoleReadScenario=$scenario
        function Get-SccmInstalledApplications {
            if($script:consoleReadScenario -eq 'absent'){return @()}
            $app=[pscustomobject]@{DisplayName='Microsoft Configuration Manager Console';DisplayVersion=$(if($script:consoleReadScenario -eq 'current-native'){'5.2609.1050.1000'}else{'5.2509.1036.1000'})}
            if($script:consoleReadScenario -eq 'ambiguous-msi'){return @($app,$app)}
            return $app
        }
        function Get-ItemProperty {
            param($LiteralPath,$ErrorAction)
            if($script:consoleReadScenario -eq 'missing-native'){return $null}
            if($LiteralPath -notmatch 'WOW6432Node' -and $script:consoleReadScenario -ne 'ambiguous-native'){return $null}
            $version=switch($script:consoleReadScenario){'current-native' {'5.2609.1050.1000'} 'other-release' {'5.2603.1000.1000'} 'older-native' {'5.2509.1036.900'} default {'5.2509.1036.1200'}}
            return [pscustomobject]@{AdminConsoleVersion=$version;'UI Installation Directory'=$(if($script:consoleReadScenario -eq 'missing-path'){$null}else{'D:\Console'})}
        }
        function Test-Path {
            param($LiteralPath,$PathType)
            if($LiteralPath -ne 'D:\Console\bin\Microsoft.ConfigurationManagement.exe' -or $PathType -ne 'Leaf'){throw 'Probe the registered console executable only.'}
            return $script:consoleReadScenario -ne 'missing-binary'
        }
        function Invoke-SccmInstaller {throw 'Reading native console identity must not invoke an installer.'}
        $value=$null;$failure=$null
        try{$value=Get-SccmConsoleVersion}catch{$failure=$_.Exception.Message}
        return @{Value=$value;Failure=$failure}
    } $scenario
    switch($scenario){
        'baseline-native' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Value -is [string] -and $outcome.Value -eq '5.2509.1036.1200') 'Native console product revision 1200 is authoritative over MSI inventory revision 1000'}
        'current-native' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Value -eq '5.2609.1050.1000') 'Matching native and MSI console versions remain unchanged'}
        'absent' {Assert-Result ($null -eq $outcome.Value -and $null -eq $outcome.Failure) 'A guest with no installed console remains outside console completion'}
        'ambiguous-msi' {Assert-Result ($outcome.Failure -like '*More than one*') 'Multiple installed consoles remain ambiguous'}
        'missing-native' {Assert-Result ($outcome.Failure -like '*no unique native AdminConsoleVersion*') 'An MSI record alone cannot substitute for missing native console identity'}
        'ambiguous-native' {Assert-Result ($outcome.Failure -like '*no unique native AdminConsoleVersion*') 'Multiple native console registrations fail closed'}
        'missing-path' {Assert-Result ($outcome.Failure -like '*no unique native AdminConsoleVersion*') 'Native version without its installation directory is incomplete'}
        'missing-binary' {Assert-Result ($outcome.Failure -like '*registered console executable is missing*') 'An orphaned native console registration is not an installed console'}
        'other-release' {Assert-Result ($outcome.Failure -like '*MSI inventory are inconsistent*') 'Native console identity from another release is rejected'}
        'older-native' {Assert-Result ($outcome.Failure -like '*MSI inventory are inconsistent*') 'Native console identity older than its MSI inventory is rejected'}
    }
}

foreach ($scenario in @('current','old','newer','missing','missing-metadata','reboot','not-updated','pending-site-reboot')) {
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:consoleScenario=$scenario
        $script:consoleVersion='5.2509.1000.1000'
        $script:consoleInstalls=0
        if($scenario -eq 'current'){$script:consoleVersion='5.2609.1050.1000'}
        if($scenario -eq 'newer'){$script:consoleVersion='5.2703.1000.1000'}
        if($scenario -eq 'missing'){$script:consoleVersion=$null}
        function Get-SccmProviderData {
            param($Provider,$SiteCode,$ClassName,$Filter)
            switch($ClassName){
                SMS_Identification {if($script:consoleScenario -eq 'missing-metadata'){return @()};return [pscustomobject]@{SMSAvailableConsoleVersion='5.2609.1050.1000'}}
                SMS_Site {return [pscustomobject]@{SiteCode='CAS';ServerName=$env:COMPUTERNAME;InstallDir='C:\fixture';Version='5.00.9152.1000'}}
                SMS_CM_UpdatePackageSiteStatus {return [pscustomobject]@{SiteCode='CAS';PackageGuid='11111111-1111-1111-1111-111111111111';State=$(if($script:consoleScenario -eq 'pending-site-reboot'){196613}else{196612})}}
            }
        }
        function Get-SccmHostSiteState {param($ComputerName) return [pscustomobject]@{Version='5.00.9152.1000';ServiceStatus='Running'}}
        function Get-SccmPendingRestartRequests {return @()}
        function New-SccmRestartRequest {
            param($Computer,$Kind,$Version,$SiteCode,$PackageGuid,[switch]$Persist)
            return @{Computer=$Computer;Kind=$Kind;Version=$Version;SiteCode=$SiteCode;PackageGuid='';BootTimeUtc='fixture-boot'}
        }
        function Invoke-SccmRemote {param($ComputerName,$ScriptBlock);return 'fixture-boot'}
        function Get-SccmConsoleVersion {return $script:consoleVersion}
        function Invoke-SccmInstaller {
            param($Path,$Arguments,$TimeoutMinutes)
            if($TimeoutMinutes -ne 30){throw 'Console installation must be bounded.'}
            if($Path -ne 'C:\fixture\tools\ConsoleSetup\ConsoleSetup.exe'){throw 'Wrong console media source.'}
            if($Arguments -notmatch '"TargetDir=.*AdminConsole"'){throw 'Silent console setup requires its explicit existing target directory.'}
            $script:consoleInstalls++
            if($script:consoleScenario -ne 'not-updated'){$script:consoleVersion='5.2609.1050.1000'}
            return $script:consoleScenario -eq 'reboot'
        }
        $result=$null;$failure=$null
        try{$result=Update-SccmServicingConsole unused CAS 0}catch{$failure=$_.Exception.Message}
        return @{Failure=$failure;Result=$result;Installs=$script:consoleInstalls}
    } $scenario
    switch($scenario){
        'current' {Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Result.Changed -and $outcome.Installs -eq 0) 'A current servicing console is unchanged'}
        'old' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Result.Changed -and $outcome.Installs -eq 1 -and -not $outcome.Result.RebootRequired) 'An older servicing console updates from current local site media before cmdlets load'}
        'newer' {Assert-Result ($outcome.Failure -like '*downgrade*' -and $outcome.Installs -eq 0) 'A newer console is never downgraded'}
        'missing' {Assert-Result ($outcome.Failure -like '*no installed servicing console*' -and $outcome.Installs -eq 0) 'Missing baseline console stops before installer selection'}
        'missing-metadata' {Assert-Result ($outcome.Failure -like '*Cannot establish*' -and $outcome.Installs -eq 0) 'Missing provider console metadata fails closed'}
        'reboot' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Result.RebootRequired -and $outcome.Installs -eq 1) 'Console installer restart requests are returned to Ansible before loading cmdlets'}
        'not-updated' {Assert-Result ($outcome.Failure -like '*did not reach*' -and $outcome.Installs -eq 1) 'Successful installer exit cannot substitute for the expected installed console version'}
        'pending-site-reboot' {Assert-Result ($outcome.Failure -like '*site needs a restart*' -and $outcome.Installs -eq 0) 'A pending site restart blocks console replacement'}
    }
}

foreach($scenario in @('preview','apply','wrong-server','setup-active','replication-pending','backup-fails','request-pending','changed-during-backup','already-local')){
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:recoveryScenario=$scenario
        $script:recoverySaves=0;$script:recoveryBackups=0
        $script:recoveryProperties=@{
            'Requested Status'=@{Value=[pscustomobject]@{IntegerValue=0};Value1=[pscustomobject]@{StringValue=$(if($scenario -eq 'request-pending'){'2'}else{'1'})};Value2=[pscustomobject]@{StringValue='105'}}
            'PreReq Check'=@{Value=[pscustomobject]@{IntegerValue=0};Value1=[pscustomobject]@{StringValue='old'};Value2=[pscustomobject]@{StringValue='old'}}
        }
        $script:recoveryDefinition=@{EmbeddedProperties=$script:recoveryProperties}
        $script:recoveryDefinition | Add-Member ScriptMethod Put {$script:recoverySaves++}
        $script:recoveryDefinition | Add-Member ScriptMethod Get {
            if($script:recoveryScenario -eq 'changed-during-backup'){$script:recoveryProperties['Requested Status'].Value1.StringValue='2'}
        }
        function New-SccmManagementConnection {
            $c=[pscustomobject]@{}
            $c | Add-Member ScriptMethod GetInstance {param($Path) return $script:recoveryDefinition}
            $c | Add-Member ScriptMethod Dispose {}
            return $c
        }
        function Get-SccmProviderData {
            param($Provider,$SiteCode,$ClassName,$Filter)
            switch($ClassName){
                SMS_Site {
                    return @(
                        [pscustomobject]@{SiteCode='PS1';Type=2;Status=1;Version='5.00.9152.1000'},
                        [pscustomobject]@{SiteCode='SEC';Type=1;Status=1;Version='5.00.9152.1000';ReportingSiteCode='PS1';ServerName=$(if($script:recoveryScenario -eq 'wrong-server'){'unexpected.mayyhem.com'}else{'ps1-sec.mayyhem.com'});SecondarySiteCMUpdateStatus=0})
                }
                SMS_CM_UpdatePackageSiteStatus {return @()}
                SMS_ReplicationLinkStatus {return [pscustomobject]@{ChildSite='SEC';ParentSite='PS1';InitializationStatus=$(if($script:recoveryScenario -eq 'replication-pending'){3}else{6});FailedSyncs=0;DegradedSyncs=0}}
                SMS_SCI_SiteDefinition {return [pscustomobject]@{SQLServerName='ps1-sec.mayyhem.com';SQLDatabaseName='CONFIGMGRSEC\CM_SEC'}}
            }
        }
        function Get-SccmHostSiteState {return [pscustomobject]@{Version='5.00.9152.1000';ServiceStatus='Running'}}
        function Get-SccmSecondaryMissingUpdatePackages {
            if($script:recoveryScenario -eq 'already-local'){return @()}
            return @('fixture-missing-package')
        }
        function Invoke-SccmRemote {return $script:recoveryScenario -eq 'setup-active'}
        function Backup-SccmDatabase {
            param($Server,$Database)
            $script:recoveryBackups++
            if($script:recoveryScenario -eq 'backup-fails'){throw 'Fixture backup verification failed.'}
            return @{Server=$Server;Database=$Database;BackupPath='C:\fixture\verified.bak'}
        }
        $failure=$null;$result=$null
        try {
            if($scenario -eq 'preview'){$result=Request-SccmSecondaryUpdateRecovery unused PS1 SEC ps1-sec.mayyhem.com 5.00.9152.1000}
            else{$result=Request-SccmSecondaryUpdateRecovery unused PS1 SEC ps1-sec.mayyhem.com 5.00.9152.1000 $false}
        }catch{$failure=$_.Exception.Message}
        return @{Result=$result;Failure=$failure;Saves=$script:recoverySaves;Backups=$script:recoveryBackups;Properties=$script:recoveryProperties}
    } $scenario
    switch($scenario){
        'preview' {Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Result.Submitted -and $outcome.Saves -eq 0 -and $outcome.Backups -eq 0 -and $outcome.Properties['Requested Status'].Value1.StringValue -eq '1') 'Secondary recovery preview performs no backup or native write and preserves the active request'}
        'apply' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Result.Submitted -and $outcome.Saves -eq 1 -and $outcome.Backups -eq 1 -and $outcome.Properties['Requested Status'].Value1.StringValue -eq '2' -and $outcome.Properties['Requested Status'].Value2.StringValue -eq '1011' -and $outcome.Properties['PreReq Check'].Value.IntegerValue -eq 1) 'Same-build secondary recovery saves one native prerequisite-enabled request only after a verified backup'}
        'wrong-server' {Assert-Result ($outcome.Failure -like '*identity*' -and $outcome.Saves -eq 0 -and $outcome.Backups -eq 0) 'Secondary recovery rejects a changed server identity before mutations'}
        'setup-active' {Assert-Result ($outcome.Failure -like '*setup is already active*' -and $outcome.Saves -eq 0 -and $outcome.Backups -eq 0) 'Secondary recovery never duplicates active native setup'}
        'replication-pending' {Assert-Result ($outcome.Failure -like '*replication must finish*' -and $outcome.Saves -eq 0 -and $outcome.Backups -eq 0) 'Secondary recovery waits for initialized replication before backup or submission'}
        'backup-fails' {Assert-Result ($outcome.Failure -like '*backup verification failed*' -and $outcome.Saves -eq 0 -and $outcome.Properties['Requested Status'].Value1.StringValue -eq '1') 'Failed backup verification leaves the native secondary request unchanged'}
        'request-pending' {Assert-Result ($outcome.Failure -like '*request is pending*' -and $outcome.Saves -eq 0 -and $outcome.Backups -eq 0) 'A concurrent pending secondary request blocks recovery'}
        'changed-during-backup' {Assert-Result ($outcome.Failure -like '*changed during backup*' -and $outcome.Saves -eq 0 -and $outcome.Backups -eq 1) 'A secondary request changed during backup is re-read and never overwritten'}
        'already-local' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Result.WaitingForParentReport -and -not $outcome.Result.Submitted -and $outcome.Saves -eq 0 -and $outcome.Backups -eq 0) 'Installed local secondary packages wait for parent reporting without another recovery or backup'}
    }
}

foreach($scenario in @('lower-build-zero-status','same-build-zero-status','same-build-sender-stalls','same-build-recovery-stalls','same-build-awaiting-report','current-secondary')){
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:secondaryRoute=$scenario;$script:secondaryApplied=$false
        $script:secondaryUpgrades=0;$script:secondaryRecoveries=0;$script:recoveryPreviews=0;$script:executiveRestarts=0
        function Get-SccmProviderData {
            param($Provider,$SiteCode,$ClassName,$Filter)
            switch($ClassName){
                SMS_Site {
                    $parent=[pscustomobject]@{SiteCode='PS1';Type=2;Status=1;Version='5.00.9152.1000';ServerName='ps1-pss.mayyhem.com'}
                    $current=$script:secondaryApplied -or $script:secondaryRoute -eq 'current-secondary'
                    $child=[pscustomobject]@{SiteCode='SEC';Type=1;Status=1;Version=$(if($script:secondaryRoute -eq 'lower-build-zero-status' -and -not $current){'5.00.9141.1000'}else{'5.00.9152.1000'});ReportingSiteCode='PS1';ServerName='ps1-sec.mayyhem.com';SecondarySiteCMUpdateStatus=$(if($current){1}else{0})}
                    if($Filter){return $child};return @($parent,$child)
                }
                SMS_SCI_SysResUse {return [pscustomobject]@{SiteCode='PS1';RoleName='SMS Provider';NetworkOSPath='\\ps1-sms.mayyhem.com'}}
                SMS_ReplicationLinkStatus {return [pscustomobject]@{ChildSite='SEC';ParentSite='PS1';InitializationStatus=6;FailedSyncs=$(if($script:secondaryRecoveries -and -not $script:secondaryApplied){3}else{0});DegradedSyncs=0}}
            }
        }
        function Connect-SccmSite {}
        function Wait-SccmSiteReady {}
        function Wait-SccmCondition {
            param($Description,$TimeoutMinutes,[switch]$RetryReadErrors,[scriptblock]$Test)
            for($poll=0;$poll -lt 4;$poll++){if(& $Test){return}}
            throw 'Fixture condition did not reach native readiness.'
        }
        function Invoke-SccmRemote {
            param($ComputerName,$ScriptBlock,$ArgumentList)
            if($ComputerName -ne 'ps1-sec.mayyhem.com'){throw 'Wrong secondary host.'}
            if("$ScriptBlock" -notmatch 'Restart-Service'){return $false}
            $script:executiveRestarts++
            if($script:secondaryRoute -eq 'same-build-sender-stalls'){$script:secondaryApplied=$true}
        }
        function Invoke-CMSecondarySiteUpgrade {
            param($SecondarySiteCode,[switch]$Force,$ErrorAction)
            if($SecondarySiteCode -ne 'SEC'){throw 'Wrong secondary upgrade target.'}
            $script:secondaryUpgrades++;$script:secondaryApplied=$true
        }
        function Request-SccmSecondaryUpdateRecovery {
            param($Provider,$ParentCode,$SecondaryCode,$Server,$ExpectedVersion,$Preview)
            if($SecondaryCode -ne 'SEC' -or $ParentCode -ne 'PS1'){throw 'Wrong recovery target.'}
            if($Preview -ne $false){$script:recoveryPreviews++;return @{Submitted=$false;Preview=$true;MissingPackages=@('11111111-2222-3333-4444-555555555555')}}
            if($script:secondaryRoute -eq 'same-build-awaiting-report'){$script:secondaryApplied=$true;return @{Submitted=$false;WaitingForParentReport=$true}}
            $script:secondaryRecoveries++
            if($script:secondaryRoute -notin @('same-build-recovery-stalls','same-build-sender-stalls')){$script:secondaryApplied=$true}
            return @{Submitted=$true;Preview=$false;MissingPackages=@('11111111-2222-3333-4444-555555555555')}
        }
        $failure=$null;$changed=$null
        try{$changed=Complete-SccmSecondaryUpdates unused CAS 1 0}catch{$failure=$_.Exception.Message}
        return @{Changed=$changed;Upgrades=$script:secondaryUpgrades;Recoveries=$script:secondaryRecoveries;Previews=$script:recoveryPreviews;Restarts=$script:executiveRestarts;Failure=$failure}
    } $scenario
    switch($scenario){
        'lower-build-zero-status' {Assert-Result ($outcome.Changed -and $outcome.Upgrades -eq 1 -and $outcome.Recoveries -eq 0 -and $outcome.Previews -eq 0 -and $outcome.Restarts -eq 0) 'A lower-build secondary with native status zero requests one supported build upgrade'}
        'same-build-zero-status' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Changed -and $outcome.Upgrades -eq 0 -and $outcome.Recoveries -eq 1 -and $outcome.Previews -eq 0 -and $outcome.Restarts -eq 0) 'A same-build secondary missing parent updates gets one native recovery and is waited on'}
        'same-build-sender-stalls' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Changed -and $outcome.Recoveries -eq 1 -and $outcome.Restarts -eq 1) 'A recovered secondary whose links stay unhealthy after setup gets one SMS_EXECUTIVE restart and then reports current'}
        'same-build-recovery-stalls' {Assert-Result ($outcome.Failure -match 'did not reach' -and $outcome.Recoveries -eq 1 -and $outcome.Previews -eq 0 -and $outcome.Restarts -eq 1) 'A recovery that never reports current gets at most one restart and fails at the bounded wait without resubmitting'}
        'same-build-awaiting-report' {Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Changed -and $outcome.Recoveries -eq 0 -and $outcome.Previews -eq 0 -and $outcome.Restarts -eq 0) 'A same-build secondary with local packages waits for its parent report without recovery'}
        'current-secondary' {Assert-Result (-not $outcome.Changed -and $outcome.Upgrades -eq 0 -and $outcome.Recoveries -eq 0 -and $outcome.Previews -eq 0 -and $outcome.Restarts -eq 0) 'A current secondary never requests another upgrade or recovery'}
    }
}

foreach($scenario in @('default-availability','online-storage','warning','critical','inaccessible','missing-status')){
    $module=Import-Module $modulePath -Force -PassThru
    $ready=& $module {
        param($scenario)
        $row=[pscustomobject]@{Status=0;AvailabilityState=0;DownSince=$null}
        if($scenario -eq 'online-storage'){$row.AvailabilityState=4}
        if($scenario -eq 'warning'){$row.Status=1}
        if($scenario -eq 'critical'){$row.Status=2}
        if($scenario -eq 'inaccessible'){$row.DownSince=[datetime]'2026-10-27'}
        if($scenario -eq 'missing-status'){$row.Status=$null}
        Test-SccmStorageSummaryReady $row
    } $scenario
    Assert-Result ($ready -eq ($scenario -in @('default-availability','online-storage'))) "Storage health uses native green status and accessibility for $scenario"
}
foreach($scenario in @('mp-list','http-error','wrong-body','unreachable')){
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:mpProbeScenario=$scenario
        function Invoke-WebRequest {
            param([switch]$UseBasicParsing,$Uri,$TimeoutSec,$ErrorAction)
            if($Uri -ne 'http://fixture.mayyhem.com/sms_mp/.sms_aut?mplist'){throw 'Wrong MP endpoint.'}
            if($script:mpProbeScenario -eq 'unreachable'){throw 'Fixture connection failed.'}
            return [pscustomobject]@{StatusCode=$(if($script:mpProbeScenario -eq 'http-error'){500}else{200});Content=$(if($script:mpProbeScenario -eq 'wrong-body'){'<html>IIS</html>'}else{'<MPList><MP Name="fixture.mayyhem.com" /></MPList>'})}
        }
        $ready=$false;$failure=$null
        try{$ready=Test-SccmManagementPointEndpoint fixture.mayyhem.com}catch{$failure=$_.Exception.Message}
        return @{Ready=$ready;Failure=$failure}
    } $scenario
    if($scenario -eq 'unreachable'){Assert-Result ($outcome.Failure -like '*connection failed*' -and -not $outcome.Ready) 'An unreachable management point cannot pass endpoint verification'}
    else{Assert-Result ($null -eq $outcome.Failure -and $outcome.Ready -eq ($scenario -eq 'mp-list')) "MP endpoint requires HTTP success and an MP list for $scenario"}
}
foreach($scenario in @('patched-baseline','same-version','missing','duplicate','other-release','older-baseline','missing-version')){
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:baselineScenario=$scenario
        function Get-SccmProviderData {
            param($Provider,$SiteCode,$ClassName,$Filter)
            if($ClassName -ne 'SMS_ClientBaseline' -or $Filter -ne 'BaselineType=1'){throw 'Expected the native production baseline only.'}
            if($script:baselineScenario -eq 'missing'){return @()}
            $version='5.00.9152.1006'
            if($script:baselineScenario -eq 'same-version'){$version='5.00.9152.1000'}
            if($script:baselineScenario -eq 'other-release'){$version='5.00.9141.1011'}
            if($script:baselineScenario -eq 'older-baseline'){$version='5.00.9152.999'}
            if($script:baselineScenario -eq 'missing-version'){$version=$null}
            $row=[pscustomobject]@{ClientVersion=$version}
            if($script:baselineScenario -eq 'duplicate'){return @($row,$row)}
            return $row
        }
        function Get-SccmMsiVersion {return '5.00.9152.1000'}
        $failure=$null;$version=$null
        try{$version=Get-SccmProductionClientVersion unused PS1 'C:\fixture.msi'}catch{$failure=$_.Exception.Message}
        return @{Version=$version;Failure=$failure}
    } $scenario
    if($scenario -in @('patched-baseline','same-version')){
        $expected=if($scenario -eq 'patched-baseline'){'5.00.9152.1006'}else{'5.00.9152.1000'}
        Assert-Result ($null -eq $outcome.Failure -and $outcome.Version -eq $expected) "Native production client version is authoritative for $scenario"
    }else{Assert-Result ($null -ne $outcome.Failure -and $null -eq $outcome.Version) "Production client baseline fails closed for $scenario"}
}

foreach($scenario in @('ready','wrong-version','wrong-site','stopped','installing','needs-restart','missing')){
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $state=@{Version='5.00.9152.1006';AssignedSite='PS1';Service='Running';SetupRunning=$false;RebootRequired=$false}
        switch($scenario){
            'wrong-version' {$state.Version='5.00.9141.1011'}
            'wrong-site' {$state.AssignedSite='OTHER'}
            'stopped' {$state.Service='StopPending'}
            'installing' {$state.SetupRunning=$true}
            'needs-restart' {$state.RebootRequired=$true}
            'missing' {$state=$null}
        }
        $ready=$false;$failure=$null
        try{$ready=Test-SccmClientReady $state '5.00.9152.1006' PS1}catch{$failure=$_.Exception.Message}
        return @{Ready=$ready;Failure=$failure}
    } $scenario
    if($scenario -eq 'needs-restart'){Assert-Result ($outcome.Failure -like '*guest restart*' -and -not $outcome.Ready) 'Native client restart requests cannot pass client completion'}
    else{Assert-Result ($null -eq $outcome.Failure -and $outcome.Ready -eq ($scenario -eq 'ready')) "Client readiness requires version, assignment, running service and completed setup for $scenario"}
}
foreach($scenario in @('restart-pending','already-restarted','exit-zero','still-installing')){
    $module=Import-Module $modulePath -Force -PassThru
    $state=& $module {
        param($scenario)
        $script:clientStateScenario=$scenario
        function Get-CimInstance {
            param($ClassName,$Namespace,$ErrorAction)
            if($ClassName -eq 'SMS_Client'){return [pscustomobject]@{ClientVersion='5.00.9152.1006'}}
            return [pscustomobject]@{LastBootUpTime=[datetime]'2026-10-27T17:00:00'}
        }
        function Get-Service {param($Name,$ErrorAction);return [pscustomobject]@{Status='Running'}}
        function Invoke-CimMethod {param($Namespace,$ClassName,$MethodName,$ErrorAction);return [pscustomobject]@{sSiteCode='PS1'}}
        function Get-Process {param($Name,$ErrorAction);if($script:clientStateScenario -eq 'still-installing'){return [pscustomobject]@{Id=123}}}
        function Test-Path {param($LiteralPath);return $true}
        function Get-Content {param($LiteralPath,$Tail);return $(if($script:clientStateScenario -eq 'exit-zero'){'<![LOG[CcmSetup is exiting with return code 0]LOG]!>'}else{'<![LOG[CcmSetup is exiting with return code 7]LOG]!>'})}
        function Get-Item {param($LiteralPath);return [pscustomobject]@{LastWriteTime=$(if($script:clientStateScenario -eq 'already-restarted'){[datetime]'2026-10-27T16:00:00'}else{[datetime]'2026-10-27T18:00:00'})}}
        Get-SccmClientState
    } $scenario
    Assert-Result ($state.Version -eq '5.00.9152.1006' -and $state.RebootRequired -eq ($scenario -eq 'restart-pending') -and $state.SetupRunning -eq ($scenario -eq 'still-installing')) "Client setup results request a restart once and only after setup exits for $scenario"
}

foreach($scenario in @('service-finished','launcher-exit','service-reboot')){
    $module=Import-Module $modulePath -Force -PassThru
    $state=& $module {
        param($scenario)
        $script:clientStateScenario=$scenario
        function Get-CimInstance {
            param($ClassName,$Namespace,$ErrorAction)
            if($ClassName -eq 'SMS_Client'){return [pscustomobject]@{ClientVersion='5.00.9141.1032'}}
            return [pscustomobject]@{LastBootUpTime=[datetime]'2026-10-27T17:00:00'}
        }
        function Get-Service {param($Name,$ErrorAction);return [pscustomobject]@{Status='Running'}}
        function Invoke-CimMethod {param($Namespace,$ClassName,$MethodName,$ErrorAction);return [pscustomobject]@{sSiteCode='PS1'}}
        function Get-Process {param($Name,$ErrorAction)}
        function Test-Path {param($LiteralPath);return $true}
        function Get-Content {
            param($LiteralPath,$Tail)
            $code=$(if($script:clientStateScenario -eq 'service-reboot'){7}else{0})
            if($script:clientStateScenario -eq 'launcher-exit'){return @('<![LOG[Successfully started the ccmsetup service]LOG]!>','<![LOG[CcmSetup is exiting with return code 0]LOG]!>')}
            return @('<![LOG[Successfully deleted the ccmsetup service]LOG]!>','<![LOG[Deleted file C:\Windows\ccmsetup\ccmsetup.xml]LOG]!>',"<![LOG[CcmSetup is exiting with return code $code]LOG]!>")
        }
        function Get-Item {param($LiteralPath);return [pscustomobject]@{LastWriteTime=[datetime]'2026-10-27T18:00:00';LastWriteTimeUtc=[datetime]::SpecifyKind([datetime]'2026-10-27T23:00:00','Utc')}}
        Get-SccmClientState
    } $scenario
    switch($scenario){
        'service-finished' {Assert-Result ($state.SetupExitCode -eq 0 -and $state.SetupFinishedUtc -like '2026-10-27T23:00:00*' -and -not $state.RebootRequired) 'A finished native setup service run reports its exit code and finish time'}
        'launcher-exit' {Assert-Result ($null -eq $state.SetupExitCode -and -not $state.SetupFinishedUtc) 'The setup launcher exit is never mistaken for a finished setup run'}
        'service-reboot' {Assert-Result ($state.SetupExitCode -eq 7 -and $state.RebootRequired) 'A finished setup run that needs a restart still reports the restart'}
    }
}

foreach($scenario in @('prune','delete-fails')){
    $module=Import-Module $modulePath -Force -PassThru
    $root=Join-Path ([IO.Path]::GetTempPath()) ('sccm-backup-fixture-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    foreach($name in @('CM_PS1_ludus_20261104073742727.bak','CM_PS1_ludus_20261104105258464.bak','CM_PS1_ludus_20261104180338716.bak','CM_CAS_ludus_20261104073730587.bak','CM_PS1_manual.bak','CM_PS1_ludus_20261104073742727.bak.txt')){Set-Content -LiteralPath (Join-Path $root $name) -Value 'fixture'}
    $outcome=& $module {
        param($scenario,$root)
        $script:pruneLog=@()
        function ConvertTo-SccmAdminShare {param($ComputerName,$Path);return $root}
        function Write-SccmLog {param($Message,$Level='INFO');$script:pruneLog+="$Level $Message"}
        if($scenario -eq 'delete-fails'){function Remove-Item {param($LiteralPath,[switch]$Force,$ErrorAction);throw 'Fixture access denied.'}}
        $failure=$null
        try{Remove-SccmOlderDatabaseBackups ps1-db.mayyhem.com 'C:\Backup\' CM_PS1 'C:\Backup\CM_PS1_ludus_20261104180338716.bak'}catch{$failure=$_.Exception.Message}
        return @{Failure=$failure;Log=$script:pruneLog}
    } $scenario $root
    $left=@(Get-ChildItem -LiteralPath $root -File | ForEach-Object Name | Sort-Object)
    Remove-Item -LiteralPath $root -Recurse -Force
    if($scenario -eq 'delete-fails'){
        Assert-Result ($null -eq $outcome.Failure -and $left.Count -eq 6 -and @($outcome.Log | Where-Object { $_ -like 'WARNING*' }).Count -eq 1) 'A failed backup cleanup only warns and never blocks servicing'
    }else{
        Assert-Result ($null -eq $outcome.Failure -and ($left -join ',') -eq 'CM_CAS_ludus_20261104073730587.bak,CM_PS1_ludus_20261104073742727.bak.txt,CM_PS1_ludus_20261104180338716.bak,CM_PS1_manual.bak' -and @($outcome.Log | Where-Object { $_ -like 'INFO Removed*' }).Count -eq 2) 'Backup cleanup keeps the newest verified lab backup and never touches other files'
    }
}

$module=Import-Module $modulePath -Force -PassThru
$logPath=Join-Path $PSScriptRoot 'fixture-main.log'
$otherLog=Join-Path $PSScriptRoot 'fixture-component.log'
$actual=& $module {param($path,$other) Set-SccmLog $path; Set-SccmLog $other -OnlyIfUnset; return $script:SccmLogPath} $logPath $otherLog
Assert-Result ($actual -eq $logPath) 'Local component initialization preserves the coordinator log destination'
$module=Import-Module $modulePath -Force -PassThru
$actual=& $module {param($path) Set-SccmLog $path -OnlyIfUnset; return $script:SccmLogPath} $otherLog
Assert-Result ($actual -eq $otherLog) 'A fresh remote component process initializes its own log destination'

foreach($scenario in @('client','console','site','windows','wrong-computer','wrong-domain','installer-active','msi-active','already-rebooted','missing-boot','client-version-changed','client-not-pending','console-version-changed','site-not-pending','windows-not-pending','unknown-kind')){
    $module=Import-Module $modulePath -Force -PassThru
    $outcome=& $module {
        param($scenario)
        $script:restartScenario=$scenario
        function Get-SccmBootTimeUtc {return 'boot-a'}
        function Get-CimInstance {
            param($ClassName,$Namespace,$Filter,$ErrorAction)
            if($ClassName -eq 'Win32_ComputerSystem'){return [pscustomobject]@{Domain='mayyhem.com'}}
            return [pscustomobject]@{SiteCode='CAS';State=$(if($script:restartScenario -eq 'site-not-pending'){196612}else{196613})}
        }
        function Get-Process {param($Name,$ErrorAction);if($script:restartScenario -eq 'installer-active'){return [pscustomobject]@{Id=123}}}
        function Test-Path {param($Path);return ($script:restartScenario -eq 'msi-active') -or ($script:restartScenario -eq 'windows' -and $Path -like '*RebootPending')}
        function Get-SccmClientState {return @{Version=$(if($script:restartScenario -eq 'client-version-changed'){'5.00.9141.1011'}else{'5.00.9152.1006'});AssignedSite='PS1';RebootRequired=($script:restartScenario -ne 'client-not-pending');SetupRunning=$false}}
        function Get-SccmConsoleVersion {if($script:restartScenario -eq 'console-version-changed'){return '5.2509.1000.1000'};return '5.2609.1050.1000'}
        function Get-SccmPendingRestartRequests {return [pscustomobject]@{Kind='Console';Version='5.2609.1050.1000'}}
        $kind='Client';$version='5.00.9152.1006';$code='PS1'
        if($scenario -in @('console','console-version-changed')){$kind='Console';$version='5.2609.1050.1000'}
        if($scenario -in @('site','site-not-pending')){$kind='SiteUpdate';$code='CAS'}
        if($scenario -in @('windows','windows-not-pending')){$kind='WindowsPrerequisite'}
        if($scenario -eq 'unknown-kind'){$kind='Unknown'}
        $request=@{Computer=($env:COMPUTERNAME+'.mayyhem.com');Kind=$kind;Version=$version;SiteCode=$code;BootTimeUtc='boot-a';PackageGuid='11111111-1111-1111-1111-111111111111'}
        if($scenario -eq 'wrong-computer'){$request.Computer='other.mayyhem.com'}
        if($scenario -eq 'wrong-domain'){$request.Computer=$env:COMPUTERNAME+'.other.invalid'}
        if($scenario -eq 'already-rebooted'){$request.BootTimeUtc='old-boot'}
        if($scenario -eq 'missing-boot'){$request.BootTimeUtc=''}
        $result=$null;$failure=$null
        try{$result=Test-SccmGuestRestart $request}catch{$failure=$_.Exception.Message}
        return @{Result=$result;Failure=$failure}
    } $scenario
    if($scenario -in @('client','console','site','windows')){Assert-Result ($null -eq $outcome.Failure -and $outcome.Result.NeedsRestart) "A proved native $scenario checkpoint permits the exact guest restart"}
    elseif($scenario -eq 'already-rebooted'){Assert-Result ($null -eq $outcome.Failure -and -not $outcome.Result.NeedsRestart -and $outcome.Result.AlreadyRebooted) 'A resumed restart checkpoint never reboots a guest whose boot identity has changed'}
    else{Assert-Result ($null -ne $outcome.Failure -and $null -eq $outcome.Result) "The restart guard refuses $scenario"}
}
foreach($scenario in @('client-ready','client-pending','client-installing','same-boot','console-ready','console-old','site-cleared','site-still-pending','windows-cleared','windows-pending')){
    $module=Import-Module $modulePath -Force -PassThru
    $ready=& $module {
        param($scenario)
        $script:postRestartScenario=$scenario
        function Get-SccmBootTimeUtc {if($script:postRestartScenario -eq 'same-boot'){return 'boot-a'};return 'boot-b'}
        function Get-SccmClientState {return @{Service='Running';AssignedSite='PS1';SetupRunning=($script:postRestartScenario -eq 'client-installing');RebootRequired=($script:postRestartScenario -eq 'client-pending')}}
        function Get-SccmConsoleVersion {if($script:postRestartScenario -eq 'console-old'){return '5.2509.1000.1000'};return '5.2609.1050.1000'}
        function Get-CimInstance {param($ClassName,$Namespace,$Filter,$ErrorAction);return [pscustomobject]@{SiteCode='CAS';State=$(if($script:postRestartScenario -eq 'site-still-pending'){196613}else{196612})}}
        function Get-Service {param($Name,$ErrorAction);return [pscustomobject]@{Status='Running'}}
        function Test-Path {param($Path);return $script:postRestartScenario -eq 'windows-pending'}
        $kind='Client';$code='PS1';$version='5.00.9152.1006'
        if($scenario -like 'console-*'){$kind='Console';$version='5.2609.1050.1000'}
        if($scenario -like 'site-*'){$kind='SiteUpdate';$code='CAS'}
        if($scenario -like 'windows-*'){$kind='WindowsPrerequisite'}
        Test-SccmGuestAfterRestart @{Computer=$env:COMPUTERNAME;Kind=$kind;SiteCode=$code;Version=$version;BootTimeUtc='boot-a';PackageGuid='11111111-1111-1111-1111-111111111111'}
    } $scenario
    Assert-Result ($ready -eq ($scenario -in @('client-ready','console-ready','site-cleared','windows-cleared'))) "Post-restart readiness verifies actual native state for $scenario"
}
$module=Import-Module $modulePath -Force -PassThru
$outcome=& $module {
    function Invoke-SccmRemote {param($ComputerName,$ScriptBlock);return 'fixture-boot'}
    $sites=@([pscustomobject]@{SiteCode='CAS';ServerName='cas-pss.mayyhem.com';Version='5.00.9152.1000'},[pscustomobject]@{SiteCode='PS1';ServerName='ps1-pss.mayyhem.com';Version='5.00.9152.1000'})
    $states=@([pscustomobject]@{SiteCode='CAS';State=196612},[pscustomobject]@{SiteCode='PS1';State=196613})
    $requests=@(Get-SccmSiteRestartRequests $sites $states '11111111-1111-1111-1111-111111111111')
    $failure=$null
    try{Stop-SccmForRestart $requests 'Fixture checkpoint'}catch{$failure=$_.Exception}
    return @{Requests=$requests;Fatal=$failure.Data['SccmFatal'];Data=$failure.Data['SccmRestartRequestsJson']}
}
Assert-Result ($outcome.Requests.Count -eq 1 -and $outcome.Requests[0].Computer -eq 'ps1-pss.mayyhem.com' -and $outcome.Fatal -and ($outcome.Data | ConvertFrom-Json).Computer -eq 'ps1-pss.mayyhem.com') 'A child-primary reboot checkpoint retains its exact package and guest identity through exception serialization'

$module=Import-Module $modulePath -Force -PassThru
$journal=& $module {
    $script:fixtureBoot='boot-a';$script:fixtureJournal='[]';$script:journalWrites=0
    function Get-SccmBootTimeUtc {return $script:fixtureBoot}
    function Test-Path {param($LiteralPath);return $true}
    function Get-Content {param($LiteralPath,[switch]$Raw);return $script:fixtureJournal}
    function Set-Content {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline)]$Value,$LiteralPath,$Encoding)
        process {
            if($LiteralPath -notlike '*pending-deployment-restarts.json'){throw 'Fixture refuses writes outside the automation journal.'}
            $script:fixtureJournal=$Value;$script:journalWrites++
        }
    }
    $null=New-SccmRestartRequest fixture Console '5.2609.1050.1000' PS1 -Persist
    $active=@(Get-SccmPendingRestartRequests)
    $script:fixtureBoot='boot-b'
    $stale=@(Get-SccmPendingRestartRequests)
    $null=New-SccmRestartRequest fixture Console '5.2703.1000.1000' PS1 -Persist
    $next=@(Get-SccmPendingRestartRequests)
    return @{Active=$active;Stale=$stale;Next=$next;Writes=$script:journalWrites}
}
Assert-Result ($journal.Active.Count -eq 1 -and $journal.Active[0].BootTimeUtc -eq 'boot-a') 'Console restart requests persist in the automation-owned journal for the current boot'
Assert-Result ($journal.Stale.Count -eq 0 -and $journal.Next.Count -eq 1 -and $journal.Next[0].BootTimeUtc -eq 'boot-b' -and $journal.Writes -eq 2) 'A completed guest reboot expires old console requests before a later request is saved'

& (Join-Path $PSScriptRoot 'Test-SccmCompletionRestart.ps1')

# Exercise the complete hotfix discovery loop with native calls replaced by
# scoped fixtures. In particular, a request cooldown must not erase an earlier
# successful observation or turn busy-only responses into a completed scan.
$hotfixScript=Join-Path $PSScriptRoot '../../roles/service_hierarchy/files/Update-SccmHotfixes.ps1'
foreach($scenario in @('cooldown-between-scans','busy-only','fix-between-scans')){
    $outcome=& {
        param($scenario,$hotfixScript)
        # Share one object across the external script's child scope; $script:
        # would refer to that script rather than this fixture when mocks run.
        $catalogFixture=@{Scenario=$scenario;Round=0;Installs=0}
        function Import-Module {param($Name,[switch]$Force)}
        function Connect-SccmSite {param($Code,$Provider)}
        function Set-SccmLog {param($Path)}
        function Write-SccmLog {param($Message,$Level)}
        function Start-Sleep {param($Seconds)}
        function Request-SccmCatalogCheck {
            $catalogFixture.Round++
            switch($catalogFixture.Scenario){
                'busy-only' {return $false}
                'cooldown-between-scans' {return $catalogFixture.Round -in @(1,4)}
                default {return $true}
            }
        }
        function Get-SccmProviderData {
            param($Provider,$SiteCode,$ClassName,$Filter)
            if($ClassName -eq 'SMS_Site'){return [pscustomobject]@{SiteCode='CAS';Version='5.00.9152.1000'}}
            return @()
        }
        function Select-SccmHotfix {
            param($Packages,$Version)
            if($catalogFixture.Scenario -eq 'fix-between-scans' -and $catalogFixture.Round -eq 2){return [pscustomobject]@{PackageGuid='fixture-fix';Name='Fixture fix';State=131075}}
            return $null
        }
        function Install-SccmUpdatePackage {$catalogFixture.Installs++}
        function Complete-SccmSecondaryUpdates {}
        function Assert-SccmReplication {}
        $failure=$null;$result=$null
        try{$result=& $hotfixScript -WorkDirectory 'C:\fixture' -Provider unused -SiteCode CAS -CatalogSettleSeconds 0}catch{$failure=$_.Exception.Message}
        return @{Failure=$failure;Result=$result;Rounds=$catalogFixture.Round;Installs=$catalogFixture.Installs}
    } $scenario $hotfixScript
    Write-Host ("Hotfix loop fixture {0}: {1}" -f $scenario, ($outcome | ConvertTo-Json -Compress -Depth 4))
    switch($scenario){
        'cooldown-between-scans' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Rounds -eq 4 -and -not $outcome.Result.Changed) 'Native cooldown responses preserve prior settled scans until a second accepted scan'}
        'busy-only' {Assert-Result ($outcome.Failure -like '*exceeded 50 rounds*' -and $outcome.Rounds -eq 50) 'Busy-only catalog checks never imply a completed empty catalog'}
        'fix-between-scans' {Assert-Result ($null -eq $outcome.Failure -and $outcome.Installs -eq 1 -and $outcome.Rounds -eq 4 -and $outcome.Result.Changed) 'A newly offered fix resets quiet observations and requires two subsequent settled scans'}
    }
}
foreach ($scenario in @('settles', 'persistent', 'ready')) {
    $module = Import-Module $modulePath -Force -PassThru
    $outcome = & $module {
        param($scenario)
        $script:replicationReads = 0
        $script:replicationSleeps = 0
        $script:replicationWarnings = @()
        function Write-SccmLog { param($Message, $Level) if ($Level -eq 'WARNING') { $script:replicationWarnings += $Message } }
        function Start-Sleep { param($Seconds) $script:replicationSleeps++ }
        function Get-SccmProviderData {
            param($Provider, $SiteCode, $ClassName, $Filter)
            if ($ClassName -ne 'SMS_ReplicationLinkStatus') { throw "Unexpected class $ClassName" }
            $script:replicationReads++
            $degraded = switch ($scenario) { 'settles' { [int]($script:replicationReads -lt 3) } 'persistent' { 1 } default { 0 } }
            return @(
                [pscustomobject]@{ParentSite='CAS'; ChildSite='PS1'; ReplicationGroup='Site Control Data'; InitializationStatus=6; FailedSyncs=0; DegradedSyncs=0},
                [pscustomobject]@{ParentSite='CAS'; ChildSite='PS1'; ReplicationGroup='Hardware_Inventory'; InitializationStatus=6; FailedSyncs=0; DegradedSyncs=$degraded}
            )
        }
        $failure = $null
        # A zero-minute bound still reads and waits until its deadline has passed.
        $timeout = if ($scenario -eq 'persistent') { 0 } else { 60 }
        try { Assert-SccmReplication 'provider-fixture' 'CAS' $timeout 0 } catch { $failure = $_.Exception.Message }
        return @{Failure=$failure; Reads=$script:replicationReads; Sleeps=$script:replicationSleeps; Warnings=$script:replicationWarnings}
    } $scenario
    switch ($scenario) {
        'settles' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Reads -eq 3 -and $outcome.Sleeps -eq 2 -and $outcome.Warnings[0] -like '*Hardware_Inventory (initialization 6, failed 0, degraded 1)*') 'Briefly degraded replication groups are named and waited on until native replication settles' }
        'persistent' { Assert-Result ($outcome.Failure -like '*1 unready groups after 0 minutes: CAS->PS1 Hardware_Inventory*Replication Link Analyzer*' -and $outcome.Reads -eq 1) 'Replication that stays degraded past its bound still stops servicing and names the group' }
        'ready' { Assert-Result ($null -eq $outcome.Failure -and $outcome.Reads -eq 1 -and $outcome.Sleeps -eq 0) 'Ready replication proceeds after one read without waiting' }
    }
}

$module = Import-Module $modulePath -Force -PassThru
$selection = & $module {
    $roles = @(
        [pscustomobject]@{SiteCode='PS1'; RoleName='SMS Provider'; NetworkOSPath='\\ps1-psv.mayyhem.com'},
        [pscustomobject]@{SiteCode='PS1'; RoleName='SMS Provider'; NetworkOSPath='\\PS1-SMS.MAYYHEM.COM'},
        [pscustomobject]@{SiteCode='PS1'; RoleName='SMS Provider'; NetworkOSPath='\\ps1-pss.mayyhem.com'}
    )
    function Write-SccmLog {}
    function Get-SccmProviderData {
        param($Provider, $SiteCode, $ClassName, $Filter)
        switch ($ClassName) {
            SMS_SCI_SysResUse { return $roles }
            SMS_Site { if ($Filter -ne "SiteCode='PS1'") { throw 'Wrong site filter.' }; return [pscustomobject]@{SiteCode='PS1'; ServerName='PS1-PSS.mayyhem.com'} }
        }
    }
    return @{
        Active = Select-SccmSiteProvider $roles 'ps1-pss.mayyhem.com'
        NoSiteServerProvider = Select-SccmSiteProvider @($roles[0], $roles[1]) 'ps1-pss.mayyhem.com'
        Lookup = Get-SccmSiteProvider 'cas-pss' 'CAS' 'PS1'
        Root = Get-SccmSiteProvider 'cas-pss' 'CAS' 'CAS'
    }
}
Assert-Result ($selection.Active -eq 'ps1-pss.mayyhem.com') 'A site provider on the active site server is preferred over passive and remote providers listed first'
Assert-Result ($selection.NoSiteServerProvider -eq 'ps1-psv.mayyhem.com') 'Without a provider on the site server the first registered provider is still used'
Assert-Result ($selection.Lookup -eq 'ps1-pss.mayyhem.com' -and $selection.Root -eq 'cas-pss') 'Child-site provider lookup selects the active site server provider and the root keeps its own provider'
Write-Host "Passed $script:checks offline PowerShell behavior checks."
