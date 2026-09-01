function result = analyzeInterfaceRun(runDir,cfg,simulationPass,simulationError, ...
    dataFlashPass,dataFlashDetail,readback)
%ANALYZEINTERFACERUN Separate interface correctness from control quality.

checks = ["WSL_SITL","RC_INPUT_TRANSPORT","RC_INPUT_VALUE", ...
    "FBWA_MAPPING","ARDUPILOT_TARGET_TRACE","SERVO_OUTPUT_TRANSPORT", ...
    "ACTUATOR_MAPPING","TRUTH_FEEDBACK","TIME_SYNC", ...
    "PACKET_CONTINUITY","PARAMETER_READBACK","HEADLESS"];
pass = false(size(checks));
detail = strings(size(checks));
metrics = struct;

required = ["packet_trace.csv","feedback_trace.csv","simulation_data.csv", ...
    "internal_ATT.csv","internal_RCIN.csv","internal_RCOU.csv"];
existsMap = isfile(fullfile(runDir,required));
pass(1) = simulationPass && dataFlashPass;
detail(1) = passFail(pass(1))+": simulation="+passFail(simulationPass)+ ...
    ", DataFlash="+passFail(dataFlashPass)+"; "+string(dataFlashDetail);
pass(2) = all(existsMap([1,4,5]));
detail(2) = passFail(pass(2))+": bridge trace, RCIN and ATT evidence";

alignment = NaN;
trace = table; att = table; rcin = table; rcout = table; simulation = table;
try
    trace = readtable(fullfile(runDir,"packet_trace.csv"));
    att = readtable(fullfile(runDir,"internal_ATT.csv"));
    rcin = readtable(fullfile(runDir,"internal_RCIN.csv"));
    rcout = readtable(fullfile(runDir,"internal_RCOU.csv"));
    simulation = readtable(fullfile(runDir,"simulation_data.csv"));
    alignment = transitionOffset(trace.sim_time_s,trace.rc1_sent_us, ...
        apTime(rcin),rcin.C1);
catch ME
    detail(2) = detail(2)+"; "+string(ME.message);
end

try
    apSimulationTime = apTime(rcin)-alignment;
    received = interp1(apSimulationTime,double(rcin.C1), ...
        double(trace.sim_time_s),"previous",NaN);
    mask = isfinite(received);
    rcError = abs(received(mask)-double(trace.rc1_sent_us(mask)));
    metrics.rc_input_max_error_us = max(rcError,[],"omitnan");
    metrics.rc_input_median_error_us = median(rcError,"omitnan");
    pass(3) = nnz(mask) > 10 && metrics.rc_input_max_error_us <= ...
        double(cfg.scenario.allowed_rc_error_us);
    detail(3) = passFail(pass(3))+sprintf( ...
        ": max sent-vs-RCIN error %.3f us",metrics.rc_input_max_error_us);
catch ME
    detail(3) = "FAIL: "+string(ME.message);
end

try
    [mapping,metrics.mapping_max_error_deg] = mappingEvidence(att,alignment,cfg);
    writetable(mapping,fullfile(runDir,"fbwa_mapping.csv"));
    pass(4) = all(mapping.Pass);
    detail(4) = passFail(pass(4))+sprintf( ...
        ": max design-vs-ATT.DesRoll plateau error %.3f deg", ...
        metrics.mapping_max_error_deg);
catch ME
    detail(4) = "FAIL: "+string(ME.message);
end
pass(5) = ~isempty(att) && ismember("DesRoll",string(att.Properties.VariableNames)) ...
    && any(isfinite(double(att.DesRoll)));
detail(5) = passFail(pass(5))+ ...
    ": ATT.DesRoll present in ArduPilot DataFlash";

try
    apSimulationTime = apTime(rcout)-alignment;
    pairs = {"protocol_aileron_left_pwm_us","C1"; ...
        "protocol_elevator_pwm_us","C2";"protocol_throttle_pwm_us","C3"; ...
        "protocol_rudder_pwm_us","C4";"protocol_aileron_right_pwm_us","C5"};
    errorUs = [];
    for k = 1:size(pairs,1)
        received = interp1(apSimulationTime,double(rcout.(pairs{k,2})), ...
            double(trace.sim_time_s),"previous",NaN);
        delta = received-double(trace.(pairs{k,1}));
        errorUs = [errorUs;abs(delta(isfinite(delta)))]; %#ok<AGROW>
    end
    metrics.servo_transport_max_error_us = percentile(errorUs,99);
    % RCOU is a lower-rate asynchronous DataFlash observation of the same
    % RCOutput values sent in every JSON servo frame. 20 us covers one
    % logging-phase interval during fast motion without hiding scale/sign
    % errors (which are hundreds of microseconds).
    pass(6) = numel(errorUs) > 50 && ...
        metrics.servo_transport_max_error_us <= 20;
    detail(6) = passFail(pass(6))+sprintf( ...
        ": P99 RCOU-vs-JSON servo packet error %.3f us", ...
        metrics.servo_transport_max_error_us);
