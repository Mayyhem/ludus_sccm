[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SiteServer,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9]{3}$')][string]$SiteCode,
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][string]$Domain
)
$ErrorActionPreference = 'Stop'
$Ansible.Changed = $false
$hostPattern = '^[A-Za-z0-9][A-Za-z0-9-]*\.' + [regex]::Escape($Domain) + '$'
if ($SiteServer -notmatch $hostPattern -or $Target -notmatch $hostPattern) {
    throw 'The site server and SMS Provider must be explicit computers in the configured domain.'
}
$parent = @(Get-CimInstance -ComputerName $SiteServer -Namespace "root\SMS\site_$SiteCode" -ClassName SMS_Site -Filter "SiteCode='$SiteCode'" -ErrorAction Stop)
if ($parent.Count -ne 1 -or $parent[0].Status -ne 1 -or $parent[0].Type -notin @(2,4) -or
    ([string]$parent[0].ServerName -split '\.')[0] -ine ($SiteServer -split '\.')[0]) {
    throw 'No unique active parent site matches the configured site server.'
}
$expected = [version]$parent[0].Version
$locations = @(Get-CimInstance -ComputerName $SiteServer -Namespace root\SMS -ClassName SMS_ProviderLocation -ErrorAction Stop |
    Where-Object { $_.SiteCode -ieq $SiteCode -and ($_.Machine -ieq $Target -or $_.Machine -ieq ($Target -split '\.')[0]) })
if ($locations.Count -gt 1) { throw 'The parent reports duplicate registrations for the requested SMS Provider.' }
$probe = Invoke-Command -ComputerName $Target -ErrorAction Stop -ArgumentList $SiteCode -ScriptBlock {
    param($Code)
    $ErrorActionPreference = 'Stop'
    $state = @{Computer=$env:COMPUTERNAME;Domain=(Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Domain;
        NamespaceExists=$false;OtherSites=@();Version='';Build=0;SiteServer='';SiteRows=0;
        AdkDeploymentTools=$false;InstallerActive=$false}
    $dism = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe'
    $state.AdkDeploymentTools = Test-Path -LiteralPath $dism -PathType Leaf
    $state.InstallerActive = @(Get-Process setup,setupwpf,ccmsetup -ErrorAction SilentlyContinue).Count -gt 0 -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\InProgress')
    $root = @(Get-CimInstance -Namespace root -ClassName __Namespace -Filter "Name='SMS'" -ErrorAction Stop)
    if ($root.Count) {
        $namespaces = @(Get-CimInstance -Namespace root\SMS -ClassName __Namespace -ErrorAction Stop)
        $state.OtherSites = @($namespaces | Where-Object { $_.Name -like 'site_*' -and $_.Name -ine "site_$Code" } | ForEach-Object Name)
        $state.NamespaceExists = @($namespaces | Where-Object Name -eq "site_$Code").Count -eq 1
        if ($state.NamespaceExists) {
            $identification = @(Get-CimInstance -Namespace "root\SMS\site_$Code" -ClassName SMS_Identification -ErrorAction Stop)
            $site = @(Get-CimInstance -Namespace "root\SMS\site_$Code" -ClassName SMS_Site -Filter "SiteCode='$Code'" -ErrorAction Stop)
            if ($identification.Count -eq 1 -and $site.Count -eq 1) {
                $state.Build = [int]$identification[0].SMSBuildNumber
                $state.Version = [string]$site[0].Version
                $state.SiteServer = [string]$site[0].ServerName
            }
            $state.SiteRows = $site.Count
        }
    }
    return $state
}
if ($probe.Computer -ine ($Target -split '\.')[0] -or $probe.Domain -ine $Domain) {
    throw 'The SMS Provider probe reached a different computer or domain.'
}
$registered = $locations.Count -eq 1
$ready = $registered -and $probe.NamespaceExists -and $probe.SiteRows -eq 1 -and
    $probe.Build -eq $expected.Build -and [version]$probe.Version -eq $expected -and
    ([string]$probe.SiteServer -split '\.')[0] -ieq ($SiteServer -split '\.')[0] -and
    @($probe.OtherSites).Count -eq 0
$canInstall = -not $registered -and -not $probe.NamespaceExists -and @($probe.OtherSites).Count -eq 0 -and
    $probe.AdkDeploymentTools -and -not $probe.InstallerActive
$Ansible.Result = @{Computer=$Target;Site=$SiteCode;Registered=$registered;Ready=$ready;CanInstall=$canInstall;
    NamespaceExists=$probe.NamespaceExists;Version=$probe.Version;ExpectedVersion=[string]$expected;
    AdkDeploymentTools=$probe.AdkDeploymentTools;InstallerActive=$probe.InstallerActive;OtherSites=@($probe.OtherSites)}
