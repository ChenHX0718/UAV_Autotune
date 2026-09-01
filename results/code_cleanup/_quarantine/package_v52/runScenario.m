function result = runScenario(scenarioName,options)
%RUNSCENARIO Execute one isolated, timestamped V5.2 experiment.
arguments
    scenarioName (1,1) string
    options.Backend (1,1) string = "wsl"
    options.Distro (1,1) string = "auto"
    options.WindowsExecutable (1,1) string = ""
    options.MissionPlannerHome (1,1) string = ""
    options.Speedup (1,1) double = NaN
    options.ParameterOverrides struct = struct
    options.ActuatorFidelity (1,1) string = ""
    options.SensorFidelity (1,1) string = ""
end
backend = lower(options.Backend);
if ~ismember(backend,["wsl","windows_compat"])
    error("UAVV52:Backend","Backend must be wsl or windows_compat.");
end
root = v52.projectRoot();
modelRoot = fullfile(root,"model");
addpath(fullfile(root,"matlab"),"-begin");
addpath(modelRoot,"-begin");
create_v52_buses();
cfg = v52.loadConfiguration(scenarioName);
if strlength(options.ActuatorFidelity) > 0
    cfg.simulation.actuator_fidelity = upper(options.ActuatorFidelity);
end
if strlength(options.SensorFidelity) > 0
    cfg.simulation.sensor_fidelity = upper(options.SensorFidelity);
end
if isfinite(options.Speedup)
    if options.Speedup <= 0
        error("UAVV52:Speedup","Speedup must be positive.");
    end
    cfg.simulation.speedup = options.Speedup;
end
runStamp = string(datetime("now","Format","yyyyMMdd_HHmmss"));
runDir = fullfile(root,"results","v5_2","runs", ...
    runStamp+"_"+scenarioName+"_"+backend);
mkdir(runDir);
mkdir(fullfile(runDir,"plots"));
diary(fullfile(runDir,"matlab_runner.log"));
diaryCleanup = onCleanup(@() diary("off")); %#ok<NASGU>
fprintf("V5.2 scenario %s started with backend %s.\n",scenarioName,backend);

if backend == "windows_compat" && strlength(options.WindowsExecutable) == 0
    candidate = fullfile(root,"..","UAV_Autotune_v5_0_SITL", ...
        "sitl","dependencies","PlaneStable","ArduPlane.exe");
    if isfile(candidate), options.WindowsExecutable = string(candidate); end
end
[P,selectedParameters] = v52.configureRun(cfg,runDir,backend, ...
    options.WindowsExecutable,options.ParameterOverrides);
parameterSnapshot = fullfile(runDir,"parameter_snapshot.param");
write_ardupilot_sitl_defaults_v52(P,parameterSnapshot);
P.controller.sitl.defaults_file_override = parameterSnapshot;
writetable(selectedParameters,fullfile(runDir,"selected_parameters.csv"));
copyfile(fullfile(root,"config","scenarios",scenarioName+".json"), ...
    fullfile(runDir,"scenario.json"));
copyfile(fullfile(root,"config","aircraft",string(cfg.aircraft.aircraft_id)+".json"), ...
    fullfile(runDir,"aircraft.json"));
copyfile(fullfile(root,"config","simulation","default.json"), ...
    fullfile(runDir,"simulation.json"));

if backend == "wsl"
    firmwareSource = "wsl_source_build";
else
    firmwareSource = "windows_compatibility_binary";
end
snapshot = struct("created",string(datetime("now","TimeZone","UTC")), ...
    "version","5.2","backend",backend,"scenario",scenarioName, ...
    "firmware_source",firmwareSource, ...
    "ardupilot_commit",string(cfg.project.ardupilot.commit), ...
    "matlab_version",string(version),"matlab_release",string(version("-release")), ...
    "json_udp_port",double(cfg.project.network.json_udp_port), ...
    "mission_planner_udp_port",double(cfg.project.network.mission_planner_udp_port), ...
    "base_step_s",double(cfg.simulation.base_step_s), ...
    "communication_step_s",double(cfg.project.timing.communication_step_s), ...
    "logging_step_s",double(cfg.simulation.logging_step_s), ...
    "speedup",double(cfg.simulation.speedup), ...
    "reset_strategy",P.v52.reset_strategy, ...
    "actuator_fidelity",P.v52.actuator_fidelity, ...
    "sensor_fidelity",P.v52.sensor_fidelity);