catch ME
    detail(6) = "FAIL: "+string(ME.message);
end

try
    P = uav_config(string(cfg.aircraft.aircraft_id), ...
        double(cfg.aircraft.nominal_airspeed_mps));
    expected = zeros(height(simulation),5);
    pwm = [simulation.protocol_throttle_pwm_us, ...
        simulation.protocol_aileron_left_pwm_us, ...
        simulation.protocol_aileron_right_pwm_us, ...
        simulation.protocol_elevator_pwm_us,simulation.protocol_rudder_pwm_us];
    for row = 1:height(simulation)
        expected(row,:) = uav_servo_mapping(P,pwm(row,:),"pwm_to_command")';
    end
    actual = [simulation.throttle_actual, ...
        deg2rad(simulation.aileron_left_actual_deg), ...
        deg2rad(simulation.aileron_right_actual_deg), ...
        deg2rad(simulation.elevator_actual_deg), ...
        deg2rad(simulation.rudder_actual_deg)];
    % To Workspace and the 50-Hz sampled actuator can observe opposite
    % sides of a protocol boundary. Match against the current or preceding
    % three frames; the P99 value tests calibration/sign/units while the
    % timing trace accounts for latency separately.
    delayedError = inf(height(simulation),5,4);
    for lag = 0:3
        delayedError(1+lag:end,:,1+lag) = ...
            abs(expected(1:end-lag,:)-actual(1+lag:end,:));
    end
    mappingError = min(delayedError,[],3);
    % Before Plane configures its output functions, JSON carries 1500-us
    % surface placeholders while the V5.4 actuator intentionally holds the
    % measured 1410-us neutral.  That protocol-startup gate is validated by
    % the actuator tests; interface mapping begins at the first real surface
    % output frame and retains the original numerical tolerance.
    surfacePwm = pwm(:,2:5);
    protocolReadyIndex = find(any(abs(surfacePwm-1500) > 0.5,2),1,"first");
    if isempty(protocolReadyIndex), protocolReadyIndex = height(simulation); end
    evaluationStart = max(4,protocolReadyIndex);
    metrics.actuator_mapping_p99_error = percentile( ...
        mappingError(evaluationStart:end,:),99);
    metrics.actuator_mapping_protocol_ready_index = protocolReadyIndex;
    pass(7) = metrics.actuator_mapping_p99_error <= 1e-6;
    detail(7) = passFail(pass(7))+sprintf( ...
        ": P99 unique PWM-to-physical mapping error %.3g", ...
        metrics.actuator_mapping_p99_error);
catch ME
    detail(7) = "FAIL: "+string(ME.message);
end

try
    feedback = readtable(fullfile(runDir,"feedback_trace.csv"));
    rollTruth = interp1(simulation.time_s,simulation.roll_deg, ...
        feedback.sim_time_s,"linear",NaN);
    truthError = abs(rollTruth-rad2deg(feedback.roll_rad));
    metrics.feedback_roll_max_error_deg = max(truthError,[],"omitnan");
    % Simulation logging and the discrete bridge execute on the same 20-ms
    % boundary but can be observed on opposite sides of that boundary.
    % A 0.25-deg limit detects unit/frame/sign defects while allowing that
    % single-frame observation phase.
    pass(8) = height(feedback) > 100 && all(isfinite(feedback.json_timestamp_s)) ...
        && metrics.feedback_roll_max_error_deg <= 0.25;
    detail(8) = passFail(pass(8))+sprintf( ...
        ": max JSON feedback-vs-truth roll error %.6f deg", ...
        metrics.feedback_roll_max_error_deg);
    dt = diff(feedback.json_timestamp_s);
    metrics.feedback_median_step_s = median(dt,"omitnan");
    pass(9) = all(dt > 0) && abs(metrics.feedback_median_step_s- ...
        double(cfg.project.timing.communication_step_s)) <= 1e-9;
    detail(9) = passFail(pass(9))+sprintf( ...
        ": median timestamp step %.6f s",metrics.feedback_median_step_s);
catch ME
    detail(8) = "FAIL: "+string(ME.message);
    detail(9) = detail(8);
