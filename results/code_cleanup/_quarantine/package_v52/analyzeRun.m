function result = analyzeRun(runDir,cfg,simulationPass,simulationError, ...
    dataFlashPass,dataFlashDetail,parameterReadback)
%ANALYZERUN Layered V5.2 acceptance: infrastructure through response.
arguments
    runDir (1,1) string
    cfg struct
    simulationPass (1,1) logical
    simulationError (1,1) string
    dataFlashPass (1,1) logical
    dataFlashDetail (1,1) string
    parameterReadback table
end

result = struct;
result.run_directory = runDir;
result.simulation_error = simulationError;
result.dataflash_detail = dataFlashDetail;
result.ardupilot_commit_expected = string(cfg.project.ardupilot.commit);
parameterPass = ~isempty(parameterReadback) && all(parameterReadback.Pass);

[infrastructurePass,infrastructureMetrics] = infrastructureEvidence(runDir,cfg);
result.infrastructure = passFail(infrastructurePass);
result.infrastructure_metrics = infrastructureMetrics;

[communicationPass,communicationMetrics] = communicationEvidence(runDir,cfg);
result.communication = passFail(simulationPass && communicationPass && ...
    dataFlashPass && parameterPass);
result.communication_metrics = communicationMetrics;
result.parameter_readback = passFail(parameterPass);

mapping = table;
mappingPass = false;
mappingMetrics = emptyMappingMetrics();
if simulationPass && dataFlashPass
    [mapping,mappingMetrics] = commandMappingEvidence(runDir,cfg);
    mappingPass = ~isempty(mapping) && all(mapping.Pass);
end
if ~isempty(mapping), writetable(mapping,fullfile(runDir,"command_mapping.csv")); end
result.command_mapping = passFail(mappingPass);
result.mapping_metrics = mappingMetrics;

[safetyPass,~,dynamicMetrics] = dynamicEvidence(runDir,cfg);
[signDetails,signPass] = signChainEvidence(runDir,cfg,mapping);
if ~isempty(signDetails)
    writetable(signDetails,fullfile(runDir,"sign_test.csv"));
end
[plateauResponse,plateauPass] = plateauResponseEvidence(runDir,cfg);
if ~isempty(plateauResponse)
    writetable(plateauResponse,fullfile(runDir,"plateau_response.csv"));
end
result.sign_test = passFail(signPass);
result.dynamics_sanity = passFail(safetyPass);
result.safety = passFail(safetyPass);
controlPass = dynamicMetrics.valid && ...
    dynamicMetrics.overshoot_percent <= double(cfg.scenario.max_overshoot_percent) && ...
    dynamicMetrics.settling_time_s <= double(cfg.scenario.max_settling_time_s) && ...
    abs(dynamicMetrics.steady_state_error_deg) <= ...
        double(cfg.scenario.max_steady_state_error_deg) && ...
    dynamicMetrics.pwm_saturation_fraction <= ...
        double(cfg.scenario.max_pwm_saturation_fraction) && ...
    dynamicMetrics.surface_saturation_fraction <= ...
        double(cfg.scenario.max_pwm_saturation_fraction) && ...
    dynamicMetrics.rate_saturation_fraction == 0;
result.control_response = passFail(controlPass);
result.dynamic_metrics = dynamicMetrics;
result.plateau_response = passFail(plateauPass);

writeTimeAlignment(runDir,mappingMetrics);

required = [result.infrastructure,result.communication, ...
    result.parameter_readback,result.command_mapping,result.sign_test, ...
    result.dynamics_sanity,result.safety,result.control_response];
result.overall = passFail(all(required == "PASS"));
writeOutputs(runDir,result,mapping,cfg);
end

function [pass,metrics] = infrastructureEvidence(runDir,cfg)
metrics = struct("backend","","firmware_source","","distro","", ...
    "ubuntu_version","","commit","","binary","", ...
    "binary_sha256","","source_build_verified",false);
file = fullfile(runDir,"wsl_launch_evidence.json");
if ~isfile(file), pass = false; return; end
try
    evidence = jsondecode(fileread(file));
    metrics.backend = string(evidence.backend);
    metrics.firmware_source = string(evidence.firmware_source);
    metrics.distro = string(evidence.distro);
    metrics.ubuntu_version = string(evidence.ubuntu_version);
    metrics.commit = string(evidence.commit);
    metrics.binary = string(evidence.binary);
    metrics.binary_sha256 = string(evidence.binary_sha256);
    metrics.source_build_verified = metrics.backend == "WSL2" && ...
        metrics.firmware_source == "source_build" && ...
        metrics.commit == string(cfg.project.ardupilot.commit) && ...
        strlength(metrics.binary_sha256) == 64;
    pass = metrics.source_build_verified;
catch
    pass = false;
end
end

function [pass,metrics] = communicationEvidence(runDir,cfg)
metrics = struct("rx_packets",0,"tx_packets",0,"dropped_packets",inf, ...
    "duplicate_packets",0,"invalid_packets",inf,"frame_rate_hz",NaN, ...
    "mean_rtt_ms",NaN, ...
    "p95_rtt_ms",NaN,"max_rtt_ms",NaN,"startup_max_rtt_ms",NaN, ...
    "mean_packet_interval_ms",NaN,"p95_packet_interval_ms",NaN, ...
    "max_packet_interval_ms",NaN,"packet_interval_std_ms",NaN, ...
    "simulation_packet_interval_ms",NaN,"warmup_excluded_s",1);
