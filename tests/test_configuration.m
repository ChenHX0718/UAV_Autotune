function result = test_configuration()
%TEST_CONFIGURATION Validate the single V5.4.1 interface/configuration contract.
root = fileparts(fileparts(mfilename("fullpath")));
project = jsondecode(fileread(fullfile(root,"config","project.json")));
assert(string(project.version) == "5.4.1");
assert(double(project.native_autotune.default_level) == 2);
baseline = uav.readParamFile(fullfile(root,"config","autotune","baseline.param"));
level = baseline.Value(baseline.Name == "AUTOTUNE_LEVEL");
assert(isscalar(level) && level == 2);
for axisName = ["roll","pitch"]
    cfg = uav.loadConfiguration("native_"+axisName+"_autotune");
    assert(string(cfg.scenario.command_semantics) == "rc_normalized");
    assert(~isfield(cfg.scenario,"desired_internal_roll_deg"));
    assert(~isfield(cfg.scenario,"desired_internal_pitch_deg"));
end
result = struct("status","PASS","version","5.4.1", ...
    "default_autotune_level",2,"command_semantics","rc_normalized");
end
