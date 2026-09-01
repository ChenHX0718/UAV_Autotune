function report = verify_aircraft_workspace(aircraftId)
%VERIFY_AIRCRAFT_WORKSPACE Preflight data-isolation check for one aircraft.
if nargin < 1 || strlength(string(aircraftId)) == 0
    aircraftId = get_active_aircraft();
end
W = uav_workspace(aircraftId,false);
manifest = read_aircraft_workspace_manifest(W);
checks = strings(0,1); status = strings(0,1);
[checks,status] = add(checks,status,"workspace manifest aircraft_id", ...
    string(manifest.aircraft_id) == string(aircraftId));
[checks,status] = add(checks,status,"aero_data folder non-empty",folderHasFiles(W.aero_data));
[checks,status] = add(checks,status,"prop_data folder non-empty",folderHasFiles(W.prop_data));
[checks,status] = add(checks,status,"flight_data folder non-empty",folderHasFiles(W.flight_data));
try
    P = uav_config(aircraftId);
    [checks,status] = add(checks,status,"uav_config loads",true);
    [checks,status] = add(checks,status,"fingerprint generated", ...
        strlength(string(P.meta.aircraft_fingerprint)) == 64);
catch ME
    P = struct; %#ok<NASGU>
    checks(end+1) = "uav_config loads"; status(end+1) = "FAIL: " + string(ME.message);
end
report = table(checks(:),status(:),'VariableNames',{'check','status'});
disp(report)
if any(startsWith(report.status,"FAIL"))
    error("UAV:AircraftWorkspacePreflightFailed", ...
        "Aircraft workspace preflight failed for %s.",aircraftId);
end
fprintf("Aircraft workspace %s is isolated and ready.\n",aircraftId);
end

function tf = folderHasFiles(folder)
if ~isfolder(folder), tf = false; return; end
listing = dir(folder);
tf = any(~[listing.isdir]);
end
function [c,s] = add(c,s,name,pass)
c(end+1) = name;
if pass, s(end+1) = "PASS"; else, s(end+1) = "FAIL"; end
end