summaryFile = fullfile(runDir,"adapter_summary.json");
traceFile = fullfile(runDir,"packet_trace.csv");
if ~isfile(summaryFile) || ~isfile(traceFile), pass = false; return; end
summary = jsondecode(fileread(summaryFile));
metrics.rx_packets = double(summary.rx_packets);
metrics.tx_packets = double(summary.tx_packets);
metrics.dropped_packets = double(summary.dropped_packets);
if isfield(summary,"duplicate_packets")
    metrics.duplicate_packets = double(summary.duplicate_packets);
end
metrics.invalid_packets = double(summary.invalid_packets);
metrics.frame_rate_hz = double(summary.last_frame_rate_hz);
trace = readtable(traceFile);
allRtt = trace.round_trip_ms(isfinite(trace.round_trip_ms));
operational = trace.sim_time_s >= metrics.warmup_excluded_s;
rtt = trace.round_trip_ms(operational & isfinite(trace.round_trip_ms));
interval = trace.packet_interval_ms(operational & isfinite(trace.packet_interval_ms));
if ~isempty(allRtt), metrics.startup_max_rtt_ms = max(allRtt); end
if ~isempty(rtt)
    metrics.mean_rtt_ms = mean(rtt);
    metrics.p95_rtt_ms = percentile(rtt,95);
    metrics.max_rtt_ms = max(rtt);
end
if ~isempty(interval)
    metrics.mean_packet_interval_ms = mean(interval);
    metrics.p95_packet_interval_ms = percentile(interval,95);
    metrics.max_packet_interval_ms = max(interval);
    metrics.packet_interval_std_ms = std(interval);
end
if height(trace) > 1
    metrics.simulation_packet_interval_ms = median(diff(trace.sim_time_s))*1000;
end
minimumPackets = 0.8*double(cfg.scenario.stop_time_s)* ...
    double(cfg.project.timing.sitl_rate_hz);
pass = metrics.rx_packets >= minimumPackets && ...
    metrics.tx_packets >= 0.8*minimumPackets && ...
    metrics.dropped_packets <= double(cfg.simulation.packet_loss_fail_threshold) && ...
    metrics.invalid_packets == 0 && ...
    all(diff(trace.frame_count) > 0) && ...
    all(diff(trace.packet_timestamp_s) > 0) && ...
    abs(metrics.frame_rate_hz-double(cfg.project.timing.sitl_rate_hz)) < 0.5 && ...
    isfinite(metrics.max_rtt_ms) && ...
    metrics.max_rtt_ms <= double(cfg.simulation.max_rtt_fail_ms);
end

function [mapping,metrics] = commandMappingEvidence(runDir,cfg)
simulation = readtable(fullfile(runDir,"simulation_data.csv"));
att = readtable(fullfile(runDir,"internal_ATT.csv"));
rcin = readtable(fullfile(runDir,"internal_RCIN.csv"));
trace = readtable(fullfile(runDir,"packet_trace.csv"));
axisName = lower(string(cfg.scenario.axis));
if axisName == "roll"
    external = simulation.external_roll_target_deg;
    desiredName = "DesRoll";
    rcName = "C1";
    traceRcName = "rc1";
else
    external = simulation.external_pitch_target_deg;
    desiredName = "DesPitch";
    rcName = "C2";
    traceRcName = "rc2";
end
if ~ismember(desiredName,string(att.Properties.VariableNames)) || ...
        ~ismember(rcName,string(rcin.Properties.VariableNames))
    mapping = table;
    metrics = emptyMappingMetrics();
    return
end
apTime = getApTime(rcin);
offset = matchedTransitionOffset(trace.sim_time_s,trace.(traceRcName), ...
    apTime,rcin.(rcName));
attSimTime = getApTime(att)-offset;
desired = double(att.(desiredName));
scenarioTimes = double(cfg.scenario.time_s(:));
scenarioValues = double(cfg.scenario.value_deg(:));
count = numel(scenarioTimes)-1;
target = zeros(count,1);
internal = nan(count,1);
errorDeg = nan(count,1);
samples = zeros(count,1);
for index = 1:count
    target(index) = scenarioValues(index);
    startTime = scenarioTimes(index)+0.3;
    endTime = scenarioTimes(index+1)-0.2;
    mask = attSimTime >= startTime & attSimTime < endTime;
    samples(index) = nnz(mask);
    if any(mask)
        internal(index) = median(desired(mask),"omitnan");
        errorDeg(index) = internal(index)-target(index);
    end
end
allowed = double(cfg.scenario.allowed_mapping_error_deg);
pass = samples > 0 & isfinite(errorDeg) & abs(errorDeg) <= allowed;
mapping = table((1:count)',scenarioTimes(1:end-1),scenarioTimes(2:end), ...
    target,internal,errorDeg,samples,pass, ...
    'VariableNames',{'Plateau','StartTime_s','EndTime_s','ExternalTarget_deg', ...
    'ArduPilotTarget_deg','MappingError_deg','Samples','Pass'});
metrics = struct("time_offset_s",offset, ...
    "maximum_plateau_error_deg",max(abs(errorDeg),[],"omitnan"), ...
    "rmse_deg",sqrt(mean(errorDeg.^2,"omitnan")), ...
    "p95_abs_error_deg",percentile(abs(errorDeg(isfinite(errorDeg))),95));
