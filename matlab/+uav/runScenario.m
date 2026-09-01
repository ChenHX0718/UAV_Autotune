function result = runScenario(scenarioName,options)
%RUNSCENARIO Execute one isolated, headless V5.4.1 SITL/Simulink run.
arguments
    scenarioName (1,1) string
    options.Distro (1,1) string = "Ubuntu-24.04"
    options.ParameterFiles string = strings(0,1)
    options.ParameterOverrides = struct
    options.InitialAirspeed (1,1) double = NaN
    options.ModelPerturbation struct = struct
    options.RequestedMode (1,1) string = ""
    options.Tag (1,1) string = ""
    options.Category (1,1) string = "runs"
    options.AllowNativeReplay (1,1) logical = false
    options.ActuatorFidelity (1,1) string = ""
    options.SensorFidelity (1,1) string = ""
    options.RandomSeed (1,1) double = NaN
end
root = uav.projectRoot();
modelRoot = fullfile(root,"model");
addpath(fullfile(root,"matlab"),"-begin"); addpath(modelRoot,"-begin");
create_interface_buses();
cfg = uav.loadConfiguration(scenarioName);
requestedMode = upper(options.RequestedMode);
if strlength(requestedMode) == 0, requestedMode = upper(string(cfg.scenario.flight_mode)); end
if ~ismember(requestedMode,["FBWA","AUTOTUNE"])
    error("UAVV541:Mode","Only FBWA and AUTOTUNE are in V5.4.1 scope.");
end

