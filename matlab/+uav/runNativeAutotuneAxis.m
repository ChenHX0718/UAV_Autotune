function result = runNativeAutotuneAxis(axisName,options)
%RUNNATIVEAUTOTUNEAXIS One isolated official-Finished AUTOTUNE run.
arguments
    axisName (1,1) string {mustBeMember(axisName,["roll","pitch"])}
    options.Level (1,1) double {mustBeInteger,mustBeInRange(options.Level,1,10)}
    options.Cycles (1,1) double {mustBeInteger,mustBePositive}
    options.BaseParameterFile (1,1) string
    options.OutputParameterFile (1,1) string
    options.Distro (1,1) string = "Ubuntu-24.04"
    options.Category (1,1) string = fullfile("v5_4_1","autotune")
    options.Tag (1,1) string = "formal"
    options.ActuatorFidelity (1,1) string = "ENGINEERING"
    options.SensorFidelity (1,1) string = "ENGINEERING"
    options.RandomSeed (1,1) double = 42
end

setup_project;
axisName = lower(axisName);
assertCampaignActive(options.Category);
design = uav.generateExcitation(axisName, ...
    AutotuneLevel=options.Level,Cycles=options.Cycles, ...
    ParameterFile=options.BaseParameterFile);
axisMask = 1;
if axisName == "pitch", axisMask = 2; end
overrides = struct("AUTOTUNE_AXES",axisMask, ...
    "AUTOTUNE_LEVEL",options.Level,"AUTOTUNE_OPTIONS",0, ...
    "YAW_RATE_ENABLE",0);
run = uav.runScenario(design.scenario_name,Distro=options.Distro, ...
    ParameterFiles=options.BaseParameterFile,ParameterOverrides=overrides, ...
    RequestedMode="AUTOTUNE",Tag=options.Tag,Category=options.Category, ...
    AllowNativeReplay=axisName=="pitch", ...
    ActuatorFidelity=options.ActuatorFidelity, ...
    SensorFidelity=options.SensorFidelity,RandomSeed=options.RandomSeed);
parsed = uav.parseNativeAutotuneLog(string(run.run_directory),Axis=axisName);
passed = run.overall == "PASS" && parsed.status == "PASS" && ...
    string(run.autotune_completion_class) == "COMPLETE_OFFICIAL_FINISHED";
legality = table;
if passed
    parameters = uav.collectFinalAutotuneParameters( ...
        string(run.run_directory),options.BaseParameterFile,axisName, ...
        options.OutputParameterFile,AutotuneLevel=options.Level);
    legality = uav.validateNativeParameterLegality(parameters);
    writetable(legality,fullfile(string(run.run_directory), ...
        "FINAL_PARAMETER_LEGALITY.csv"));
    passed = all(legality.ReplayAllowed);
end
failure = "";
if run.overall ~= "PASS"
    failure = string(run.failure_reason);
elseif parsed.status ~= "PASS"
    failure = string(parsed.failure_reason);
elseif string(run.autotune_completion_class) ~= "COMPLETE_OFFICIAL_FINISHED"
    failure = string(run.autotune_completion_class);
elseif ~passed
    failure = "PARAMETER_LEGALITY_FAIL";
end
result = struct("axis",axisName,"level",options.Level, ...
    "status",passFail(passed),"failure_reason",failure,"run",run, ...
    "parse",parsed,"legality",legality,"design",design, ...
    "parameter_file",string(options.OutputParameterFile));
if ~passed, result.parameter_file = ""; end
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function assertCampaignActive(category)
% Refuse to launch any later trial in a campaign that was invalidated while
% an earlier long-running trial was still completing.
root = uav.projectRoot();
resultRoot = fullfile(root,"results");
candidate = fullfile(resultRoot,category);
while startsWith(string(candidate),string(resultRoot), ...
        "IgnoreCase",true)
    marker = fullfile(candidate,"INVALIDATED.json");
    if isfile(marker)
        error("UAVV541:CampaignInvalidated", ...
            "Refusing to launch a run below invalidated campaign %s",candidate);
    end
    parent = fileparts(candidate);
    if string(parent) == string(candidate), break; end
    candidate = parent;
end
end