end

function [safetyPass,signPass,metrics] = dynamicEvidence(runDir,cfg)
metrics = emptyDynamicMetrics();
simulationFile = fullfile(runDir,"simulation_data.csv");
traceFile = fullfile(runDir,"packet_trace.csv");
if ~isfile(simulationFile) || ~isfile(traceFile)
    safetyPass = false; signPass = false; return
end
data = readtable(simulationFile);
trace = readtable(traceFile);
axisName = lower(string(cfg.scenario.axis));
if axisName == "roll"
    target = data.external_roll_target_deg;
    actual = data.roll_deg;
    rate = data.p_deg_s;
else
    target = data.external_pitch_target_deg;
    actual = data.pitch_deg;
    rate = data.q_deg_s;
end
finite = all(isfinite([data.roll_deg,data.pitch_deg,data.p_deg_s, ...
    data.q_deg_s,data.r_deg_s,data.airspeed_mps,data.altitude_m]),"all");
safetyPass = finite && max(abs([data.p_deg_s;data.q_deg_s;data.r_deg_s])) < 720 && ...
    min(data.airspeed_mps) > 1 && max(data.airspeed_mps) < 100 && ...
    max(abs(data.roll_deg)) < 85 && max(abs(data.pitch_deg)) < 60;

scenarioTimes = double(cfg.scenario.time_s(:));
scenarioValues = double(cfg.scenario.value_deg(:));
stepIndex = find(abs(scenarioValues(1:end-1)) > 0.1,1,"first");
if isempty(stepIndex), signPass = false; return; end
t0 = scenarioTimes(stepIndex);
t1 = scenarioTimes(stepIndex+1);
previousTarget = scenarioValues(max(stepIndex-1,1));
stepTarget = scenarioValues(stepIndex);
baselineMask = data.time_s >= max(0,t0-1) & data.time_s < t0;
segmentMask = data.time_s >= t0 & data.time_s < t1;
if ~any(baselineMask) || nnz(segmentMask) < 5
    signPass = false; return
end
baseline = median(actual(baselineMask),"omitnan");
tailStart = t0+0.7*(t1-t0);
tailMask = data.time_s >= tailStart & data.time_s < t1;
tailValue = median(actual(tailMask),"omitnan");
stepSize = stepTarget-previousTarget;
signPass = sign(tailValue-baseline) == sign(stepSize);

t = data.time_s(segmentMask);
y = actual(segmentMask);
command = stepTarget;
direction = sign(stepSize); if direction == 0, direction = 1; end
relative = direction*(y-baseline);
amplitude = max(abs(stepSize),eps);
t10 = firstCrossing(t,relative,0.1*amplitude);
t90 = firstCrossing(t,relative,0.9*amplitude);
metrics.rise_time_s = t90-t10;
metrics.peak_deg = direction*max(direction*y);
metrics.overshoot_percent = max(0,max(direction*(y-command)))/amplitude*100;
errorDeg = command-y;
inside = abs(errorDeg) <= double(cfg.scenario.settling_band_deg);
settledIndex = firstSuffixTrue(inside);
if isempty(settledIndex)
    metrics.settling_time_s = t1-t0;
else
    metrics.settling_time_s = t(settledIndex)-t0;
end
tailError = errorDeg(max(1,end-max(2,round(0.2*numel(errorDeg)))+1):end);
metrics.steady_state_error_deg = mean(tailError,"omitnan");
metrics.rmse_deg = sqrt(mean(errorDeg.^2,"omitnan"));
metrics.p95_error_deg = percentile(abs(errorDeg),95);
metrics.max_rate_deg_s = max(abs(rate(segmentMask)));
surfacePwm = [trace.pwm_aileron_left,trace.pwm_aileron_right, ...
    trace.pwm_elevator,trace.pwm_rudder];
metrics.pwm_saturation_fraction = mean(surfacePwm <= 1105 | ...
    surfacePwm >= 1895,"all");
limits = cfg.aircraft.surface_limits_deg;
surface = [data.aileron_left_actual_deg,data.aileron_right_actual_deg, ...
    data.elevator_actual_deg,data.rudder_actual_deg];
lowerLimits = [limits.aileron_left(1),limits.aileron_right(1), ...
    limits.elevator(1),limits.rudder(1)];
upperLimits = [limits.aileron_left(2),limits.aileron_right(2), ...
    limits.elevator(2),limits.rudder(2)];
metrics.surface_saturation_fraction = mean(surface(segmentMask,:) <= lowerLimits+0.25 | ...
    surface(segmentMask,:) >= upperLimits-0.25,"all");
rateLimit = double(cfg.aircraft.angular_rate_limit_deg_s);
rates = abs([data.p_deg_s(segmentMask),data.q_deg_s(segmentMask), ...
    data.r_deg_s(segmentMask)]);
metrics.rate_saturation_fraction = mean(rates >= 0.98*rateLimit,"all");
metrics.valid = all(isfinite([metrics.overshoot_percent, ...
    metrics.settling_time_s,metrics.steady_state_error_deg,metrics.rmse_deg]));
end

