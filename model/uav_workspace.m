function W = uav_workspace(aircraftId,createIfMissing)
%UAV_WORKSPACE Resolve the isolated workspace for one aircraft.
%
% Every aircraft gets independent input data. Generated results, final exports
% and SITL runtime state are kept below the project-level results directory.
% Core MATLAB/Simulink code remains shared at project root.

if nargin < 1 || strlength(string(aircraftId)) == 0
    aircraftId = get_active_aircraft();
end
if nargin < 2
    createIfMissing = true;
end
aircraftId = string(aircraftId);
validId = ~isempty(regexp(char(aircraftId), ...
    '^[A-Za-z0-9][A-Za-z0-9_-]*$','once'));
if ~validId
    error("UAV:InvalidAircraftId", ...
        "Aircraft ID may contain only letters, numbers, '_' and '-': %s",aircraftId);
end
root = string(fileparts(mfilename("fullpath")));
projectRoot = string(fileparts(root));
W = struct;
W.root = root;
W.project_root = projectRoot;
W.aircraft_id = aircraftId;
W.aircraft_root = fullfile(root,"aircraft",aircraftId);
W.input_root = fullfile(W.aircraft_root,"input");
W.aero_data = fullfile(W.input_root,"aero_data");
W.prop_data = fullfile(W.input_root,"prop_data");
W.battery_data = fullfile(W.input_root,"battery_data");
W.flight_data = fullfile(W.input_root,"flight_data");
W.results = fullfile(projectRoot,"results","v5_4_1","aircraft",aircraftId);
W.final_delivery = fullfile(W.results,"final_delivery");
W.sitl_runtime = fullfile(W.results,"sitl_runtime");
W.reports = fullfile(W.results,"logs");
W.definition_file = fullfile(W.aircraft_root,"aircraft_definition.m");
W.manifest_file = fullfile(W.aircraft_root,"workspace_manifest.json");
folders = [W.aircraft_root,W.input_root,W.aero_data,W.prop_data, ...
    W.battery_data,W.flight_data,W.results,W.final_delivery, ...
    W.sitl_runtime,W.reports];
if createIfMissing
    for f = folders
        if ~isfolder(f), mkdir(f); end
    end
end
end
