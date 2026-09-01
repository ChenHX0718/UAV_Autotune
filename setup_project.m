function setup_project()
%SETUP_PROJECT Configure the portable V5.4.1 MATLAB/Simulink environment.
root = string(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"matlab"),"-begin");
addpath(fullfile(root,"model"),"-begin");
addpath(fullfile(root,"tests"),"-begin");
if ~isfolder(fullfile(root,"results")), mkdir(fullfile(root,"results")); end
create_interface_buses();
fprintf("UAV Autotune V5.4.1 ready: %s\n",root);
end
