#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{ type = 'str'; required = $true }
        role_name = @{ type = 'str'; required = $true }
        site_code = @{ type = 'str'; required = $true }
        security_scope_name = @{ type = 'str'; required = $false; default = 'All' }
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

$adminUser = Get-CMAdministrativeUser -Name $module.Params.name -ErrorAction SilentlyContinue

if (-not $adminUser) {
    New-CMAdministrativeUser -Name $module.Params.name -RoleName $module.Params.role_name -SecurityScopeName $module.Params.security_scope_name
    $module.ExitJson()
} elseif ($adminUser.RoleNames -notcontains $module.Params.role_name) {
    Add-CMSecurityRoleToAdministrativeUser -AdministrativeUserName $module.Params.name -RoleName $module.Params.role_name
    $module.ExitJson()
} else {
    $module.ExitJson()
}