function [details,pass] = signChainEvidence(runDir,cfg,mapping)
details = table; pass = false;
simulationFile = fullfile(runDir,"simulation_data.csv");
traceFile = fullfile(runDir,"packet_trace.csv");
if ~isfile(simulationFile) || ~isfile(traceFile) || isempty(mapping), return; end
data = readtable(simulationFile);
trace = readtable(traceFile);
times = double(cfg.scenario.time_s(:));
values = double(cfg.scenario.value_deg(:));
plateaus = find(abs(values(1:end-1)) > 0.1);
if isempty(plateaus), return; end
n = numel(plateaus);
axisText = repmat(string(cfg.scenario.axis),n,1);
target = zeros(n,1); commandSign = zeros(n,1);
internalDelta = nan(n,1); rcDelta = nan(n,1); pwmDelta = nan(n,1);
surfaceDelta = nan(n,1); rateDelta = nan(n,1); attitudeDelta = nan(n,1);
internalPass = false(n,1); rcPass = false(n,1); pwmPass = false(n,1);
surfacePass = false(n,1); ratePass = false(n,1); attitudePass = false(n,1);
axisName = lower(string(cfg.scenario.axis));
if axisName == "roll"
    rcSignal = double(trace.rc1)-1500;
    % Both configured aileron PWM channels move together; the physical
    % right servo reversal creates the aerodynamic differential downstream.
    pwmSignal = 0.5*(double(trace.pwm_aileron_left)+ ...
        double(trace.pwm_aileron_right))-1500;
    surfaceSignal = double(data.aileron_left_actual_deg)- ...
        double(data.aileron_right_actual_deg);
    rateSignal = double(data.p_deg_s); attitudeSignal = double(data.roll_deg);
else
    rcSignal = double(cfg.aircraft.rc.pitch_command_sign)* ...
        (double(trace.rc2)-1500);
    pwmSignal = -(double(trace.pwm_elevator)-1500);
    surfaceSignal = -double(data.elevator_actual_deg);
    rateSignal = double(data.q_deg_s); attitudeSignal = double(data.pitch_deg);
end
for k = 1:n
    index = plateaus(k);
    t0 = times(index); t1 = times(index+1);
    previous = values(max(index-1,1));
    direction = sign(values(index)-previous);
    if direction == 0, direction = sign(values(index)); end
    target(k) = values(index); commandSign(k) = direction;
    preData = data.time_s >= max(0,t0-0.8) & data.time_s < t0;
    responseData = data.time_s >= t0+0.04 & data.time_s < min(t1,t0+1.2);
    tailData = data.time_s >= t0+0.7*(t1-t0) & data.time_s < t1;
    preTrace = trace.sim_time_s >= max(0,t0-0.8) & trace.sim_time_s < t0;
    responseTrace = trace.sim_time_s >= t0+0.04 & ...
        trace.sim_time_s < min(t1,t0+1.2);
    if ~any(preData) || ~any(responseData) || ~any(tailData) || ...
            ~any(preTrace) || ~any(responseTrace), continue; end
    internalDelta(k) = direction*mapping.ArduPilotTarget_deg(index);
    rcDelta(k) = direction*(median(rcSignal(responseTrace),"omitnan")- ...
        median(rcSignal(preTrace),"omitnan"));
    pwmDelta(k) = max(direction*(pwmSignal(responseTrace)- ...
        median(pwmSignal(preTrace),"omitnan")),[],"omitnan");
    surfaceDelta(k) = max(direction*(surfaceSignal(responseData)- ...
        median(surfaceSignal(preData),"omitnan")),[],"omitnan");
    rateDelta(k) = max(direction*(rateSignal(responseData)- ...
        median(rateSignal(preData),"omitnan")),[],"omitnan");
    attitudeDelta(k) = direction*(median(attitudeSignal(tailData),"omitnan")- ...
        median(attitudeSignal(preData),"omitnan"));
    internalPass(k) = mapping.Pass(index) && internalDelta(k) > 0.1;
    rcPass(k) = rcDelta(k) > 10;
    pwmPass(k) = pwmDelta(k) > 2;
    surfacePass(k) = surfaceDelta(k) > 0.02;
    ratePass(k) = rateDelta(k) > 0.05;
    attitudePass(k) = attitudeDelta(k) > 0.1;
end
overallPass = internalPass & rcPass & pwmPass & surfacePass & ...
    ratePass & attitudePass;
details = table(plateaus(:),axisText,target,commandSign,internalDelta,rcDelta, ...
    pwmDelta,surfaceDelta,rateDelta,attitudeDelta,internalPass,rcPass, ...
    pwmPass,surfacePass,ratePass,attitudePass,overallPass, ...
    'VariableNames',{'Plateau','Axis','Target_deg','CommandSign', ...
    'InternalTargetDirectional_deg','RCDirectionalDelta_us', ...
    'PWMDirectionalDelta_us','SurfaceDirectionalDelta_deg', ...
    'RateDirectionalDelta_deg_s','AttitudeDirectionalDelta_deg', ...
    'InternalTargetPass','RCPass','PWMPass','SurfacePass','RatePass', ...
    'AttitudePass','Pass'});
pass = all(overallPass);
end

