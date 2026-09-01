function W = set_active_aircraft(aircraftId)
%SET_ACTIVE_AIRCRAFT Select which isolated aircraft workspace is used.
W = uav_workspace(aircraftId,false);
if ~isfolder(W.aircraft_root)
    error("UAV:AircraftWorkspaceMissing", ...
        "Aircraft workspace does not exist: %s\nRun create_new_aircraft('%s') first.", ...
        W.aircraft_root,aircraftId);
end
manifest = read_aircraft_workspace_manifest(W);
if string(manifest.aircraft_id) ~= string(aircraftId)
    error("UAV:WorkspaceManifestMismatch", ...
        "Workspace manifest says '%s', requested '%s'.", ...
        string(manifest.aircraft_id),string(aircraftId));
end
root = string(fileparts(mfilename("fullpath")));
fid = fopen(fullfile(root,"active_aircraft.txt"),"w");
if fid < 0, error("UAV:ActiveAircraftWriteFailed","Cannot write active_aircraft.txt"); end
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,"%s\n",aircraftId);
clear cleanup
fprintf("Active aircraft set to %s\n",aircraftId);
end
