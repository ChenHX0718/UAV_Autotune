[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][string]$DefaultsFile,
    [string]$Distro = 'auto',
    [double]$Speedup = 1,
    [int]$RateHz = 50,
    [string]$WindowsHostAddress = ''
)

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$cfg = Get-ProjectConfig
$Distro = Get-ProjectDistro -Requested $Distro
$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$DefaultsFile = (Resolve-Path -LiteralPath $DefaultsFile).Path
$runWsl = ConvertTo-ProjectWslPath -WindowsPath $RunDirectory -Distro $Distro
$defaultsWsl = ConvertTo-ProjectWslPath -WindowsPath $DefaultsFile -Distro $Distro
if (-not $WindowsHostAddress) { $WindowsHostAddress = Get-ProjectWindowsHostAddress -Distro $Distro }

$repoName = [string]$cfg.wsl.repo_name
$wslUser = Get-ProjectWslUser -Distro $Distro
$binaryRelative = [string]$cfg.ardupilot.binary_relative_path
$commit = [string]$cfg.ardupilot.commit
$mpPort = [int]$cfg.network.mission_planner_udp_port
$headlessPort = [int]$cfg.network.headless_mavlink_udp_port
$localControlPort = [int]$cfg.network.wsl_local_control_udp_port
$homeConfig = $cfg.home
$homeText = '{0:F8},{1:F8},{2:F3},{3:F3}' -f $homeConfig.latitude_deg,$homeConfig.longitude_deg,$homeConfig.altitude_m,$homeConfig.yaw_deg

$preflightScript = @"
set -euo pipefail
repo="`$HOME/$repoName"
binary="`$repo/$binaryRelative"
test -x "`$binary"
test "`$(cd "`$repo" && git rev-parse HEAD)" = $(Quote-ProjectBash $commit)
cd $(Quote-ProjectBash $runWsl)
if [ -s sitl.pid ] && kill -0 "`$(cat sitl.pid)" 2>/dev/null; then
  echo 'SITL is already running for this run directory.' >&2
  exit 2
fi
"@
Invoke-ProjectWslBash -Distro $Distro -User $wslUser -Script $preflightScript

# Keep wsl.exe alive for the entire SITL lifetime. A Linux process placed in
# the background of a short-lived wsl.exe invocation can be reaped when that
# host invocation closes, even when nohup is used. Here ArduPlane remains the
# foreground process of a hidden Windows-side WSL host.
$launchScript = @"
set -euo pipefail
repo="`$HOME/$repoName"
binary="`$repo/$binaryRelative"
cd $(Quote-ProjectBash $runWsl)
actual_commit="`$(cd "`$repo" && git rev-parse HEAD)"
binary_sha256="`$(sha256sum "`$binary" | awk '{print `$1}')"
ubuntu_version="`$(. /etc/os-release && printf %s "`$VERSION_ID")"
started_utc="`$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"backend":"WSL2","firmware_source":"source_build","distro":"%s","ubuntu_version":"%s","user":"%s","commit":"%s","binary":"%s","binary_sha256":"%s","started_utc":"%s"}\n' \
  $(Quote-ProjectBash $Distro) "`$ubuntu_version" $(Quote-ProjectBash $wslUser) \
  "`$actual_commit" "`$binary" "`$binary_sha256" "`$started_utc" > wsl_launch_evidence.json
printf '{"state":"STARTING","windows_host":"%s"}\n' $(Quote-ProjectBash $WindowsHostAddress) > sitl_status.json
echo "`$`$" > sitl.pid
printf '{"state":"WAITING_FOR_SITL","pid":%s,"windows_host":"%s"}\n' "`$`$" $(Quote-ProjectBash $WindowsHostAddress) > sitl_status.json
exec "`$binary" \
  --model $(Quote-ProjectBash "JSON:$WindowsHostAddress") \
  --speedup $(Quote-ProjectBash ([string]$Speedup)) \
  --rate $(Quote-ProjectBash ([string]$RateHz)) \
  --serial0 $(Quote-ProjectBash "udpclient:$WindowsHostAddress`:$mpPort") \
  --serial1 $(Quote-ProjectBash "udpclient:$WindowsHostAddress`:$headlessPort") \
  --serial2 $(Quote-ProjectBash "udpclient:127.0.0.1`:$localControlPort") \
  --defaults $(Quote-ProjectBash $defaultsWsl) \
  --home $(Quote-ProjectBash $homeText) --wipe > sitl_console.log 2>&1 < /dev/null
"@

$bytes = [System.Text.Encoding]::UTF8.GetBytes($launchScript)
$encoded = [System.Convert]::ToBase64String($bytes)
$transport = "printf %s $encoded | base64 --decode | bash -s"
$processArgs = @('-d',$Distro,'-u',$wslUser,'--','bash','-lc', `
    ('"' + $transport + '"'))
$hostProcess = Start-Process -FilePath wsl.exe -ArgumentList $processArgs `
    -WindowStyle Hidden -PassThru
if ($null -eq $hostProcess) { throw 'Failed to start the Windows WSL host process.' }
Set-Content -LiteralPath (Join-Path $RunDirectory 'wsl_host.pid') `
    -Value ([string]$hostProcess.Id) -Encoding ASCII

$pidFile = Join-Path $RunDirectory 'sitl.pid'
$statusFile = Join-Path $RunDirectory 'sitl_status.json'
$started = $false
for ($attempt = 1; $attempt -le 100; $attempt++) {
    if ($hostProcess.HasExited) {
        $detail = ''
        $console = Join-Path $RunDirectory 'sitl_console.log'
        if (Test-Path -LiteralPath $console) {
            $detail = (Get-Content -LiteralPath $console -Tail 80 | Out-String).Trim()
        }
        throw "ArduPlane WSL host exited during startup. $detail"
    }
    if ((Test-Path -LiteralPath $pidFile) -and `
            (Test-Path -LiteralPath $statusFile)) {
        $linuxPid = (Get-Content -Raw -LiteralPath $pidFile).Trim()
        if ($linuxPid -match '^\d+$') {
            $started = $true
            break
        }
    }
    Start-Sleep -Milliseconds 100
}
if (-not $started) {
    try { $hostProcess.Kill() } catch {}
    throw 'Timed out waiting for the ArduPlane WSL process identity.'
}
Write-Output "SITL_PROCESS_PASS pid=$linuxPid wsl_host_pid=$($hostProcess.Id) host=$WindowsHostAddress"
