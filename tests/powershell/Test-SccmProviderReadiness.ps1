# All WMI, remoting and target state are mocked. No installation is submitted.
$ErrorActionPreference='Stop'
$probePath=Join-Path $PSScriptRoot '../../roles/install_sms/files/Get-SccmProviderState.ps1'
$checks=0
foreach($scenario in @('absent','ready','registered-missing','old-version','wrong-site-server','missing-adk','installer-active','wrong-computer','wrong-domain','other-site','unregistered-namespace','duplicate','parent-wrong-server','parent-inactive','remote-error','foreign-target')){
    $outcome=& {
        param($Scenario,$ProbePath)
        $global:SccmProviderFixtureScenario=$Scenario
        $global:SccmProviderFixtureReads=0;$global:SccmProviderFixtureRemoteReads=0
        $Ansible=[pscustomobject]@{Changed=$null;Result=$null}
        function Get-CimInstance {
            param($ComputerName,$Namespace,$ClassName,$Filter,$ErrorAction)
            $global:SccmProviderFixtureReads++
            if($ComputerName -ne 'ps1-pss.mayyhem.com'){throw 'Unexpected parent target.'}
            if($ClassName -eq 'SMS_Site'){
                return [pscustomobject]@{Status=$(if($global:SccmProviderFixtureScenario -eq 'parent-inactive'){2}else{1});Type=2;Version='5.00.9152.1000';ServerName=$(if($global:SccmProviderFixtureScenario -eq 'parent-wrong-server'){'unexpected.mayyhem.com'}else{'ps1-pss.mayyhem.com'})}
            }
            if($ClassName -ne 'SMS_ProviderLocation'){throw 'Unexpected native class.'}
            if($global:SccmProviderFixtureScenario -in @('ready','registered-missing','old-version','wrong-site-server','duplicate')){
                $row=[pscustomobject]@{Machine='ps1-sms.mayyhem.com';SiteCode='PS1'}
                if($global:SccmProviderFixtureScenario -eq 'duplicate'){return @($row,$row)}
                return $row
            }
        }
        function Invoke-Command {
            param($ComputerName,$ErrorAction,$ArgumentList,$ScriptBlock)
            $global:SccmProviderFixtureRemoteReads++
            if($ComputerName -ne 'ps1-sms.mayyhem.com' -or $ArgumentList -ne 'PS1'){throw 'Unexpected remote target.'}
            if($global:SccmProviderFixtureScenario -eq 'remote-error'){throw 'Fixture access denied.'}
            $exists=$global:SccmProviderFixtureScenario -in @('ready','old-version','wrong-site-server','unregistered-namespace')
            return @{Computer=$(if($global:SccmProviderFixtureScenario -eq 'wrong-computer'){'unexpected'}else{'PS1-SMS'});
                Domain=$(if($global:SccmProviderFixtureScenario -eq 'wrong-domain'){'unexpected.test'}else{'mayyhem.com'});
                NamespaceExists=$exists;OtherSites=$(if($global:SccmProviderFixtureScenario -eq 'other-site'){@('site_SEC')}else{@()});
                Version=$(if($global:SccmProviderFixtureScenario -eq 'old-version'){'5.00.9141.1000'}elseif($exists){'5.00.9152.1000'}else{''});
                Build=$(if($global:SccmProviderFixtureScenario -eq 'old-version'){9141}elseif($exists){9152}else{0});
                SiteServer=$(if($global:SccmProviderFixtureScenario -eq 'wrong-site-server'){'unexpected.mayyhem.com'}else{'ps1-pss.mayyhem.com'});
                SiteRows=$(if($exists){1}else{0});AdkDeploymentTools=($global:SccmProviderFixtureScenario -ne 'missing-adk');InstallerActive=($global:SccmProviderFixtureScenario -eq 'installer-active')}
        }
        $failure=$null
        try{
            $target=if($Scenario -eq 'foreign-target'){'ps1-sms.unexpected.test'}else{'ps1-sms.mayyhem.com'}
            & $ProbePath -SiteServer ps1-pss.mayyhem.com -SiteCode PS1 -Target $target -Domain mayyhem.com
        }catch{$failure=$_.Exception.Message}
        return @{State=$Ansible.Result;Changed=$Ansible.Changed;Failure=$failure;Reads=$global:SccmProviderFixtureReads;RemoteReads=$global:SccmProviderFixtureRemoteReads}
    } $scenario $probePath
    $ok=switch($scenario){
        'absent' {$null -eq $outcome.Failure -and $outcome.State.CanInstall -and -not $outcome.State.Ready -and -not $outcome.State.Registered}
        'ready' {$null -eq $outcome.Failure -and $outcome.State.Ready -and $outcome.State.Registered -and -not $outcome.State.CanInstall}
        'registered-missing' {$null -eq $outcome.Failure -and $outcome.State.Registered -and -not $outcome.State.Ready -and -not $outcome.State.CanInstall}
        {$_ -in @('old-version','wrong-site-server','missing-adk','installer-active','other-site','unregistered-namespace')} {$null -eq $outcome.Failure -and -not $outcome.State.Ready -and -not $outcome.State.CanInstall}
        {$_ -in @('wrong-computer','wrong-domain')} {$outcome.Failure -like '*different computer or domain*'}
        'duplicate' {$outcome.Failure -like '*duplicate registrations*' -and $outcome.RemoteReads -eq 0}
        {$_ -in @('parent-wrong-server','parent-inactive')} {$outcome.Failure -like '*unique active parent*' -and $outcome.RemoteReads -eq 0}
        'remote-error' {$outcome.Failure -eq 'Fixture access denied.'}
        'foreign-target' {$outcome.Failure -like '*configured domain*' -and $outcome.Reads -eq 0 -and $outcome.RemoteReads -eq 0}
    }
    if(-not $ok -or $outcome.Changed -ne $false){throw "Provider readiness regression failed: $scenario; $($outcome | ConvertTo-Json -Depth 5 -Compress)"}
    $checks++
    Write-Host "PASS: SMS Provider readiness $scenario"
}
Write-Host "Passed $checks SMS Provider readiness checks; all native operations mocked."

Remove-Variable SccmProviderFixtureScenario,SccmProviderFixtureReads,SccmProviderFixtureRemoteReads -Scope Global
