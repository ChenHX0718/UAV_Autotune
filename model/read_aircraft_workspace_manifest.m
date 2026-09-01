function manifest = read_aircraft_workspace_manifest(W)
%READ_AIRCRAFT_WORKSPACE_MANIFEST Read and validate workspace identity.
if nargin < 1 || isempty(W)
    W = uav_workspace(get_active_aircraft(),false);
end
if ~isfile(W.manifest_file)
    error("UAV:WorkspaceManifestMissing", ...
        "Missing aircraft workspace manifest: %s",W.manifest_file);
end
manifest = jsondecode(fileread(W.manifest_file));
if ~isfield(manifest,"aircraft_id")
    error("UAV:WorkspaceManifestInvalid","Manifest has no aircraft_id: %s",W.manifest_file);
end
if string(manifest.aircraft_id) ~= string(W.aircraft_id)
    error("UAV:WorkspaceManifestMismatch", ...
        "Folder is %s but manifest belongs to %s.",W.aircraft_id,string(manifest.aircraft_id));
end
end