function [response,pass] = plateauResponseEvidence(runDir,cfg)
response = table; pass = false;
simulationFile = fullfile(runDir,"simulation_data.csv");
traceFile = fullfile(runDir,"packet_trace.csv");
if ~isfile(simulationFile) || ~isfile(traceFile), return; end
data = readtable(simulationFile); trace = readtable(traceFile);
times = double(cfg.scenario.time_s(:)); values = double(cfg.scenario.value_deg(:));
plateaus = find(abs(values(1:end-1)) > 0.1);
if isempty(plateaus), return; end
n = numel(plateaus); target = zeros(n,1); peak = nan(n,1);
rise = nan(n,1); overshoot = nan(n,1); settling = nan(n,1);
steadyError = nan(n,1); rmse = nan(n,1); p95Error = nan(n,1);
maxRate = nan(n,1); pwmSat = nan(n,1); surfaceSat = nan(n,1);
rateSat = nan(n,1); samples = zeros(n,1); rowPass = false(n,1);
axisName = lower(string(cfg.scenario.axis));
if axisName == "roll"
    actual = double(data.roll_deg); axisRate = double(data.p_deg_s);
else
    actual = double(data.pitch_deg); axisRate = double(data.q_deg_s);
end
surface = [double(data.aileron_left_actual_deg), ...
    double(data.aileron_right_actual_deg),double(data.elevator_actual_deg), ...
    double(data.rudder_actual_deg)];
limits = cfg.aircraft.surface_limits_deg;
lowerLimits = [limits.aileron_left(1),limits.aileron_right(1), ...
    limits.elevator(1),limits.rudder(1)];
upperLimits = [limits.aileron_left(2),limits.aileron_right(2), ...
    limits.elevator(2),limits.rudder(2)];
for k = 1:n
    index = plateaus(k); t0 = times(index); t1 = times(index+1);
    target(k) = values(index); previous = values(max(index-1,1));
    direction = sign(target(k)-previous); if direction == 0, direction = 1; end
    baselineMask = data.time_s >= max(0,t0-0.8) & data.time_s < t0;
    segmentMask = data.time_s >= t0 & data.time_s < t1;
    traceMask = trace.sim_time_s >= t0 & trace.sim_time_s < t1;
    samples(k) = nnz(segmentMask);
    if ~any(baselineMask) || samples(k) < 5 || ~any(traceMask), continue; end
    baseline = median(actual(baselineMask),"omitnan");
    t = double(data.time_s(segmentMask)); y = actual(segmentMask);
    stepSize = target(k)-previous; amplitude = max(abs(stepSize),eps);
    relative = direction*(y-baseline);
    rise(k) = firstCrossing(t,relative,0.9*amplitude)- ...
        firstCrossing(t,relative,0.1*amplitude);
    peak(k) = direction*max(direction*y);
    overshoot(k) = max(0,max(direction*(y-target(k))))/amplitude*100;
    errorDeg = target(k)-y;
    settledIndex = firstSuffixTrue(abs(errorDeg) <= ...
        double(cfg.scenario.settling_band_deg));
    if isempty(settledIndex), settling(k) = t1-t0;
    else, settling(k) = t(settledIndex)-t0; end
    tail = max(1,numel(errorDeg)-max(2,round(0.2*numel(errorDeg)))+1):numel(errorDeg);
    steadyError(k) = mean(errorDeg(tail),"omitnan");
    rmse(k) = sqrt(mean(errorDeg.^2,"omitnan"));
    p95Error(k) = percentile(abs(errorDeg),95);
    maxRate(k) = max(abs(axisRate(segmentMask)));
    pwm = [trace.pwm_aileron_left(traceMask),trace.pwm_aileron_right(traceMask), ...
        trace.pwm_elevator(traceMask),trace.pwm_rudder(traceMask)];
    pwmSat(k) = mean(pwm <= 1105 | pwm >= 1895,"all");
    segmentSurface = surface(segmentMask,:);
    surfaceSat(k) = mean(segmentSurface <= lowerLimits+0.25 | ...
        segmentSurface >= upperLimits-0.25,"all");
    rateLimit = double(cfg.aircraft.angular_rate_limit_deg_s);
    rates = abs([data.p_deg_s(segmentMask),data.q_deg_s(segmentMask), ...
        data.r_deg_s(segmentMask)]);
    rateSat(k) = mean(rates >= 0.98*rateLimit,"all");
    rowPass(k) = isfinite(rise(k)) && ...
        overshoot(k) <= double(cfg.scenario.max_overshoot_percent) && ...
        settling(k) <= double(cfg.scenario.max_settling_time_s) && ...
        abs(steadyError(k)) <= double(cfg.scenario.max_steady_state_error_deg) && ...
        pwmSat(k) <= double(cfg.scenario.max_pwm_saturation_fraction) && ...
        surfaceSat(k) <= double(cfg.scenario.max_pwm_saturation_fraction) && ...
        rateSat(k) == 0;
end
response = table(plateaus(:),target,peak,rise,overshoot,settling,steadyError, ...
    rmse,p95Error,maxRate,pwmSat,surfaceSat,rateSat,samples,rowPass, ...
    'VariableNames',{'Plateau','Target_deg','Peak_deg','RiseTime_s', ...
    'Overshoot_percent','SettlingTime_s','SteadyStateError_deg','RMSE_deg', ...
    'P95Error_deg','MaxRate_deg_s','PWMSaturationFraction', ...
    'SurfaceSaturationFraction','RateSaturationFraction','Samples','Pass'});
pass = all(rowPass);
end

