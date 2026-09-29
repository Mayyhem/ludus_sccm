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

if ($module.Params.workstations) {
    foreach ($workstation in $workstations) {
        Invoke-GPUpdate -Computer $workstation.Name -Force -RandomDelayInMinutes 0
    }
}

if ($module.Params.servers) {
    foreach ($server in $servers) {
        Invoke-GPUpdate -Computer $server.Name -Force -RandomDelayInMinutes 0
    }
}

if ($module.Params.domain_controllers) {
    foreach ($domainController in $domainControllers) {
        Invoke-GPUpdate -Computer $domainController.Name -Force -RandomDelayInMinutes 0
    }
}

$module.ExitJson()
