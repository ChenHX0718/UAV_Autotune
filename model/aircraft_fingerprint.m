function [fingerprint,manifest] = aircraft_fingerprint(P)
%AIRCRAFT_FINGERPRINT Stable SHA-256 identity for aircraft/config/input data.
% Computer paths and output files are deliberately excluded.
S = struct;
S.schema = 4;
S.aircraft_id = char(P.meta.aircraft_id);
S.model_version = char(P.meta.model_version);
S.core_revision = char(P.meta.core_revision);
S.mass = P.mass;
S.inertia = P.inertia;
S.geometry = P.geometry;
S.limits = P.limits;
S.actuator = P.actuator;
S.battery = P.battery;
S.ap = P.ap;
S.env = P.env;
S.sensor = P.sensor;
S.sim = P.sim;
S.aero_mode = P.aero.mode;
S.prop_operating = struct("mode",P.prop.mode, ...
    "bus_voltage",P.prop.bus_voltage, ...
    "efficiency_scale",P.prop.efficiency_scale);
S.input_hashes = struct;
S.input_hashes.aero_data = hashDirectory(P.paths.aero_data);
S.input_hashes.prop_data = hashDirectory(P.paths.prop_data);
S.input_hashes.battery_data = hashDirectory(P.paths.battery_data);
if isfield(P,"mp") && isfield(P.mp,"vehicle_parameter_file") && ...
        isfile(P.mp.vehicle_parameter_file)
    S.input_hashes.flight_parameter_file = hashFile(P.mp.vehicle_parameter_file);
else
    S.input_hashes.flight_parameter_file = "MISSING";
end
% Raw flight logs can be very large. Their identified/entered parameters are
% already present in P and therefore fingerprinted; raw *.BIN files are not
% re-hashed on every uav_config call.
payload = jsonencode(S);
fingerprint = sha256Bytes(unicode2native(payload,"UTF-8"));
manifest = S;
manifest.fingerprint = fingerprint;
end

function out = hashDirectory(folder)
folder = string(folder);
if ~isfolder(folder)
    out = "MISSING";
    return
end
files = recursiveFiles(folder);
if isempty(files)
    out = "EMPTY";
    return
end
records = strings(numel(files),1);
for k = 1:numel(files)
    relative = erase(string(files(k)),folder + filesep);
    records(k) = replace(relative,"\\","/") + ":" + hashFile(files(k));
end
records = sort(records);
out = sha256Bytes(unicode2native(strjoin(records,newline),"UTF-8"));
end

function files = recursiveFiles(folder)
listing = dir(folder);
files = strings(0,1);
for k = 1:numel(listing)
    name = string(listing(k).name);
    if name == "." || name == "..", continue; end
    path = fullfile(folder,name);
    if listing(k).isdir
        files = [files; recursiveFiles(path)]; %#ok<AGROW>
    else
        files(end+1,1) = string(path); %#ok<AGROW>
    end
end
end

function out = hashFile(path)
fid = fopen(path,"rb");
if fid < 0, error("UAV:FingerprintReadFailed","Cannot read %s",path); end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid,Inf,"*uint8");
clear cleanup
out = sha256Bytes(bytes);
end

function out = sha256Bytes(bytes)
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(typecast(uint8(bytes(:)),'int8'));
digest = typecast(md.digest(),'uint8');
out = lower(string(reshape(dec2hex(digest,2).',1,[])));
end
