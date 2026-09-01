function summary = run_regression_suite(options)
%RUN_REGRESSION_SUITE Execute retained V5.4.1 regression checks.
arguments
    options.IncludeSimulation (1,1) logical = true
end
setup_project();
root = uav.projectRoot();
names = ["configuration","step_overshoot","surface_direction", ...
    "actuator","model_load","sensor"];
functions = {@test_configuration,@test_step_overshoot, ...
    @test_surface_direction_chain,@test_actuator_model, ...
    @test_model_load,@test_sensor_model};
status = strings(numel(names),1);
detail = strings(numel(names),1);
for k = 1:numel(names)
    if ~options.IncludeSimulation && ismember(names(k),["model_load","sensor"])
        status(k) = "NOT_RUN";
        detail(k) = "Simulation checks disabled by caller.";
        continue
    end
    try
        functions{k}();
        status(k) = "PASS";
        detail(k) = "";
    catch ME
        status(k) = "FAIL";
        detail(k) = string(ME.identifier)+": "+string(ME.message);
    end
end
summary = table(names',status,detail, ...
    'VariableNames',{'Check','Status','Detail'});
outDir = fullfile(root,"results","code_cleanup");
if ~isfolder(outDir), mkdir(outDir); end
writetable(summary,fullfile(outDir,"REGRESSION_RESULTS.csv"));
disp(summary);
end
