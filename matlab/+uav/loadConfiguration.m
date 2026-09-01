function cfg = loadConfiguration(scenarioName)
%LOADCONFIGURATION Load separated project/aircraft/simulation/scenario data.
arguments
    scenarioName (1,1) string
end
root = uav.projectRoot();
cfg.project = readJson(fullfile(root,"config","project.json"));
cfg.aircraft = readJson(fullfile(root,"config","aircraft", ...
    string(cfg.project.aircraft_id)+".json"));
cfg.simulation = readJson(fullfile(root,"config","simulation","default.json"));
scenarioFile = fullfile(root,"config","scenarios",scenarioName+".json");
if ~isfile(scenarioFile)
    error("UAVV541:ScenarioNotFound","Scenario does not exist: %s",scenarioFile);
end
cfg.scenario = readJson(scenarioFile);
required = ["name","flight_mode","command_semantics","axis", ...
    "stop_time_s","time_s"];
for field = required
    if ~isfield(cfg.scenario,field)
        error("UAVV541:InvalidScenario","Scenario %s lacks %s.", ...
            scenarioName,field);
    end
end
semantics = lower(string(cfg.scenario.command_semantics));
if semantics ~= "rc_normalized"
    error("UAVV541:AmbiguousCommandSemantics", ...
        "Formal V5.4.1 scenarios must use rc_normalized commands.");
end
axisName = lower(string(cfg.scenario.axis));
if ~ismember(axisName,["roll","pitch"])
    error("UAVV541:InvalidScenario", ...
        "Formal native AUTOTUNE supports roll or pitch, not %s.",axisName);
end
fieldName = "rc_"+axisName+"_normalized";
if ~isfield(cfg.scenario,fieldName)
    error("UAVV541:InvalidScenario","Scenario %s lacks %s.", ...
        scenarioName,fieldName);
end
end

function value = readJson(filePath)
value = jsondecode(fileread(filePath));
end
