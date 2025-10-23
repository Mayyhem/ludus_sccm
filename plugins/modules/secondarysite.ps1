#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        parent_site_code = @{ type = 'str'; required = $true }
        sitesystem_name = @{ type = 'str'; required = $true }
        site_code = @{ type = 'str'; required = $true }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"

#https://www.windows-noob.com/forums/topic/16422-connect-configmgr64-function-to-connect-to-cmsite-sccm-feedback-for-improvement/
if ((Get-PSDrive -Name $module.Params.site_code -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null)
{
    $ProviderMachineName = (Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection -Name Server).Server
    New-PSDrive -Name $module.Params.site_code -PSProvider CMSite -Root $ProviderMachineName
}

Set-Location "$($module.Params.site_code):\"

$SQLServerSettings = New-CMSqlServerSetting -CopySqlServerExpressOnSecondarySite
$InstallFiles = New-CMInstallationSourceFile -CopyFromParentSiteServer
New-CMSecondarySite -CertificateExpirationTimeUtc "1/1/2028 12:00 AM" -CreateSelfSignedCertificate -Http -InstallationSourceFile $InstallFiles -InstallInternetServer $True -PrimarySiteCode $parent_site_code -ServerName $sitesystem_name -SecondarySiteCode $site_code -SiteName "Secondary Site" -SqlServerSetting $SQLServerSettings