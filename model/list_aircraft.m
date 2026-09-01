function T = list_aircraft()
%LIST_AIRCRAFT List isolated aircraft workspaces and active selection.
root = string(fileparts(mfilename("fullpath")));
base = fullfile(root,"aircraft");
if ~isfolder(base)
    T = table;
    return
end
listing = dir(base);
listing = listing([listing.isdir]);
listing = listing(~ismember({listing.name},{'.','..'}));
active = get_active_aircraft();
id = strings(0,1); isActive = false(0,1); manifestOK = false(0,1); legacyReuse = false(0,1);
for k = 1:numel(listing)
    name = string(listing(k).name);
    W = uav_workspace(name,false);
    id(end+1,1) = name; %#ok<AGROW>
    isActive(end+1,1) = name == active; %#ok<AGROW>
    try
        m = read_aircraft_workspace_manifest(W);
        manifestOK(end+1,1) = true; %#ok<AGROW>
        legacyReuse(end+1,1) = isfield(m,"legacy_scoped_reuse_allowed") && logical(m.legacy_scoped_reuse_allowed); %#ok<AGROW>
    catch
        manifestOK(end+1,1) = false; %#ok<AGROW>
        legacyReuse(end+1,1) = false; %#ok<AGROW>
    end
end
T = table(id,isActive,manifestOK,legacyReuse, ...
    'VariableNames',{'aircraft_id','active','manifest_ok','legacy_scoped_reuse_allowed'});
disp(T)
end
