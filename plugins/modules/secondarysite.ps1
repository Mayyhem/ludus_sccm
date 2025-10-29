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
    $ProviderMachineName = (Get-ItemProperty 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection' -Name Server).Server
    New-PSDrive -Name $module.Params.site_code -PSProvider CMSite -Root $ProviderMachineName
}

Set-Location "$($module.Params.site_code):\"

$certExpiry = [DateTime]::UtcNow.AddYears(2)

# Idempotency: Check if a secondary site already exists for this site code or server name
$ns = "root\SMS\site_$($module.Params.parent_site_code)"
$secondaryExists = $false
try {
    $secByCode = Get-WmiObject -Namespace $ns -Class SMS_Site -Filter ("SiteCode='{0}'" -f $module.Params.site_code) -ErrorAction Stop
    if ($secByCode) { $secondaryExists = $true }
} catch { }

if (-not $secondaryExists) {
    try {
        $server = $module.Params.sitesystem_name
        $short = ($server -split '\.')[0]
        $sites = Get-WmiObject -Namespace $ns -Class SMS_Site -ErrorAction Stop
        foreach ($s in ($sites | Where-Object { $_ })) {
            if (($s.ServerName -ieq $server) -or ($s.ServerName -ieq $short)) {
                # SMS_Site.Type: 2 is Secondary Site
                if ($s.Type -eq 2) { $secondaryExists = $true; break }
            }
        }
    } catch { }
}

if ($secondaryExists) {
    # Already installed, exit without attempting creation
    return
}

$SQLServerSettings = New-CMSqlServerSetting -CopySqlServerExpressOnSecondarySite
$InstallFiles = New-CMInstallationSourceFile -CopyFromParentSiteServer
New-CMSecondarySite -CertificateExpirationTimeUtc $certExpiry -CreateSelfSignedCertificate -Http -InstallationSourceFile $InstallFiles -InstallInternetServer $True -PrimarySiteCode $($module.Params.parent_site_code) -ServerName $($module.Params.sitesystem_name) -SecondarySiteCode $($module.Params.site_code) -SiteName "Secondary Site" -SqlServerSetting $SQLServerSettings