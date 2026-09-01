function result = test_model_load()
%TEST_MODEL_LOAD Load and update the retained four-axis Simulink model.
root = fileparts(fileparts(mfilename("fullpath")));
modelName = "UAV_Autotune_Model_4Axis";
P = uav_config("UAV_A",13); %#ok<NASGU>
P.controller.backend = "test_direct_actuator";
P.control_authority.profile = struct("axis","roll", ...
    "command_fraction",0,"command_direction",1, ...
    "pulse_start_s",0,"pulse_end_s",1,"test_only",true);
assignin("base","P",P);
load_system(fullfile(root,"model",modelName+".slx"));
cleanup = onCleanup(@() close_system(modelName,0)); %#ok<NASGU>
set_param(modelName,"SimulationCommand","update");
result = struct("status","PASS","model",modelName);
end
