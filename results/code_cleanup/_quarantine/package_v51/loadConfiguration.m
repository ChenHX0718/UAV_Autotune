function cfg = loadConfiguration(scenarioName)
%LOADCONFIGURATION Load separated project/aircraft/simulation/scenario data.
arguments
    scenarioName (1,1) string
end
root = v51.projectRoot();
cfg.project = readJson(fullfile(root,"config","project.json"));
cfg.aircraft = readJson(fullfile(root,"config","aircraft", ...
    string(cfg.project.aircraft_id)+".json"));
cfg.simulation = readJson(fullfile(root,"config","simulation","default.json"));
scenarioFile = fullfile(root,"config","scenarios",scenarioName+".json");
if ~isfile(scenarioFile)
    error("UAVV51:ScenarioNotFound","Scenario does not exist: %s",scenarioFile);
end
cfg.scenario = readJson(scenarioFile);
if isfield(cfg.scenario,"status") && ...
        string(cfg.scenario.status) == "V5.2_FRAMEWORK_ONLY"
    error("UAVV51:V52ScenarioNotExecutable", ...
        "Scenario %s is a V5.2 framework placeholder, not a V5.1 test.",scenarioName);
end
end

function value = readJson(filePath)
value = jsondecode(fileread(filePath));
end
