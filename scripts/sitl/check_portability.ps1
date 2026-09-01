[CmdletBinding()]
param([string]$Distro = 'auto')

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$root = Get-ProjectRoot
$Distro = Get-ProjectDistro -Requested $Distro
$results = Join-Path $root 'results'

$sourceDirectories = @('config','matlab','model','scripts','tests') | ForEach-Object {
    Join-Path $root $_
}
$sourceFiles = @(
    Get-ChildItem -LiteralPath $root -File -Filter '*.m'
    foreach ($directory in $sourceDirectories) {
        Get-ChildItem -LiteralPath $directory -Recurse -File |
            Where-Object { $_.Extension -in @('.m','.ps1','.sh','.json','.conf') }
    }
)

$windowsAbsolute = '(?i)(?<![A-Za-z0-9_])(?:[A-Z]:\\)'
$linuxHome = '(?i)/home/[A-Za-z0-9._-]+/'
$findings = [System.Collections.Generic.List[object]]::new()
foreach ($file in $sourceFiles) {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $lineNumber++
        if ($line -match $windowsAbsolute -or $line -match $linuxHome) {
            $findings.Add([pscustomobject]@{
                File = $file.FullName.Substring($root.Length + 1)
                Line = $lineNumber
                Text = $line.Trim()
            })
        }
    }
}

$wslPath = ConvertTo-ProjectWslPath -WindowsPath $root -Distro $Distro
$wslUser = Get-ProjectWslUser -Distro $Distro
$pathConversionPass = $wslPath -match '^/mnt/[a-z]/' -and $wslPath -match 'UAV_Autotune_v5_4_1_Validation_Fix$'
$userDiscoveryPass = $wslUser -and $wslUser -ne 'root'
$sourceScanPass = $findings.Count -eq 0
$overall = $sourceScanPass -and $pathConversionPass -and $userDiscoveryPass

$findings | Export-Csv -LiteralPath (Join-Path $results 'portability_report.csv') `
    -NoTypeInformation -Encoding UTF8
$evidence = [ordered]@{
    verdict = $(if ($overall) { 'PASS' } else { 'FAIL' })
    source_scan_pass = $sourceScanPass
    hardcoded_path_findings = $findings.Count
    path_conversion_pass = $pathConversionPass
    converted_project_path = $wslPath
    wsl_user_discovery_pass = $userDiscoveryPass
    discovered_wsl_user = $wslUser
    distro = $Distro
    checked_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$evidence | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $results 'portability_verdict.json') -Encoding UTF8
if (-not $overall) { throw 'Portability check failed. See results/portability_report.csv.' }
Write-Output "PORTABILITY_PASS distro=$Distro user=$wslUser path=$wslPath"
