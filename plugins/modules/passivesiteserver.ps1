#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
	    move_contentlib_to = @{ type = 'str'; required = $true }
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

#https://github.com/vinaypamnani-msft/memlabs/blob/0d90a7fb968c864ed2e5391606b103f5b520e2e2/vmbuild/DSC/phases/InstallPassiveSiteServer.ps1
Move-CMContentLibrary -NewLocation $module.Params.move_contentlib_to -SiteCode $module.Params.site_code

$i = 0
$lastMoveProgress = 0
do {
    $moveStatus = Get-CMSite -SiteCode $site_code
    $moveProgress = $moveStatus.ContentLibraryMoveProgress

    if ($lastMoveProgress -eq $moveProgress) {
        $i++
    }
    else {
        $i = 0
    }

    if ($i -gt 120) {
        # Bail after progress hasn't change for 60 minutes (30 seconds * 120)
        $bailOut = $true
        break
    }

    Start-Sleep -Seconds 30
    Write-Host "Moving Content Library to $move_contentlib_to, Current Progress: $moveProgress%" -RetrySeconds 30

    if ($moveStatus.ContentLibraryStatus -eq 3) {
        Write-Host "Content Library Location empty after move. Retrying Content Library Move"
        Move-CMContentLibrary -NewLocation $move_contentlib_to -SiteCode $site_code -Verbose
    }

    $lastMoveProgress = $moveStatus.ContentLibraryMoveProgress

} until ($moveProgress -eq 100 -and (-not [string]::IsNullOrWhitespace($moveStatus.ContentLibraryLocation)))
if ($bailOut) {
    Write-Host "Gave up after 1 hour on Content Library move after move progress stalled at $moveProgress%. Exiting." -Failure
    return
}
else {
    Write-Host "Content Library moved to $($moveStatus.ContentLibraryLocation)"
}

$InstallPath = "C:\Program Files\Microsoft Configuration Manager"
New-CMSiteSystemServer -SiteCode $module.Params.site_code -SiteSystemServerName $module.Params.sitesystem_name
Add-CMPassiveSite -SiteCode $module.Params.site_code -SiteSystemServerName $module.Params.sitesystem_name -InstallDirectory $InstallPath -SourceFilePathOption CopySourceFileFromActiveSite