#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        workstations = @{ type = 'bool'; required = $true }
        servers = @{ type = 'bool'; required = $true }
        domain_controllers = @{ type = 'bool'; required = $true }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

Import-Module ActiveDirectory

$domainInfo = Get-ADDomain

# Define the search base where servers/workstations live. These are the
# conventional Ludus OU paths; if the caller of this collection is not
# running under Ludus and those OUs don't exist yet, gracefully skip
# rather than crashing with "Directory object not found".
$serversOU = "OU=servers," + $domainInfo.DistinguishedName
$workstationsOU = "OU=Workstations," + $domainInfo.DistinguishedName

function Get-ComputersInOU {
    param([string]$SearchBase)
    try {
        Get-ADComputer -Filter * -SearchBase $SearchBase -ErrorAction Stop
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        # OU doesn't exist — return empty so the loop below is a no-op.
        @()
    } catch {
        # Any other AD error is worth surfacing.
        throw
    }
}

$servers = Get-ComputersInOU -SearchBase $serversOU
$workstations = Get-ComputersInOU -SearchBase $workstationsOU
$domainControllers = Get-ADDomainController -Filter *

function Invoke-ComputerPolicyRefresh {
    param(
        [string]$Computer,
        [scriptblock]$Command = {
            $output = & "$env:SystemRoot\System32\gpupdate.exe" /target:computer /force /wait:120 2>&1 | Out-String
            [pscustomobject]@{Computer = $env:COMPUTERNAME; ExitCode = $LASTEXITCODE; Output = $output}
        }
    )
    if (($Computer -split '\.')[0] -ieq $env:COMPUTERNAME) {
        $result = & $Command
    } else {
        $result = Invoke-Command -ComputerName $Computer -ScriptBlock $Command -ErrorAction Stop
    }
    if ($result.ExitCode -ne 0) { throw "Computer policy refresh on $Computer failed with exit code $($result.ExitCode): $($result.Output)" }
    return $result
}

$targets = @()
if ($module.Params.workstations) {
    $targets += @($workstations | ForEach-Object { if ($_.DNSHostName) { $_.DNSHostName } else { $_.Name } })
}
if ($module.Params.servers) {
    $targets += @($servers | ForEach-Object { if ($_.DNSHostName) { $_.DNSHostName } else { $_.Name } })
}
if ($module.Params.domain_controllers) {
    $targets += @($domainControllers | ForEach-Object { if ($_.HostName) { $_.HostName } else { $_.Name } })
}
$targets = @($targets | Sort-Object -Unique)
$module.Result.targets = $targets
$module.Result.results = @()
$module.Result.changed = $false
if ($module.CheckMode) { $module.ExitJson(); return }

foreach ($computer in $targets) {
    try {
        $module.Result.results += Invoke-ComputerPolicyRefresh $computer
        $module.Result.changed = $true
    } catch {
        $module.FailJson("Cannot refresh computer policy on ${computer}: $($_.Exception.Message)", $_)
    }
}

$module.ExitJson()