function writeTimeAlignment(runDir,mappingMetrics)
traceFile = fullfile(runDir,"packet_trace.csv");
attFile = fullfile(runDir,"internal_ATT.csv");
if ~isfile(traceFile), return; end
trace = readtable(traceFile);
source = ["Simulink simulation";"JSON packet timestamp";"Wall clock UTC"];
startTime = [trace.sim_time_s(1);trace.packet_timestamp_s(1);trace.wall_time_utc_s(1)];
endTime = [trace.sim_time_s(end);trace.packet_timestamp_s(end);trace.wall_time_utc_s(end)];
offsetToSimulation = [0;trace.packet_timestamp_s(1)-trace.sim_time_s(1);NaN];
if isfile(attFile)
    att = readtable(attFile); ap = getApTime(att);
    source(end+1,1) = "ArduPilot DataFlash";
    startTime(end+1,1) = ap(1); endTime(end+1,1) = ap(end);
    offsetToSimulation(end+1,1) = mappingMetrics.time_offset_s;
end
writetable(table(source,startTime,endTime,offsetToSimulation, ...
    'VariableNames',{'TimeSource','Start','End','OffsetForSimulation_s'}), ...
    fullfile(runDir,"time_alignment.csv"));
end

function writeOutputs(runDir,result,mapping,cfg)
names = ["INFRASTRUCTURE";"COMMUNICATION";"PARAMETER_READBACK"; ...
    "COMMAND_MAPPING";"SIGN";"DYNAMICS_SANITY";"CONTROL_RESPONSE"; ...
    "SAFETY";"PLATEAU_RESPONSE";"OVERALL"];
verdict = [result.infrastructure;result.communication; ...
    result.parameter_readback;result.command_mapping;result.sign_test; ...
    result.dynamics_sanity;result.control_response;result.safety; ...
    result.plateau_response;result.overall];
writetable(table(names,verdict,'VariableNames',{'Category','Verdict'}), ...
    fullfile(runDir,"summary.csv"));
d = result.dynamic_metrics;
metricName = ["rise_time_s";"peak_deg";"overshoot_percent"; ...
    "settling_time_s";"steady_state_error_deg";"rmse_deg"; ...
    "p95_error_deg";"max_rate_deg_s";"pwm_saturation_fraction"; ...
    "surface_saturation_fraction";"rate_saturation_fraction"; ...
    "mapping_max_error_deg";"mapping_rmse_deg";"mean_rtt_ms"; ...
    "p95_rtt_ms";"max_rtt_ms";"startup_max_rtt_ms"; ...
    "max_packet_interval_ms";"packet_interval_std_ms"; ...
    "simulation_packet_interval_ms"];
metricValue = [d.rise_time_s;d.peak_deg;d.overshoot_percent; ...
    d.settling_time_s;d.steady_state_error_deg;d.rmse_deg; ...
    d.p95_error_deg;d.max_rate_deg_s;d.pwm_saturation_fraction; ...
    d.surface_saturation_fraction;d.rate_saturation_fraction; ...
    result.mapping_metrics.maximum_plateau_error_deg; ...
    result.mapping_metrics.rmse_deg;result.communication_metrics.mean_rtt_ms; ...
    result.communication_metrics.p95_rtt_ms;result.communication_metrics.max_rtt_ms; ...
    result.communication_metrics.startup_max_rtt_ms; ...
    result.communication_metrics.max_packet_interval_ms; ...
    result.communication_metrics.packet_interval_std_ms; ...
    result.communication_metrics.simulation_packet_interval_ms];
writetable(table(metricName,metricValue,'VariableNames',{'Metric','Value'}), ...
    fullfile(runDir,"metrics.csv"));
makePlots(runDir,cfg,mapping);
lines = ["# V5.2 Run Report";""; ...
    "- Scenario: `"+string(cfg.scenario.name)+"`"; ...
    "- INFRASTRUCTURE: **"+result.infrastructure+"**"; ...
    "- ArduPilot expected commit: `"+result.ardupilot_commit_expected+"`"; ...
    "- COMMUNICATION: **"+result.communication+"**"; ...
    "- COMMAND_MAPPING: **"+result.command_mapping+"**"; ...
    "- SIGN: **"+result.sign_test+"**"; ...
    "- DYNAMICS_SANITY: **"+result.dynamics_sanity+"**"; ...
    "- CONTROL_RESPONSE: **"+result.control_response+"**"; ...
    "- SAFETY: **"+result.safety+"**"; ...
    "- OVERALL: **"+result.overall+"**";""; ...
    "## Key metrics";""; ...
    "- Maximum command-mapping error: "+ ...
        number(result.mapping_metrics.maximum_plateau_error_deg)+" deg"; ...
    "- Overshoot: "+number(d.overshoot_percent)+" %"; ...
    "- Settling time: "+number(d.settling_time_s)+" s"; ...
    "- Steady-state error: "+number(d.steady_state_error_deg)+" deg"; ...
    "- RMSE: "+number(d.rmse_deg)+" deg"; ...
    "- PWM saturation fraction: "+number(d.pwm_saturation_fraction); ...
    "- Surface saturation fraction: "+number(d.surface_saturation_fraction); ...
    "- Rate saturation fraction: "+number(d.rate_saturation_fraction); ...
    "- Operational mean/P95/max JSON round trip (after 1 s warm-up): "+ ...
        number(result.communication_metrics.mean_rtt_ms)+" / "+ ...
        number(result.communication_metrics.p95_rtt_ms)+" / "+ ...
        number(result.communication_metrics.max_rtt_ms)+" ms"; ...
    "- Startup maximum JSON round trip: "+ ...
        number(result.communication_metrics.startup_max_rtt_ms)+" ms"; ...
    "- Simulation-time JSON interval: "+ ...
        number(result.communication_metrics.simulation_packet_interval_ms)+" ms";""; ...
    "## Simulation error";"";"```";result.simulation_error;"```"];
