function result = start_autotune(action,options)
%START_AUTOTUNE Single public entry point for UAV Autotune V5.4.1.
arguments
    action (1,1) string {mustBeMember(action, ...
        ["repeatability","axis","physical_validation", ...
         "level_screen","report","regression"])}
    options.Axis (1,1) string {mustBeMember(options.Axis, ...
        ["roll","pitch","yaw","all"])} = "roll"
    options.Level (1,1) double {mustBeInteger,mustBeInRange(options.Level,1,10)} = 2
    options.Count (1,1) double {mustBeInteger,mustBePositive} = 3
    options.Distro (1,1) string = "Ubuntu-24.04"
    options.ActuatorFidelity (1,1) string = "ENGINEERING"
    options.SensorFidelity (1,1) string = "ENGINEERING"
    options.RandomSeed (1,1) double = 42
end

setup_project();
root = uav.projectRoot();
switch action
    case "repeatability"
        result = uav.runAutotuneRepeatability( ...
            Level=options.Level,Count=options.Count,Distro=options.Distro, ...
            ActuatorFidelity=options.ActuatorFidelity, ...
            SensorFidelity=options.SensorFidelity,RandomSeed=options.RandomSeed);
    case "axis"
        if options.Axis == "all" || options.Axis == "yaw"
            error("UAVV541:AxisEntry", ...
                "Native AUTOTUNE axis runs support roll or pitch only.");
        end
        baseline = fullfile(root,"config","autotune","baseline.param");
        outputFile = fullfile(root,"results","v5_4_1","manual", ...
            options.Axis+"_params_after.param");
        result = uav.runNativeAutotuneAxis(options.Axis, ...
            Level=options.Level,Cycles=30,BaseParameterFile=baseline, ...
            OutputParameterFile=outputFile,Distro=options.Distro, ...
            Category=fullfile("v5_4_1","manual"),Tag="formal", ...
            ActuatorFidelity=options.ActuatorFidelity, ...
            SensorFidelity=options.SensorFidelity,RandomSeed=options.RandomSeed);
    case "physical_validation"
        axesToRun = options.Axis;
        if axesToRun == "all", axesToRun = ["roll","pitch","yaw"]; end
        result = uav.runPhysicalControlAuthority(Axes=axesToRun);
    case "level_screen"
        result = uav.generateLevelFeasibility();
    case "report"
        result = uav.generateValidationReport();
    case "regression"
        result = run_regression_suite();
end
end
