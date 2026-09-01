function W = create_new_aircraft(aircraftId,varargin)
%CREATE_NEW_AIRCRAFT Create a CLEAN isolated workspace for a new UAV.
%
%   create_new_aircraft("UAV_B")
%   create_new_aircraft("UAV_B","MakeActive",true)
%
% Safety rule: no UAV_A input data, results or SITL EEPROM are
% copied.  The new aircraft cannot run until aircraft_definition.m is filled
% and config_complete is deliberately set to true.

p = inputParser;
p.addParameter("MakeActive",true,@(x)islogical(x) || isnumeric(x));
p.parse(varargin{:});
W = uav_workspace(aircraftId,false);
if isfolder(W.aircraft_root)
    existing = dir(W.aircraft_root);
    existing = existing(~ismember({existing.name},{'.','..'}));
    if ~isempty(existing)
        error("UAV:AircraftAlreadyExists", ...
            "Workspace already exists and is not empty: %s",W.aircraft_root);
    end
end
W = uav_workspace(aircraftId,true);
write_aircraft_workspace_manifest(W,false);
root = string(fileparts(mfilename("fullpath")));
template = fullfile(root,"aircraft_template","aircraft_definition_template.m");
if ~isfile(template)
    error("UAV:AircraftTemplateMissing","Missing template: %s",template);
end
copyfile(template,W.definition_file);
writeInputReadme(W);
if logical(p.Results.MakeActive)
    set_active_aircraft(aircraftId);
end
fprintf("\nCreated clean aircraft workspace: %s\n",W.aircraft_root);
fprintf("Next steps:\n");
fprintf("  1) Edit %s\n",W.definition_file);
fprintf("  2) Put XFLR5 data in %s\n",W.aero_data);
fprintf("  3) Put propulsion data in %s\n",W.prop_data);
fprintf("  4) Put this aircraft's Mission Planner .param/log data in %s\n",W.flight_data);
fprintf("  5) Set A.config_complete = true only after checking every required field.\n");
fprintf("  6) Run verify_aircraft_workspace('%s') before simulation.\n",aircraftId);
end

function writeInputReadme(W)
path = fullfile(W.input_root,"README_INPUT_DATA.txt");
fid = fopen(path,"w");
if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,[ ...
    "AIRCRAFT INPUT DATA ONLY - %s\n\n" ...
    "aero_data     : XFLR5 aerodynamic/stability data for THIS aircraft\n" ...
    "prop_data     : propulsion bench/model data for THIS aircraft\n" ...
    "battery_data  : battery data for THIS aircraft if used\n" ...
    "flight_data   : Mission Planner .param, logs and calibration data for THIS aircraft\n\n" ...
    "DO NOT copy results, final_delivery or sitl_runtime from another UAV.\n"], ...
    W.aircraft_id);
clear cleanup
end
