# Integration check: run as an SCCM administrator on one explicitly selected
# site server. Creates only small fixtures below C:\ludus\sccm\offline-checks.
param([Parameter(Mandatory)][string]$SiteCode, [Parameter(Mandatory)][string]$Provider)
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '../../roles/sccm_common/files/SccmDeployment.psm1'
Import-Module $modulePath -Force
$directory = 'C:\ludus\sccm\offline-checks\filesystem-context'
$source = "$directory\source"
$destination = "$directory\destination"
[void][IO.Directory]::CreateDirectory($source)
[void][IO.Directory]::CreateDirectory($destination)
[IO.File]::WriteAllText("$source\fixture [literal].txt", 'SCCM filesystem regression fixture')
$uncSource = ConvertTo-SccmAdminShare $Provider $source
$uncDestination = ConvertTo-SccmAdminShare $Provider $destination
Connect-SccmSite $SiteCode $Provider
$before = (Get-Location).Path
try {
    Copy-SccmFile -Path "$uncSource\*" -Destination $destination -Recurse
    Copy-SccmFile -LiteralPath "$source\fixture [literal].txt" -Destination "$uncDestination\literal-copy.txt"
    Copy-SccmFile -LiteralPath "$uncSource\fixture [literal].txt" -Destination "$uncDestination\unc-copy.txt"
    foreach ($name in @('fixture [literal].txt', 'literal-copy.txt', 'unc-copy.txt')) {
        if ([IO.File]::ReadAllText("$destination\$name") -ne 'SCCM filesystem regression fixture') {
            throw "File contents were not preserved: $name"
        }
    }
    if ((Get-Location).Path -ne $before -or (Get-Location).Provider.Name -ne 'CMSite') {
        throw 'Filesystem transfers changed the current SCCM drive.'
    }
    Write-Output 'Passed 3 filesystem copy variants from the real CMSite provider; contents and drive context preserved.'
} finally {
    Set-Location $env:SystemDrive\
}
