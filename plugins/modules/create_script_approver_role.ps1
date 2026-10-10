#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{ type = 'str'; required = $true }
        source_role_name = @{ type = 'str'; required = $false; default = 'Read-only Analyst' }
        site_code = @{ type = 'str'; required = $true }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

Import-Module "C:\\Program Files (x86)\\Microsoft Configuration Manager\\AdminConsole\\bin\\ConfigurationManager.psd1"

if ((Get-PSDrive -Name $module.Params.site_code -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null)
{
    $ProviderMachineName = (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection' -Name Server).Server
    New-PSDrive -Name $module.Params.site_code -PSProvider CMSite -Root $ProviderMachineName
}

Set-Location "$($module.Params.site_code):\"

# Matches Microsoft's documented "Script Approvers" role on the SMS Scripts axis:
# https://learn.microsoft.com/en-us/mem/configmgr/apps/deploy-use/create-deploy-scripts#bkmk_ScriptRoles
# The read surface is broader (Read-only Analyst's full read footprint) because
# Copy-CMSecurityRole inherits the source role's permissions and
# Set-CMSecurityRolePermission does not clear un-named categories. Acceptable for lab.
$scriptApproverPermissions = @{
    "Site"        = "Read"
    "SMS Scripts" = "Read,Approve,Modify"
}

$role = Get-CMSecurityRole -Name $module.Params.name -ErrorAction SilentlyContinue

if (-not $role) {
    Copy-CMSecurityRole -Name $module.Params.name -SourceRoleName $module.Params.source_role_name -Description "SMS Scripts Approve/Modify on top of Read-only Analyst read surface. Lab role for the EXEC-2 attack path."
    $role = Get-CMSecurityRole -Name $module.Params.name
}

# Reconcile the current permission set onto the role every run.
$role | Set-CMSecurityRolePermission -RolePermission $scriptApproverPermissions

$module.ExitJson()
