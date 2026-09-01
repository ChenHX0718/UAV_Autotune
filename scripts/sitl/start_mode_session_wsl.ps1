[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('FBWA','AUTOTUNE')][string]$EntryMode,
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][double]$ExitAfterSimSeconds,
    [Parameter(Mandatory)][double]$ScoringStartSimSeconds,
    [Parameter(Mandatory)][double]$ScoringEndSimSeconds,
    [Parameter(Mandatory)][double]$MinimumStartupGuardSeconds,
    [Parameter(Mandatory)][double]$StartupTimeoutWallSeconds,
    [Parameter(Mandatory)][int]$HeartbeatRequiredCount,
    [Parameter(Mandatory)][int]$FdmRequiredCount,
    [Parameter(Mandatory)][int]$AttitudeAlignmentRequiredCount,
    [Parameter(Mandatory)][double]$AttitudeAlignmentRollPitchToleranceDeg,
    [Parameter(Mandatory)][double]$AttitudeAlignmentYawToleranceDeg,
    [Parameter(Mandatory)][int]$ModeRequiredCount,
    [Parameter(Mandatory)][double]$ModeStableSimSeconds,
    [Parameter(Mandatory)][double]$ModeHeartbeatTimeoutWallSeconds,
    [Parameter(Mandatory)][string]$ParameterQueryName,
    [string]$AutotuneAxis = '',
    [string]$Distro = 'auto'
)

. (Join-Path $PSScriptRoot 'lib\common.ps1')
$Distro = Get-ProjectDistro -Requested $Distro
$RunDirectory = (Resolve-Path -LiteralPath $RunDirectory).Path
$root = Get-ProjectRoot
$cfg = Get-ProjectConfig
$wslUser = Get-ProjectWslUser -Distro $Distro
$scriptPath = Join-Path $root 'scripts\wsl\native_autotune_session.py'
$scriptWsl = ConvertTo-ProjectWslPath -WindowsPath $scriptPath -Distro $Distro
$runWsl = ConvertTo-ProjectWslPath -WindowsPath $RunDirectory -Distro $Distro
$port = [int]$cfg.network.wsl_local_control_udp_port
$entryOutput = $runWsl.TrimEnd('/') + '/mode_entry.json'
$preconditionOutput = $runWsl.TrimEnd('/') + '/mode_precondition.json'
$exitOutput = $runWsl.TrimEnd('/') + '/mode_exit.json'
$sessionOutput = $runWsl.TrimEnd('/') + '/mode_session.json'
$traceFile = $runWsl.TrimEnd('/') + '/packet_trace.csv'
$feedbackFile = $runWsl.TrimEnd('/') + '/feedback_trace.csv'
$abortFile = $runWsl.TrimEnd('/') + '/safety_abort.json'
$sitlReadyOutput = $runWsl.TrimEnd('/') + '/sitl_ready.json'
$fbwaReadyOutput = $runWsl.TrimEnd('/') + '/fbwa_ready.json'
$modeReadyOutput = $runWsl.TrimEnd('/') + '/mode_ready.json'
$modeDropoutOutput = $runWsl.TrimEnd('/') + '/mode_dropout.json'
$liveAuditOutput = $runWsl.TrimEnd('/') + '/live_mode_audit.json'
$officialFinishedOutput = $runWsl.TrimEnd('/') + '/official_finished.json'

$script = @"
set -euo pipefail
source "`$HOME/venv-ardupilot/bin/activate"
exec python $(Quote-ProjectBash $scriptWsl) \
  --port $(Quote-ProjectBash ([string]$port)) \
  --entry-mode $(Quote-ProjectBash $EntryMode) \
  --precondition-output $(Quote-ProjectBash $preconditionOutput) \
  --entry-output $(Quote-ProjectBash $entryOutput) \
  --exit-output $(Quote-ProjectBash $exitOutput) \
  --session-output $(Quote-ProjectBash $sessionOutput) \
  --trace-file $(Quote-ProjectBash $traceFile) \
  --feedback-file $(Quote-ProjectBash $feedbackFile) \
  --abort-file $(Quote-ProjectBash $abortFile) \
  --sitl-ready-output $(Quote-ProjectBash $sitlReadyOutput) \
  --fbwa-ready-output $(Quote-ProjectBash $fbwaReadyOutput) \
  --mode-ready-output $(Quote-ProjectBash $modeReadyOutput) \
  --mode-dropout-output $(Quote-ProjectBash $modeDropoutOutput) \
  --live-audit-output $(Quote-ProjectBash $liveAuditOutput) \
  --official-finished-output $(Quote-ProjectBash $officialFinishedOutput) \
  --autotune-axis $(Quote-ProjectBash $AutotuneAxis) \
  --exit-after-sim-seconds $(Quote-ProjectBash ([string]$ExitAfterSimSeconds)) \
  --scoring-start-sim-seconds $(Quote-ProjectBash ([string]$ScoringStartSimSeconds)) \
  --scoring-end-sim-seconds $(Quote-ProjectBash ([string]$ScoringEndSimSeconds)) \
  --minimum-startup-guard-seconds $(Quote-ProjectBash ([string]$MinimumStartupGuardSeconds)) \
  --startup-timeout-wall-seconds $(Quote-ProjectBash ([string]$StartupTimeoutWallSeconds)) \
  --heartbeat-required-count $(Quote-ProjectBash ([string]$HeartbeatRequiredCount)) \
  --fdm-required-count $(Quote-ProjectBash ([string]$FdmRequiredCount)) \
  --attitude-alignment-required-count $(Quote-ProjectBash ([string]$AttitudeAlignmentRequiredCount)) \
  --attitude-alignment-roll-pitch-tolerance-deg $(Quote-ProjectBash ([string]$AttitudeAlignmentRollPitchToleranceDeg)) \
  --attitude-alignment-yaw-tolerance-deg $(Quote-ProjectBash ([string]$AttitudeAlignmentYawToleranceDeg)) \
  --mode-required-count $(Quote-ProjectBash ([string]$ModeRequiredCount)) \
  --mode-stable-sim-seconds $(Quote-ProjectBash ([string]$ModeStableSimSeconds)) \
  --mode-heartbeat-timeout-wall-seconds $(Quote-ProjectBash ([string]$ModeHeartbeatTimeoutWallSeconds)) \
  --parameter-query-name $(Quote-ProjectBash $ParameterQueryName)
"@
$bytes = [System.Text.Encoding]::UTF8.GetBytes($script)
$encoded = [System.Convert]::ToBase64String($bytes)
$transport = "printf %s $encoded | base64 --decode | bash -s"
$processArgs = @('-d',$Distro,'-u',$wslUser,'--','bash','-lc',('"' + $transport + '"'))
$stdoutPath = Join-Path $RunDirectory 'mode_session_stdout.log'
$stderrPath = Join-Path $RunDirectory 'mode_session_stderr.log'
$process = Start-Process -FilePath wsl.exe -ArgumentList $processArgs `
    -WindowStyle Hidden -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -PassThru
if ($null -eq $process) { throw 'Failed to start the native mode session.' }
Set-Content -LiteralPath (Join-Path $RunDirectory 'mode_session_host.pid') `
    -Value ([string]$process.Id) -Encoding ASCII
[pscustomobject]@{
    State = 'STARTED'
    EntryMode = $EntryMode
    ExitAfterSimSeconds = $ExitAfterSimSeconds
    ScoringStartSimSeconds = $ScoringStartSimSeconds
    ScoringEndSimSeconds = $ScoringEndSimSeconds
    WindowsHostPid = $process.Id
}