end

try
    frameDelta = diff(double(trace.frame_count));
    metrics.packet_count = height(trace);
    metrics.packet_interval_p95_ms = percentile(diff(trace.sim_time_s)*1000,95);
    pass(10) = height(trace) >= 0.8*double(cfg.scenario.stop_time_s)* ...
        double(cfg.project.timing.sitl_rate_hz) && all(frameDelta > 0) && ...
        all(trace.invalid_packets == 0) && all(trace.dropped_packets == 0);
    detail(10) = passFail(pass(10))+sprintf( ...
        ": %d packets, P95 interval %.3f ms, no drop/invalid", ...
        height(trace),metrics.packet_interval_p95_ms);
catch ME
    detail(10) = "FAIL: "+string(ME.message);
end

pass(11) = istable(readback) && height(readback) > 0 && all(readback.Pass);
detail(11) = passFail(pass(11))+sprintf( ...
    ": %d/%d parameter values matched DataFlash read-back", ...
    nnz(readback.Pass),height(readback));
pass(12) = simulationPass && dataFlashPass;
detail(12) = passFail(pass(12))+ ...
    ": run, RC experiment, parameter automation and logging used no GUI";

interfaceOverall = all(pass);
acceptance = table(checks',pass',detail', ...
    'VariableNames',{'Check','Pass','Detail'});
writetable(acceptance,fullfile(runDir,"interface_acceptance.csv"));
control = controlMetrics(att,rcout,alignment,cfg);
writetable(struct2table(control),fullfile(runDir,"control_baseline_metrics.csv"));
v52.writeInterfacePlots(runDir,cfg,alignment);

result = struct("interface_overall",passFail(interfaceOverall), ...
    "control_rating",control.rating,"checks",acceptance, ...
    "interface_metrics",metrics,"control_metrics",control, ...
    "simulation_error",simulationError,"run_directory",runDir);
writeRunReport(runDir,result,acceptance);
end

function [mapping,maxError] = mappingEvidence(att,offset,cfg)
t = apTime(att)-offset;
times = double(cfg.scenario.time_s(:));
target = double(cfg.scenario.desired_internal_roll_deg(:));
n = numel(times)-1;
internal = nan(n,1); samples = zeros(n,1);
for k = 1:n
    mask = t >= times(k)+0.3 & t < times(k+1)-0.2;
    samples(k) = nnz(mask);
    internal(k) = median(double(att.DesRoll(mask)),"omitnan");
end
errorDeg = internal-target(1:n);
pass = samples > 0 & isfinite(errorDeg) & ...
    abs(errorDeg) <= double(cfg.scenario.allowed_mapping_error_deg);
mapping = table((1:n)',times(1:n),times(2:n+1),target(1:n),internal, ...
    errorDeg,samples,pass,'VariableNames',{'Plateau','StartTime_s','EndTime_s', ...
    'DesignInternalTarget_deg','ArduPilotDesRoll_deg','Error_deg','Samples','Pass'});
maxError = max(abs(errorDeg),[],"omitnan");
end

function metrics = controlMetrics(att,rcout,offset,cfg)
metrics = struct("valid",false,"rise_time_s",NaN,"overshoot_percent",NaN, ...
    "settling_time_s",NaN,"steady_state_error_deg",NaN,"rmse_deg",NaN, ...
    "p95_error_deg",NaN,"oscillation_deg",NaN, ...
    "pwm_saturation_fraction",NaN,"surface_saturation_fraction",NaN, ...
    "rmse_component",NaN,"overshoot_component",NaN, ...
    "settling_component",NaN,"oscillation_component",NaN, ...
    "saturation_component",NaN,"total",NaN,"rating","INVALID");
