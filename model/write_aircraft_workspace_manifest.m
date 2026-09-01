function manifest = write_aircraft_workspace_manifest(W,legacyScopedReuseAllowed)
%WRITE_AIRCRAFT_WORKSPACE_MANIFEST Create/update aircraft workspace identity.
if nargin < 2, legacyScopedReuseAllowed = false; end
manifest = struct;
manifest.schema_version = 2;
manifest.aircraft_id = char(W.aircraft_id);
manifest.created_or_updated = char(datetime("now","Format","yyyy-MM-dd'T'HH:mm:ss"));
manifest.legacy_scoped_reuse_allowed = logical(legacyScopedReuseAllowed);
manifest.note = [ ...
    "Files under this workspace belong only to this aircraft. " ...
    "Do not copy results or SITL EEPROM into another aircraft workspace."];
text = jsonencode(manifest,"PrettyPrint",true);
fid = fopen(W.manifest_file,"w");
if fid < 0, error("UAV:ManifestWriteFailed","Cannot create %s",W.manifest_file); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid,text,"char");
clear cleanup
end