writeText(fullfile(runDir,"run_report.txt"),strjoin(lines,newline));
end

function makePlots(runDir,cfg,mapping)
simulationFile = fullfile(runDir,"simulation_data.csv");
if ~isfile(simulationFile), return; end
data = readtable(simulationFile);
axisName = lower(string(cfg.scenario.axis));

f = figure("Visible","off","Color","w");
plot(data.time_s,data.external_roll_target_deg,"LineWidth",1.4); hold on;
if axisName == "roll" && ~isempty(mapping)
    stairs(mapping.StartTime_s,mapping.ArduPilotTarget_deg,"LineWidth",1.2);
else
    plot(data.time_s,nan(size(data.time_s)),"LineWidth",1.2);
end
plot(data.time_s,data.roll_deg,"LineWidth",1.2); grid on;
xlabel("Simulation time (s)"); ylabel("Roll (deg)");
legend("External target","ArduPilot target","Truth","Location","best");
title("Roll target chain");
exportgraphics(f,fullfile(runDir,"plots", ...
    "01_roll_target_vs_ardupilot_target_vs_actual.png"),"Resolution",160); close(f);

f = figure("Visible","off","Color","w");
plot(data.time_s,data.external_roll_target_deg-data.roll_deg,"LineWidth",1.2); grid on;
xlabel("Simulation time (s)"); ylabel("Roll error (deg)"); title("Roll error");
exportgraphics(f,fullfile(runDir,"plots","02_roll_error.png"),"Resolution",160); close(f);

traceFile = fullfile(runDir,"packet_trace.csv");
if isfile(traceFile)
    trace = readtable(traceFile);
    f = figure("Visible","off","Color","w");
    plot(trace.sim_time_s,[trace.pwm_aileron_left,trace.pwm_aileron_right, ...
        trace.pwm_elevator,trace.pwm_rudder],"LineWidth",1.0); grid on;
    xlabel("Simulation time (s)"); ylabel("PWM (us)");
    legend("Aileron L","Aileron R","Elevator","Rudder","Location","best");
    title("ArduPlane PWM outputs");
    exportgraphics(f,fullfile(runDir,"plots","03_pwm.png"),"Resolution",160); close(f);

    f = figure("Visible","off","Color","w");
    plot(trace.sim_time_s,trace.packet_interval_ms,"LineWidth",1.0); grid on;
    yline(1000/double(cfg.project.timing.sitl_rate_hz),"--");
    xlabel("Simulation time (s)"); ylabel("Wall inter-arrival (ms)");
    title("Packet timing");
    exportgraphics(f,fullfile(runDir,"plots","08_packet_timing.png"),"Resolution",160); close(f);

    f = figure("Visible","off","Color","w");
    jitter = trace.packet_interval_ms-median(trace.packet_interval_ms,"omitnan");
    plot(trace.sim_time_s,trace.round_trip_ms,"LineWidth",1.0); hold on;
    plot(trace.sim_time_s,jitter,"LineWidth",1.0); grid on;
    xlabel("Simulation time (s)"); ylabel("Milliseconds");
    legend("JSON round trip","Inter-arrival jitter","Location","best");
    title("Latency and jitter (not one-way latency)");
    exportgraphics(f,fullfile(runDir,"plots","09_latency_jitter.png"),"Resolution",160); close(f);
end

f = figure("Visible","off","Color","w");
plot(data.time_s,[data.aileron_left_actual_deg,data.aileron_right_actual_deg, ...
    data.elevator_actual_deg,data.rudder_actual_deg],"LineWidth",1.0); grid on;
xlabel("Simulation time (s)"); ylabel("Surface angle (deg)");
legend("Aileron L","Aileron R","Elevator","Rudder","Location","best");
title("Actual surface angles");
exportgraphics(f,fullfile(runDir,"plots","04_surface_angle.png"),"Resolution",160); close(f);

f = figure("Visible","off","Color","w");
plot(data.time_s,data.p_deg_s,"LineWidth",1.1); grid on;
xlabel("Simulation time (s)"); ylabel("p (deg/s)"); title("Roll rate p");
exportgraphics(f,fullfile(runDir,"plots","05_roll_rate_p.png"),"Resolution",160); close(f);

f = figure("Visible","off","Color","w");
plot(data.time_s,data.external_pitch_target_deg,"LineWidth",1.4); hold on;
if axisName == "pitch" && ~isempty(mapping)
    stairs(mapping.StartTime_s,mapping.ArduPilotTarget_deg,"LineWidth",1.2);
else
    plot(data.time_s,nan(size(data.time_s)),"LineWidth",1.2);
end
plot(data.time_s,data.pitch_deg,"LineWidth",1.2); grid on;
xlabel("Simulation time (s)"); ylabel("Pitch (deg)");
legend("External target","ArduPilot target","Truth","Location","best");
title("Pitch target and response");
exportgraphics(f,fullfile(runDir,"plots","06_pitch_target_vs_actual.png"),"Resolution",160); close(f);