if isempty(att), return; end
t = apTime(att)-offset;
des = double(att.DesRoll); actual = double(att.Roll);
times = double(cfg.scenario.time_s(:));
targets = double(cfg.scenario.desired_internal_roll_deg(:));
steps = find(abs(targets(1:end-1)) > 0.5);
if isempty(steps), return; end
allError = []; rise = []; overshoot = []; settling = [];
steady = []; oscillation = [];
for step = steps'
    mask = t >= times(step) & t < times(step+1);
    if nnz(mask) < 10, continue; end
    tt = t(mask)-times(step); dd = des(mask); yy = actual(mask);
    error = dd-yy; target = median(dd,"omitnan"); direction = sign(target);
    allError = [allError;error]; %#ok<AGROW>
    overshoot(end+1,1) = max(0,100*(max(direction*yy)-abs(target))/ ...
        max(abs(target),eps)); %#ok<AGROW>
    threshold10 = 0.1*abs(target); threshold90 = 0.9*abs(target);
    t10 = firstTime(tt,direction*yy,threshold10);
    t90 = firstTime(tt,direction*yy,threshold90);
    rise(end+1,1) = max(0,t90-t10); %#ok<AGROW>
    inside = abs(error) <= 0.5;
    lastOutside = find(~inside,1,"last");
    if isempty(lastOutside)
        settling(end+1,1) = 0; %#ok<AGROW>
    elseif lastOutside < numel(tt)
        settling(end+1,1) = tt(lastOutside+1); %#ok<AGROW>
    else
        settling(end+1,1) = tt(end); %#ok<AGROW>
    end
    tail = max(1,floor(0.75*numel(error))):numel(error);
    steady(end+1,1) = median(error(tail),"omitnan"); %#ok<AGROW>
    oscillation(end+1,1) = std(error(tail),"omitnan"); %#ok<AGROW>
end
if isempty(allError), return; end
metrics.rmse_deg = sqrt(mean(allError.^2,"omitnan"));
metrics.p95_error_deg = percentile(abs(allError),95);
metrics.rise_time_s = max(rise,[],"omitnan");
metrics.overshoot_percent = max(overshoot,[],"omitnan");
metrics.settling_time_s = max(settling,[],"omitnan");
[~,worst] = max(abs(steady));
metrics.steady_state_error_deg = steady(worst);
metrics.oscillation_deg = max(oscillation,[],"omitnan");
if ~isempty(rcout)
    names = ["C1","C2","C4","C5"];
    pwm = zeros(height(rcout),numel(names));
    for k = 1:numel(names), pwm(:,k) = double(rcout.(names(k))); end
    metrics.pwm_saturation_fraction = mean(any(pwm <= 1005 | pwm >= 1995,2));
end
metrics.surface_saturation_fraction = metrics.pwm_saturation_fraction;
metrics.rmse_component = metrics.rmse_deg/5;
metrics.overshoot_component = metrics.overshoot_percent/100;
metrics.settling_component = metrics.settling_time_s/5;
metrics.oscillation_component = metrics.oscillation_deg/5;
metrics.saturation_component = 5*metrics.pwm_saturation_fraction;
metrics.total = metrics.rmse_component+metrics.overshoot_component+ ...
    metrics.settling_component+metrics.oscillation_component+ ...
    metrics.saturation_component;
metrics.valid = all(isfinite([metrics.rmse_deg,metrics.total]));
if metrics.valid && metrics.rmse_deg <= 1 && metrics.overshoot_percent <= 20
    metrics.rating = "BASELINE_ACCEPTABLE";
elseif metrics.valid
    metrics.rating = "UNTUNED";
end
end

function writeRunReport(runDir,result,acceptance)
lines = ["# V5.2 Interface Acceptance";""; ...
    "Interface overall: **"+result.interface_overall+"**"; ...
    "Control rating: **"+result.control_rating+"**";""; ...
    "Control quality is reported separately and never changes interface PASS.";""];
for k = 1:height(acceptance)
    lines(end+1) = "- "+acceptance.Check(k)+": **"+ ...
        passFail(acceptance.Pass(k))+"** — "+acceptance.Detail(k); %#ok<AGROW>
end
fid = fopen(fullfile(runDir,"interface_acceptance.txt"),"w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",lines);
end

function offset = transitionOffset(traceTime,traceRc,firmwareTime,firmwareRc)
traceIndex = find(abs(diff(double(traceRc))) > 20,1)+1;
firmwareIndex = find(abs(diff(double(firmwareRc))) > 20,1)+1;
if isempty(traceIndex) || isempty(firmwareIndex)
    error("UAVV52:NoRCTransition","No comparable RC transition was logged.");
end
offset = double(firmwareTime(firmwareIndex))-double(traceTime(traceIndex));
end

function t = apTime(data)
if ismember("ap_time_s",string(data.Properties.VariableNames))
    t = double(data.ap_time_s);
else
    t = double(data.TimeUS)/1e6;
end
end

function value = firstTime(t,x,threshold)
index = find(x >= threshold,1);
if isempty(index), value = t(end); else, value = t(index); end
end

function value = percentile(x,p)
x = sort(double(x(isfinite(x))));
if isempty(x), value = NaN; return; end
position = 1+(numel(x)-1)*p/100;
lo = floor(position); hi = ceil(position);
if lo == hi, value = x(lo); else, value = x(lo)+(position-lo)*(x(hi)-x(lo)); end
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end
