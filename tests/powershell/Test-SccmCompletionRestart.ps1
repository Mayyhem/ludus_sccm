# Isolated coordinator fixtures: every guest/provider/installer operation is mocked.
$completionScript = Join-Path $PSScriptRoot '../../roles/service_hierarchy/files/Complete-SccmDeployment.ps1'
$completionChecks = 0
function Assert-CompletionFixture {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw "FAIL: $Message"}
    $script:completionChecks++
    Write-Host "PASS: $Message"
}
foreach($scenario in @('client-restart','client-unassigned','console-restart','manual-restart','unreachable','client-two-pass','client-stuck')){
    $outcome=& {
        param($scenario,$completionScript,$fixtureRoot)
        $fixture=@{Scenario=$scenario;Resumed=$false;ClientVersion='5.00.9141.1011';ConsoleVersion=$null;ClientInstalls=0;ConsoleInstalls=0;Reloads=0;Root=($env:COMPUTERNAME+'.mayyhem.com')}
        if($scenario -eq 'console-restart'){$fixture.ClientVersion='5.00.9152.1006';$fixture.ConsoleVersion='5.2509.1000.1000'}
        [void][IO.Directory]::CreateDirectory($fixtureRoot)
        function Import-Module {param($Name,[switch]$Force)}
        function Set-SccmLog {param($Path,[switch]$OnlyIfUnset)}
        function Write-SccmLog {param($Message,$Level)}
        function Stop-SccmWork {param($Message);throw $Message}
        function Connect-SccmSite {param($SiteCode,$Provider)}
        function Wait-SccmSiteReady {}
        function Wait-SccmPassiveReady {}
        function Test-SccmStorageSummaryReady {return $true}
        function Get-SccmResourceComputerName {return 'ps1-dev.mayyhem.com'}
        function ConvertTo-SccmAdminShare {param($Computer,$Path);return $fixtureRoot}
        function Copy-SccmFile {}
        function Get-SccmProductionClientVersion {return '5.00.9152.1006'}
        function Select-SccmSiteProvider {param($ProviderRoles,$SiteServer);return ([string]@($ProviderRoles)[0].NetworkOSPath).Trim('\')}
        function Assert-SccmReplication {}
        function Update-CMDistributionPoint {param($BootImageId,[switch]$ReloadBootImage,$Confirm,$ErrorAction);$fixture.Reloads++}
        function Wait-SccmCondition {
            param($Description,$TimeoutMinutes,[switch]$RetryReadErrors,[scriptblock]$Test)
            if(-not (& $Test)){throw "Fixture condition remains false: $Description"}
        }
        function Test-SccmClientReady {
            param($State,$Version,$SiteCode)
            if($State.RebootRequired){throw 'Native client setup requires a guest restart.'}
            return $State.Version -eq $Version -and $State.AssignedSite -eq $SiteCode -and $State.Service -eq 'Running'
        }
        function Get-SccmProviderData {
            param($Provider,$SiteCode,$ClassName,$Filter)
            switch($ClassName){
                SMS_Site {return [pscustomobject]@{SiteCode='PS1';ServerName=$fixture.Root;InstallDir='C:\fixture';Status=1;Version='5.00.9152.1000';Type=2}}
                SMS_SCI_SysResUse {return @([pscustomobject]@{SiteCode='PS1';RoleName='SMS Site Server';NetworkOSPath=('\\'+$fixture.Root)},[pscustomobject]@{SiteCode='PS1';RoleName='SMS Provider';NetworkOSPath=('\\'+$fixture.Root)})}
                SMS_SiteSystemSummarizer {return [pscustomobject]@{SiteCode='PS1';Role='SMS Site Server';SiteSystem=$fixture.Root;Status=0;AvailabilityState=4;DownSince=$null}}
                SMS_Identification {return [pscustomobject]@{SMSBuildNumber=9152;SMSAvailableConsoleVersion='5.2609.1050.1000'}}
                SMS_R_System {return [pscustomobject]@{Client=1;Obsolete=0;Name='PS1-DEV'}}
                SMS_BootImagePackage {return [pscustomobject]@{PackageID='PS100002';SourceVersion=$(if($fixture.Reloads){3}else{2})}}
                SMS_PackageStatusDistPointsSummarizer {return [pscustomobject]@{PackageID='PS100002';SourceVersion=$(if($fixture.Reloads){3}else{2});State=0}}
            }
        }
        function Invoke-SccmRemote {
            param($ComputerName,[scriptblock]$ScriptBlock,[object[]]$ArgumentList)
            $text=$ScriptBlock.ToString()
            # The fixture provider is this test host; only the client is unreachable.
            if($text -match 'SMS_Identification'){return 9152}
            if($ComputerName -eq 'ps1-dev.mayyhem.com' -and $fixture.Scenario -eq 'unreachable'){throw 'Fixture endpoint unreachable'}
            if($text -match 'return @\{ConsoleVersion'){
                if($ComputerName -ne 'ps1-dev.mayyhem.com'){return @{ConsoleVersion=$null;ClientVersion=$null;AssignedSite=$null;PendingRestarts=@()}}
                return @{ConsoleVersion=$fixture.ConsoleVersion;ClientVersion=$fixture.ClientVersion;AssignedSite='PS1';PendingRestarts=@()}
            }
            if($text -match 'ConsoleSetup\\ConsoleSetup.exe'){
                $fixture.ConsoleInstalls++;$fixture.ConsoleVersion='5.2609.1050.1000'
                return @{Computer='ps1-dev.mayyhem.com';Kind='Console';Version='5.2609.1050.1000';SiteCode='PS1';BootTimeUtc='fixture-boot';PackageGuid=''}
            }
            if($text -match 'Client\\ccmsetup.exe'){
                $fixture.ClientInstalls++
                # Native setup applies one patch level per run in the two-pass case.
                $fixture.ClientVersion=$(if($fixture.Scenario -eq 'client-stuck' -or ($fixture.Scenario -eq 'client-two-pass' -and $fixture.ClientInstalls -eq 1)){'5.00.9152.1003'}else{'5.00.9152.1006'})
                return '2026-11-05T00:00:00.0000000Z'
            }
            if($text -match 'Get-SccmClientState'){
                $finished=$fixture.Scenario -in @('client-two-pass','client-stuck')
                return @{Version=$fixture.ClientVersion;AssignedSite=$(if($fixture.Scenario -eq 'client-unassigned' -and -not $fixture.Resumed){''}else{'PS1'});Service='Running';SetupRunning=$false;RebootRequired=(-not $fixture.Resumed -and -not $finished);BootTimeUtc='fixture-boot';SetupExitCode=$(if($finished){0}else{$null});SetupFinishedUtc=$(if($finished){'2026-11-05T00:05:00.0000000Z'}else{''})}
            }
            if($text -match 'Get-SccmConsoleVersion'){return $fixture.ConsoleVersion}
            return 'fixture-probe'
        }
        $first=$null;$second=$null;$third=$null;$failure=$null
        try{$first=& $completionScript -WorkDirectory $fixtureRoot -Provider unused -SiteCode PS1 -TargetBuild 9152 -CheckpointForReboot ($scenario -ne 'manual-restart')}catch{$failure=$_.Exception.Message}
        $firstReport=Get-Content (Join-Path $fixtureRoot 'deployment-report.json') -Raw | ConvertFrom-Json
        $reloadsBeforeRestart=$fixture.Reloads
        if($first -and $first.RebootRequests.Count){
            $fixture.Resumed=$true
            $second=& $completionScript -WorkDirectory $fixtureRoot -Provider unused -SiteCode PS1 -TargetBuild 9152 -CheckpointForReboot $true
            $third=& $completionScript -WorkDirectory $fixtureRoot -Provider unused -SiteCode PS1 -TargetBuild 9152 -CheckpointForReboot $true
        }
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        return @{First=$first;FirstReport=$firstReport;Second=$second;Third=$third;Failure=$failure;ReloadsBeforeRestart=$reloadsBeforeRestart;Fixture=$fixture}
    } $scenario $completionScript (Join-Path $PSScriptRoot ('completion-fixture-'+$scenario+'-'+[guid]::NewGuid().ToString('N')))
    if($scenario -in @('client-restart','client-unassigned','console-restart')){
        Assert-CompletionFixture ($null -eq $outcome.Failure -and -not $outcome.First.Complete -and $outcome.First.RebootRequests.Count -eq 1 -and $outcome.ReloadsBeforeRestart -eq 0) "Coordinator returns an incomplete restart checkpoint before boot-image work for $scenario"
        $reported=@(if($scenario -eq 'console-restart'){$outcome.First.Consoles}else{$outcome.First.Clients})
        Assert-CompletionFixture ($reported.Count -eq 1 -and -not $reported[0].Ready -and $reported[0].RebootRequired) "A required restart never appears as healthy component completion for $scenario"
        Assert-CompletionFixture ($outcome.Second.Complete -and $outcome.Third.Complete -and -not $outcome.Third.Changed -and $outcome.Fixture.Reloads -eq 1 -and ($outcome.Fixture.ClientInstalls+$outcome.Fixture.ConsoleInstalls) -eq 1) "Resume verifies current components and refreshes boot images only once for $scenario"
    }elseif($scenario -eq 'client-two-pass'){
        Assert-CompletionFixture ($null -eq $outcome.Failure -and $outcome.First.Complete -and -not $outcome.First.RebootRequests.Count -and $outcome.Fixture.ClientInstalls -eq 2 -and $outcome.First.Clients[0].Version -eq '5.00.9152.1006') 'A client left below the production version by a finished setup run gets one more setup run instead of a timeout'
    }elseif($scenario -eq 'client-stuck'){
        Assert-CompletionFixture ($outcome.Failure -like '*Some components failed*' -and $outcome.Fixture.ClientInstalls -eq 3 -and ($outcome.FirstReport.Failures -join ' ') -like '*after 3 runs*') 'A client that never reaches the production version stops after three setup runs'
    }elseif($scenario -eq 'manual-restart'){
        Assert-CompletionFixture ($outcome.Failure -like '*Some components failed*' -and -not $outcome.FirstReport.Complete -and ($outcome.FirstReport.Failures -join ' ') -like '*requires a guest restart*') 'Disabled checkpoint mode preserves an explicit restart failure'
    }else{
        Assert-CompletionFixture ($outcome.Failure -like '*Some components failed*' -and -not $outcome.FirstReport.Complete -and $outcome.FirstReport.UnreachableClients.Count -eq 1) 'An unreachable registered client prevents a completed deployment report'
    }
}
Write-Host "Passed $completionChecks isolated completion restart checks."
