#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{ type = 'str'; required = $true }
        site_code = @{ type = 'str'; required = $true }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

Import-Module "C:\\Program Files (x86)\\Microsoft Configuration Manager\\AdminConsole\\bin\\ConfigurationManager.psd1"

#https://www.windows-noob.com/forums/topic/16422-connect-configmgr64-function-to-connect-to-cmsite-sccm-feedback-for-improvement/
if ((Get-PSDrive -Name $module.Params.site_code -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null)
{
    $ProviderMachineName = (Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\ConfigMgr10\AdminUI\Connection -Name Server).Server
    New-PSDrive -Name $module.Params.site_code -PSProvider CMSite -Root $ProviderMachineName 
}

Set-Location "$($module.Params.site_code):\"

# Query for NAA Account (handle multiple returned instances)
# https://www.oscc.be/sccm/configmgr/powershell/naa/Set-NAA-using-Powershell-in-CB/
$components = Get-WmiObject -Class SMS_SCI_ClientComp -Namespace "root\sms\site_$($module.Params.site_code)" | Where-Object { $_.ItemName -eq "Software Distribution" }

if (-not $components) {
    $module.FailJson("Could not find 'Software Distribution' client component in WMI")
}

# Prefer a component that already has the 'Network Access User Names' property list; otherwise take the first
if ($components -is [System.Array]) {
    $component = $components | Where-Object { $_.PropLists -and ($_.PropLists | Where-Object { $_.PropertyListName -eq "Network Access User Names" }) } | Select-Object -First 1
    if (-not $component) { $component = $components | Select-Object -First 1 }
} else {
    $component = $components
}

$props = $component.PropLists
$prop = $null
if ($props) {
    $prop = $props | Where-Object { $_.PropertyListName -eq "Network Access User Names" }
}


# Make CMAccount Network Access Account or Exit if Exists
if ($prop -and ($prop.Values -contains $module.Params.name)) {
    $module.ExitJson()
} else {
    # Create or update the embedded property list without dropping other PropLists
    $new = [WmiClass] "root\sms\site_$($module.Params.site_code):SMS_EmbeddedPropertyList"
    $embeddedpropertylist = $new.CreateInstance()
    $embeddedpropertylist.PropertyListName = "Network Access User Names"
    $embeddedpropertylist.Values = @($module.Params.name)

    $updatedPropLists = @()
    if ($props) {
        # Keep existing lists except the one we're replacing
        $updatedPropLists += ($props | Where-Object { $_.PropertyListName -ne "Network Access User Names" })
    }
    # Add (or replace with) our desired list
    $updatedPropLists += $embeddedpropertylist

    $component.PropLists = $updatedPropLists
    $component.Put() | Out-Null
    $module.ExitJson()
}