f = figure("Visible","off","Color","w");
yyaxis left; plot(data.time_s,data.airspeed_mps,"LineWidth",1.1); ylabel("Airspeed (m/s)");
yyaxis right; plot(data.time_s,data.altitude_m,"LineWidth",1.1); ylabel("Altitude (m)");
grid on; xlabel("Simulation time (s)"); title("Airspeed and altitude");
exportgraphics(f,fullfile(runDir,"plots","07_airspeed_altitude.png"),"Resolution",160); close(f);

f = figure("Visible","off","Color","w");
surface = [data.aileron_left_actual_deg,data.aileron_right_actual_deg, ...
    data.elevator_actual_deg,data.rudder_actual_deg];
limits = cfg.aircraft.surface_limits_deg;
lowerLimits = [limits.aileron_left(1),limits.aileron_right(1), ...
    limits.elevator(1),limits.rudder(1)];
upperLimits = [limits.aileron_left(2),limits.aileron_right(2), ...
    limits.elevator(2),limits.rudder(2)];
surfaceFlag = any(surface <= lowerLimits+0.25 | surface >= upperLimits-0.25,2);
stairs(data.time_s,double(surfaceFlag),"LineWidth",1.1); hold on;
if isfile(traceFile)
    pwmFlag = any([trace.pwm_aileron_left,trace.pwm_aileron_right, ...
        trace.pwm_elevator,trace.pwm_rudder] <= 1105 | ...
        [trace.pwm_aileron_left,trace.pwm_aileron_right, ...
        trace.pwm_elevator,trace.pwm_rudder] >= 1895,2);
    stairs(trace.sim_time_s,double(pwmFlag),"LineWidth",1.1);
end
grid on; ylim([-0.05,1.05]); xlabel("Simulation time (s)");
ylabel("Saturation flag"); legend("Surface","PWM","Location","best");
title("Saturation evidence");
exportgraphics(f,fullfile(runDir,"plots","10_saturation.png"),"Resolution",160); close(f);
end

function t = getApTime(data)
if ismember("ap_time_s",string(data.Properties.VariableNames))
    t = double(data.ap_time_s);
elseif ismember("TimeUS",string(data.Properties.VariableNames))
    t = double(data.TimeUS)/1e6;
else
    error("UAVV52:DataFlashTime","DataFlash CSV has no TimeUS/ap_time_s.");
end
end

function offset = matchedTransitionOffset(traceTime,traceRc,apTime,apRc)
% DataFlash logging can begin after the first scenario transition. Match the
% first transition visible in DataFlash to the transition with the same
% before/after PWM values in the complete bridge trace.
traceTime = double(traceTime); traceRc = double(traceRc);
apTime = double(apTime); apRc = double(apRc);
apIndex = find(abs(diff(apRc)) > 20,1,"first")+1;
traceIndices = find(abs(diff(traceRc)) > 20)+1;
if isempty(apIndex) || isempty(traceIndices)
    error("UAVV52:NoRCTransition","No RC transition found for time alignment.");
end
apBefore = median(apRc(max(1,apIndex-3):apIndex-1),"omitnan");
apAfter = median(apRc(apIndex:min(numel(apRc),apIndex+2)),"omitnan");
score = inf(size(traceIndices));
for index = 1:numel(traceIndices)
    candidate = traceIndices(index);
    traceBefore = median(traceRc(max(1,candidate-3):candidate-1),"omitnan");
    traceAfter = median(traceRc(candidate:min(numel(traceRc),candidate+2)),"omitnan");
    score(index) = abs(traceBefore-apBefore)+abs(traceAfter-apAfter);
end
[bestScore,best] = min(score);
if bestScore > 20
    error("UAVV52:UnmatchedRCTransition", ...
        "DataFlash RC transition could not be matched to the bridge trace.");
end
offset = apTime(apIndex)-traceTime(traceIndices(best));
end

function value = firstCrossing(t,x,threshold)
index = find(x >= threshold,1,"first");
if isempty(index), value = t(end); else, value = t(index); end
end

function index = firstSuffixTrue(mask)
index = [];
for candidate = 1:numel(mask)
    if all(mask(candidate:end)), index = candidate; return; end
end
end

function value = percentile(x,p)
x = sort(double(x(isfinite(x))));
if isempty(x), value = NaN; return; end
position = 1+(numel(x)-1)*p/100;
lower = floor(position); upper = ceil(position);
if lower == upper
    value = x(lower);
else
    value = x(lower)+(position-lower)*(x(upper)-x(lower));
end
end

function metrics = emptyMappingMetrics()
metrics = struct("time_offset_s",NaN,"maximum_plateau_error_deg",NaN, ...
    "rmse_deg",NaN,"p95_abs_error_deg",NaN);
end

function metrics = emptyDynamicMetrics()
metrics = struct("valid",false,"rise_time_s",NaN,"peak_deg",NaN, ...
    "overshoot_percent",NaN,"settling_time_s",NaN, ...
    "steady_state_error_deg",NaN,"rmse_deg",NaN,"p95_error_deg",NaN, ...
    "max_rate_deg_s",NaN,"pwm_saturation_fraction",NaN, ...
    "surface_saturation_fraction",NaN,"rate_saturation_fraction",NaN);
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function value = number(x)
if isfinite(x), value = string(sprintf("%.6g",x)); else, value = "NaN"; end
end

function writeText(filePath,content)
fid = fopen(filePath,"w");
if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",content);
end