writeText(fullfile(runDir,"configuration_snapshot.json"), ...
    jsonencode(snapshot,"PrettyPrint",true));
resetEvidence = struct("model_initialization","fresh SimulationInput run", ...
    "plant_state","model initial conditions restored", ...
    "actuator_state","S-function InitializeConditions restored trim", ...
    "wind_state","model initial conditions restored", ...
    "controller_state","ArduPilot process restarted with --wipe", ...
    "timing_state","bridge recreated and counters reset", ...
    "strategy",P.v52.reset_strategy);
writeText(fullfile(runDir,"reset_evidence.json"), ...
    jsonencode(resetEvidence,"PrettyPrint",true));

if backend == "wsl"
    startScript = fullfile(root,"tools","start_sitl_wsl.ps1");
    v52.invokePowerShell(startScript,["-RunDirectory",runDir, ...
        "-DefaultsFile",parameterSnapshot,"-Distro",options.Distro, ...
        "-Speedup",string(cfg.simulation.speedup), ...
        "-RateHz",string(cfg.project.timing.sitl_rate_hz)]);
    wslCleanup = onCleanup(@() safeStopWsl(root,runDir,options.Distro));
end

modelName = string(cfg.project.model_name);
modelFile = fullfile(modelRoot,modelName+".slx");
cacheFolder = fullfile(runDir,"simulink_cache");
codegenFolder = fullfile(runDir,"simulink_codegen");
mkdir(cacheFolder); mkdir(codegenFolder);
Simulink.fileGenControl("set","CacheFolder",cacheFolder, ...
    "CodeGenFolder",codegenFolder,"createDir",true);
simulationError = "";
simulationPass = false;
bridgeCleanup = onCleanup(@() closeBridge()); %#ok<NASGU>
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
    v52.writeSimulationData(out,P,double(cfg.simulation.logging_step_s), ...
        fullfile(runDir,"simulation_data.csv"));
catch ME
    simulationError = string(getReport(ME,"extended","hyperlinks","off"));
    fprintf(2,"%s\n",simulationError);
end
closeBridge();
try close_system(modelName,0); catch, end
if backend == "wsl"
    safeStopWsl(root,runDir,options.Distro);
    clear wslCleanup
end
[dataFlashPass,dataFlashDetail] = v52.exportDataFlash(runDir,backend, ...
    options.Distro,options.MissionPlannerHome);

readback = v52.validateParameterReadback(parameterSnapshot, ...
    fullfile(runDir,"parameter_readback.csv"), ...
    fullfile(runDir,"parameter_validation.csv"));
result = v52.analyzeInterfaceRun(runDir,cfg,simulationPass,simulationError, ...
    dataFlashPass,dataFlashDetail,readback);
writeText(fullfile(runDir,"result.json"),jsonencode(result,"PrettyPrint",true));
fprintf("V5.2 interface verdict: %s; control rating: %s\n", ...
    result.interface_overall,result.control_rating);

    function closeBridge()
        try ardupilot_sitl_controller("close",P); catch, end
    end

end

function writeText(filePath,content)
fid = fopen(filePath,"w");
if fid < 0, error("UAVV52:FileWrite","Cannot write %s",filePath); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",content);
end

function safeStopWsl(root,runDir,distro)
stopScript = fullfile(root,"tools","stop_sitl_wsl.ps1");
try
    v52.invokePowerShell(stopScript,["-RunDirectory",runDir,"-Distro",distro]);
catch ME
    fprintf(2,"SITL stop warning: %s\n",ME.message);
end
end
