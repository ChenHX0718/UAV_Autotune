function [selected,validation] = writeDefaults(P,outputFile,extraParameters,options)
%WRITEDEFAULTS Merge the V5.4.1 baseline with validated run inputs.
arguments
    P struct
    outputFile (1,1) string
    extraParameters table = table(strings(0,1),zeros(0,1), ...
        'VariableNames',{'Name','Value'})
    options.AllowNativeReplay (1,1) logical = false
end
write_ardupilot_sitl_defaults(P,outputFile);
base = uav.readParamFile(outputFile);
transport = table(["SERIAL1_PROTOCOL";"SERIAL1_BAUD"; ...
    "SERIAL2_PROTOCOL";"SERIAL2_BAUD";"LOG_DISARMED";"FLTMODE_CH"; ...
    "ARSPD_TYPE";"ARSPD_USE";"ARSPD_SKIP_CAL"], ...
    [2;115;2;115;1;0;100;1;1], ...
    'VariableNames',{'Name','Value'});
selected = uav.mergeParameters(base,transport,extraParameters);
validation = validateCommitMetadata(extraParameters);
allowed = validation.Pass;
if options.AllowNativeReplay
    allowed = validation.ReplayAllowed;
end
if any(~allowed)
    bad = join(validation.Name(~allowed),", ");
    error("UAVV541:ParameterValidation", ...
        "Parameters failed commit metadata validation: %s",bad);
end
uav.writeParamFile(outputFile,selected);
end

function validation = validateCommitMetadata(parameters)
if isempty(parameters)
    validation = table(strings(0,1),zeros(0,1),false(0,1),strings(0,1), ...
        false(0,1),false(0,1),'VariableNames', ...
        {'Name','Value','Pass','Detail','NativeMetadataWarning','ReplayAllowed'});
    return
end
raw = uav.validateParameterSet(parameters);
pass = raw.Pass;
detail = raw.Detail;
% Commit defaults intentionally use zero to disable the error filter even
% though the generated UI metadata advertises only its positive range.
disabledFilter = endsWith(raw.Name,"_RATE_FLTE") & raw.Requested == 0;
pass(disabledFilter) = true;
detail(disabledFilter) = "LEGAL_COMPILED_DISABLE_VALUE";
validation = table(raw.Name,raw.Requested,pass,detail, ...
    'VariableNames',{'Name','Value','Pass','Detail'});
mutable = unique([uav.autotuneMutableParameters("roll"); ...
    uav.autotuneMutableParameters("pitch")]);
nativeWarning = ~validation.Pass & ismember(validation.Name,mutable) & ...
    raw.MetadataFound & raw.RangeDeclared & ...
    validation.Detail == "OUTSIDE_FIRMWARE_RANGE";
validation = addvars(validation,nativeWarning,validation.Pass|nativeWarning, ...
    'NewVariableNames',{'NativeMetadataWarning','ReplayAllowed'});
end