stamp = string(datetime("now","Format","yyyyMMdd_HHmmss_SSS"));
suffix = scenarioName;
if strlength(options.Tag) > 0, suffix = suffix+"_"+options.Tag; end
category = string(options.Category);
categoryParts = split(replace(category,"\","/"),"/");
categoryParts(categoryParts == "") = [];
if isempty(categoryParts) || ~startsWith(lower(categoryParts(1)),"v5_")
    category = fullfile("v5_4_1",category);
end
runDir = fullfile(root,"results",category,stamp+"_"+suffix);
mkdir(runDir); mkdir(fullfile(runDir,"plots"));
diary(fullfile(runDir,"matlab_runner.log"));
diaryCleanup = onCleanup(@() diary("off")); %#ok<NASGU>

[P,~] = uav.configureRun(cfg,runDir,InitialAirspeed=options.InitialAirspeed, ...
    ModelPerturbation=options.ModelPerturbation, ...
    ActuatorFidelity=options.ActuatorFidelity, ...
    SensorFidelity=options.SensorFidelity,RandomSeed=options.RandomSeed);
extra = table(strings(0,1),zeros(0,1),'VariableNames',{'Name','Value'});
for file = options.ParameterFiles(:)'
    extra = uav.mergeParameters(extra,uav.readParamFile(file));
end
extra = uav.mergeParameters(extra,options.ParameterOverrides);
extra = uav.mergeParameters(extra,uav.sensorParameterOverrides(P));
snapshotFile = fullfile(runDir,"parameter_snapshot.param");
[selected,metadataValidation] = uav.writeDefaults(P,snapshotFile,extra, ...
    AllowNativeReplay=options.AllowNativeReplay);
writetable(selected,fullfile(runDir,"selected_parameters.csv"));
writetable(metadataValidation,fullfile(runDir,"parameter_metadata_validation.csv"));
P.controller.sitl.defaults_file_override = snapshotFile;
copyfile(fullfile(root,"config","scenarios",scenarioName+".json"), ...
    fullfile(runDir,"scenario.json"));
writeJson(fullfile(runDir,"model_perturbation.json"),options.ModelPerturbation);

snapshot = struct("created_utc",string(datetime("now","TimeZone","UTC")), ...
    "version","5.4.1","scenario",scenarioName,"requested_mode",requestedMode, ...
    "ardupilot_commit",string(cfg.project.ardupilot.commit), ...
    "initial_airspeed_mps",P.session.initial_airspeed_mps, ...
    "random_seed",P.session.random_seed,"actuator_fidelity",P.fidelity.actuator, ...
    "sensor_fidelity",P.fidelity.sensor,"headless",true, ...
    "simulation_speedup",double(cfg.simulation.speedup), ...
    "communication_step_s",double(cfg.simulation.communication_step_s), ...
    "logging_step_s",double(cfg.simulation.logging_step_s), ...
    "tuning_owner","ArduPilot Native AUTOTUNE");
writeJson(fullfile(runDir,"configuration_snapshot.json"),snapshot);

simulationPass = false; simulationError = ""; entryMode = struct("pass",false);
exitMode = struct("pass",false); modeSession = struct("pass",false);
modeSessionLaunch = struct("pass",false); startPass = false;
startScript = fullfile(root,"scripts","sitl","start_sitl_wsl.ps1");
try
    uav.invokePowerShell(startScript,["-RunDirectory",runDir, ...
        "-DefaultsFile",snapshotFile,"-Distro",options.Distro, ...
        "-Speedup",string(cfg.simulation.speedup), ...
        "-RateHz",string(cfg.project.timing.sitl_rate_hz)]);
    startPass = true;
catch ME
    simulationError = string(getReport(ME,"extended","hyperlinks","off"));
end
wslCleanup = onCleanup(@() safeStop(root,runDir,options.Distro)); %#ok<NASGU>

if startPass
    modeSessionLaunch = uav.startModeSession(requestedMode,runDir,cfg, ...
        Distro=options.Distro);
end

modelName = string(cfg.project.model_name);
modelFile = fullfile(modelRoot,modelName+".slx");
cacheFolder = fullfile(runDir,"simulink_cache");
codegenFolder = fullfile(runDir,"simulink_codegen");
mkdir(cacheFolder); mkdir(codegenFolder);
Simulink.fileGenControl("set","CacheFolder",cacheFolder, ...
    "CodeGenFolder",codegenFolder,"createDir",true);
bridgeCleanup = onCleanup(@() closeBridge(P)); %#ok<NASGU>
if startPass && fieldOr(modeSessionLaunch,"pass",false)
    try
        open_system(modelFile);
        in = Simulink.SimulationInput(modelName);
        in = in.setVariable("P",P);
        in = in.setModelParameter("StopTime",string(cfg.scenario.stop_time_s), ...
            "SolverType","Fixed-step","Solver","ode4", ...
            "FixedStep",string(cfg.simulation.base_step_s), ...
            "SimulationMode","normal","ReturnWorkspaceOutputs","on");
        out = sim(in);
        simulationPass = true;
        uav.writeSimulationData(out,P,double(cfg.simulation.logging_step_s), ...
            fullfile(runDir,"simulation_data.csv"));
    catch ME
        simulationError = string(getReport(ME,"extended","hyperlinks","off"));
    end
end

if startPass && fieldOr(modeSessionLaunch,"pass",false)
    [entryMode,exitMode,modeSession] = uav.waitModeSession(runDir);
end
closeBridge(P); try close_system(modelName,0); catch, end
safeStop(root,runDir,options.Distro); clear wslCleanup
[dataFlashPass,dataFlashDetail] = uav.exportDataFlash(runDir,options.Distro);

axisName = lower(string(cfg.scenario.axis));
mutable = strings(0,1);
if requestedMode == "AUTOTUNE", mutable = uav.autotuneMutableParameters(axisName); end
readback = uav.validateParameterReadback(snapshotFile, ...
    fullfile(runDir,"parameter_readback.csv"),mutable);
writetable(readback,fullfile(runDir,"parameter_validation.csv"));

onlineSafetyAbort = isfile(fullfile(runDir,"safety_abort.json"));
modeDropout = isfile(fullfile(runDir,"mode_dropout.json"));
packet = packetIntegrity(runDir,cfg,onlineSafetyAbort || modeDropout);
safety = uav.evaluateSafetyEnvelope(runDir);
if onlineSafetyAbort
    safety.pass = false;
    safety.failure_reason = "ENVELOPE_VIOLATION";
    try
        safety.online_abort = jsondecode(fileread( ...
            fullfile(runDir,"safety_abort.json")));
    catch
    end
end
modeAudit = auditModeScoringWindow(runDir,requestedMode,cfg);
atrpRequired = requestedMode == "AUTOTUNE";
atrpPass = ~atrpRequired || isfile(fullfile(runDir,"internal_ATRP.csv"));
modePass = fieldOr(entryMode,"pass",false) && ...
    fieldOr(exitMode,"pass",false) && fieldOr(modeSession,"pass",false) && ...
    nestedFieldOr(modeSession,"sitl_ready","pass",false) && ...
    nestedFieldOr(modeSession,"fbwa_ready","pass",false) && ...
    nestedFieldOr(modeSession,"live_mode_monitor","pass",false) && ...
    fieldOr(modeAudit,"pass",false);
overallPass = startPass && simulationPass && dataFlashPass && modePass && ...
    packet.pass && safety.pass && atrpPass && all(readback.Pass);
failure = classifyFailure(startPass,simulationPass,dataFlashPass,modePass, ...
    packet,safety,atrpPass,readback,onlineSafetyAbort,modeDropout,modeSession);
result = struct("overall",passFail(overallPass),"failure_reason",failure, ...
    "run_directory",runDir,"scenario",scenarioName,"axis",axisName, ...
    "requested_mode",requestedMode,"simulation_pass",simulationPass, ...
    "simulation_error",simulationError,"dataflash_pass",dataFlashPass, ...
    "dataflash_detail",dataFlashDetail,"mode_pass",modePass, ...
    "mode_session",modeSession,"mode_scoring_audit",modeAudit, ...
    "packet_integrity",packet,"safety",safety,"atrp_present",atrpPass, ...
    "parameter_readback_pass",all(readback.Pass), ...
    "online_safety_abort",onlineSafetyAbort,"mode_dropout",modeDropout, ...
    "autotune_completion_class",completionClass(modeSession,requestedMode));
writeJson(fullfile(runDir,"result.json"),result);
fprintf("V5.4.1 %s: %s %s\n",scenarioName,result.overall,result.failure_reason);
end

function packet = packetIntegrity(runDir,cfg,onlineSafetyAbort)
filePath = fullfile(runDir,"packet_trace.csv");
packet = struct("pass",false,"failure_reason","INTERFACE_FAIL");
if ~isfile(filePath), packet.detail = "packet_trace missing"; return; end
try
    data = readtable(filePath);
    frameDelta = diff(double(data.frame_count));
    packet.count = height(data);
    integrityDuration = double(cfg.scenario.stop_time_s);
    if onlineSafetyAbort
        integrityDuration = max(double(data.sim_time_s));
        packet.intentional_truncation = true;
    end
    packet.expected_minimum = floor(0.8*integrityDuration* ...
        double(cfg.project.timing.sitl_rate_hz));
    requiredNames = ["sim_time_s","packet_timestamp_s","wall_time_utc_s", ...
        "frame_count","frame_rate_hz","rc_roll_normalized", ...
        "rc_pitch_normalized","rc_yaw_normalized", ...
        "rc_throttle_normalized","rc1_sent_us","rc2_sent_us", ...
        "rc3_sent_us","rc4_sent_us","protocol_throttle_pwm_us", ...
        "protocol_aileron_left_pwm_us","protocol_aileron_right_pwm_us", ...
        "protocol_elevator_pwm_us","protocol_rudder_pwm_us", ...
        "tx_packets","rx_packets","dropped_packets", ...
        "duplicate_packets","invalid_packets"];
    if ~all(ismember(requiredNames,string(data.Properties.VariableNames)))
        packet.detail = "required packet-trace columns missing";
        return
    end
    requiredNumeric = data{:,cellstr(requiredNames)};
    packet.nan_count = nnz(isnan(requiredNumeric));
    packet.inf_count = nnz(isinf(requiredNumeric));
    packet.dropped = max(double(data.dropped_packets));
    packet.invalid = max(double(data.invalid_packets));
    packet.pass = packet.count >= packet.expected_minimum && ...
        all(frameDelta > 0) && packet.nan_count == 0 && ...
        packet.inf_count == 0 && ...
        packet.dropped == 0 && packet.invalid == 0;
    if packet.pass, packet.failure_reason = ""; end
catch ME
    packet.detail = string(ME.message);
end
end

function audit = auditModeScoringWindow(runDir,modeName,cfg)
expected = 5; if modeName == "AUTOTUNE", expected = 8; end
startTime = numericFieldOr(cfg.scenario,"scoring_start_time_s", ...
    double(cfg.project.mode_gate.minimum_startup_guard_s));
endTime = numericFieldOr(cfg.scenario,"scoring_end_time_s", ...
    double(cfg.scenario.stop_time_s));
officialFile = fullfile(runDir,"official_finished.json");
if modeName == "AUTOTUNE" && isfile(officialFile)
    official = jsondecode(fileread(officialFile));
    if isfield(official,"first_finished_simulation_s") && ...
            isfinite(double(official.first_finished_simulation_s))
        endTime = double(official.first_finished_simulation_s);
    end
end
tolerance = double(cfg.project.mode_gate.coverage_tolerance);
audit = struct("pass",false,"failure_reason","MODE_CHANGE_FAIL", ...
    "expected_mode",modeName,"expected_mode_number",expected, ...
    "scoring_start_time_s",startTime,"scoring_end_time_s",endTime, ...
    "coverage_tolerance",tolerance,"fbwa_coverage",0, ...
    "manual_coverage",0,"other_mode_coverage",0, ...
    "detail","MODE_LOG_MISSING_OR_SCORING_WINDOW_UNKNOWN");
modeFile = fullfile(runDir,"internal_MODE.csv");
attFile = fullfile(runDir,"internal_ATT.csv");
if ~isfile(modeFile) || ~isfile(attFile)
    writeJson(fullfile(runDir,"mode_scoring_audit.json"),audit); return
end
try
    modeData = readtable(modeFile); attData = readtable(attFile);
    if ~all(ismember(["ModeNum","ap_time_s"], ...
            string(modeData.Properties.VariableNames)))
        writeJson(fullfile(runDir,"mode_scoring_audit.json"),audit); return
    end
    times = double(modeData.ap_time_s); modes = double(modeData.ModeNum);
    [times,order] = sort(times); modes = modes(order);
    attEnd = max(double(attData.ap_time_s));
    observedEnd = min(endTime,attEnd);
    if observedEnd <= startTime
        audit.detail = "SCORING_WINDOW_NOT_REACHED";
        audit.dataflash_end_time_s = attEnd;
        writeJson(fullfile(runDir,"mode_scoring_audit.json"),audit); return
    end
    stateIndex = find(times <= startTime,1,"last");
    if isempty(stateIndex)
        audit.detail = "MODE_AT_SCORING_START_UNKNOWN";
        writeJson(fullfile(runDir,"mode_scoring_audit.json"),audit); return
    end
    currentMode = modes(stateIndex); cursor = startTime;
    durationExpected = 0; durationManual = 0; durationOther = 0;
    transitions = find(times > startTime & times < observedEnd);
    for index = transitions(:)'
        duration = times(index)-cursor;
        [durationExpected,durationManual,durationOther] = addDuration( ...
            currentMode,expected,duration,durationExpected, ...
            durationManual,durationOther);
        currentMode = modes(index); cursor = times(index);
    end
    [durationExpected,durationManual,durationOther] = addDuration( ...
        currentMode,expected,observedEnd-cursor,durationExpected, ...
        durationManual,durationOther);
    total = observedEnd-startTime;
    expectedCoverage = durationExpected/max(total,eps);
    manualCoverage = durationManual/max(total,eps);
    otherCoverage = durationOther/max(total,eps);
    completeWindow = attEnd >= endTime-0.05;
    audit.pass = completeWindow && expectedCoverage >= 1-tolerance;
    audit.failure_reason = ""; if ~audit.pass, audit.failure_reason = "MODE_DROPOUT"; end
    if expected == 5, audit.fbwa_coverage = expectedCoverage; end
    audit.expected_mode_coverage = expectedCoverage;
    audit.manual_coverage = manualCoverage;
    audit.other_mode_coverage = otherCoverage;
    audit.duration_expected_s = durationExpected;
    audit.duration_manual_s = durationManual;
    audit.duration_other_s = durationOther;
    audit.dataflash_end_time_s = attEnd;
    audit.observed_scoring_end_time_s = observedEnd;
    audit.complete_scoring_window = completeWindow;
    audit.detail = "DATAFLASH_SCORING_WINDOW_MODE_COVERAGE_PASS";
    if ~audit.pass, audit.detail = "DATAFLASH_SCORING_WINDOW_MODE_COVERAGE_FAILED"; end
catch ME
    audit.detail = "MODE_AUDIT_ERROR: "+string(ME.message);
end
writeJson(fullfile(runDir,"mode_scoring_audit.json"),audit);
end

function [expectedDuration,manualDuration,otherDuration] = addDuration( ...
        mode,expected,duration,expectedDuration,manualDuration,otherDuration)
if mode == expected
    expectedDuration = expectedDuration+duration;
elseif mode == 0
    manualDuration = manualDuration+duration;
else
    otherDuration = otherDuration+duration;
end
end

function failure = classifyFailure(startPass,simulationPass,dataFlashPass, ...
        modePass,packet,safety,atrpPass,readback,onlineSafetyAbort, ...
        modeDropout,modeSession)
if ~startPass, failure = "SITL_CRASH";
elseif stringFieldOr(modeSession,"failure_reason","") == "STARTUP_TIMEOUT"
    failure = "STARTUP_TIMEOUT";
elseif nestedStringFieldOr(modeSession,"live_mode_monitor", ...
        "completion_class","") == "INCOMPLETE_TIMEOUT"
    failure = "INCOMPLETE_TIMEOUT";
elseif modeDropout, failure = "MODE_DROPOUT";
elseif onlineSafetyAbort, failure = "ENVELOPE_VIOLATION";
elseif ~modePass, failure = "MODE_CHANGE_FAIL";
elseif ~simulationPass, failure = "AIRCRAFT_DIVERGENCE";
elseif ~dataFlashPass, failure = "LOG_MISSING";
elseif ~packet.pass, failure = "INTERFACE_FAIL";
elseif ~safety.pass, failure = string(safety.failure_reason);
elseif ~atrpPass, failure = "LOG_MISSING";
elseif ~all(readback.Pass), failure = "PARAMETER_READBACK_FAIL";
else, failure = "";
end

function value = nestedStringFieldOr(s,parent,name,default)
value = default;
if isstruct(s) && isfield(s,parent) && isstruct(s.(parent)) && ...
        isfield(s.(parent),name)
    value = string(s.(parent).(name));
end
end
end

function closeBridge(P)
try ardupilot_sitl_controller("close",P); catch, end
end

function safeStop(root,runDir,distro)
try
    uav.invokePowerShell(fullfile(root,"scripts","sitl","stop_sitl_wsl.ps1"), ...
        ["-RunDirectory",runDir,"-Distro",distro]);
catch
end
end

function value = fieldOr(s,name,default)
if isstruct(s) && isfield(s,name), value = logical(s.(name)); else, value = default; end
end

function value = nestedFieldOr(s,parent,name,default)
if isstruct(s) && isfield(s,parent) && isstruct(s.(parent)) && ...
        isfield(s.(parent),name)
    value = logical(s.(parent).(name));
else
    value = default;
end
end

function value = numericFieldOr(s,name,default)
if isstruct(s) && isfield(s,name), value = double(s.(name)); else, value = default; end
end

function value = stringFieldOr(s,name,default)
if isstruct(s) && isfield(s,name), value = string(s.(name)); else, value = default; end
end

function value = completionClass(modeSession,requestedMode)
if requestedMode ~= "AUTOTUNE"
    value = "NOT_APPLICABLE"; return
end
value = "FAILED_OTHER";
if isfield(modeSession,"live_mode_monitor")
    live = modeSession.live_mode_monitor;
    if isfield(live,"completion_class")
        value = string(live.completion_class);
    elseif isfield(live,"safety_abort") && logical(live.safety_abort)
        value = "ABORTED_SAFETY";
    elseif isfield(live,"failure_reason") && ...
            string(live.failure_reason) == "INCOMPLETE_TIMEOUT"
        value = "INCOMPLETE_TIMEOUT";
    end
end
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function writeJson(filePath,value)
fid = fopen(filePath,"w"); if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end
