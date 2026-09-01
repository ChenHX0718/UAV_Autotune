function summary = runSmokeTest(options)
%RUNSMOKETEST Run infrastructure/mapping/sign/scale/dynamics/safety tests.
arguments
    options.Backend (1,1) string = "wsl"
    options.Distro (1,1) string = "auto"
    options.WindowsExecutable (1,1) string = ""
    options.MissionPlannerHome (1,1) string = ""
    options.Speedup (1,1) double = NaN
end
scenarios = ["fbwa_roll_step","fbwa_roll_scale","fbwa_pitch_step"];
verdict = strings(numel(scenarios),1);
runDirectory = strings(numel(scenarios),1);
detail = strings(numel(scenarios),1);
for index = 1:numel(scenarios)
    try
        result = v51.runScenario(scenarios(index),Backend=options.Backend, ...
            Distro=options.Distro,WindowsExecutable=options.WindowsExecutable, ...
            MissionPlannerHome=options.MissionPlannerHome,Speedup=options.Speedup);
        verdict(index) = result.overall;
        runDirectory(index) = result.run_directory;
    catch ME
        verdict(index) = "FAIL";
        detail(index) = string(getReport(ME,"extended","hyperlinks","off"));
    end
end
summary = table(scenarios',verdict,runDirectory,detail, ...
    'VariableNames',{'Scenario','Verdict','RunDirectory','Detail'});
writetable(summary,fullfile(v51.projectRoot(),"results","smoke_test_summary.csv"));
if any(verdict ~= "PASS")
    error("UAVV51:SmokeTestFailed", ...
        "One or more V5.1 smoke-test layers failed. See results/smoke_test_summary.csv.");
end
end
