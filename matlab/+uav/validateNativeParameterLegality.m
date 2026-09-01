function validation = validateNativeParameterLegality(parameters)
%VALIDATENATIVEPARAMETERLEGALITY Enforce pinned-commit metadata on output.
arguments
    parameters table
end
validation = uav.validateParameterSet(parameters);
disabledFilter = endsWith(validation.Name,"_RATE_FLTE") & ...
    validation.Requested == 0;
validation.Pass(disabledFilter) = true;
validation.Detail(disabledFilter) = "LEGAL_COMPILED_DISABLE_VALUE";
mutable = unique([uav.autotuneMutableParameters("roll"); ...
    uav.autotuneMutableParameters("pitch")]);
nativeWarning = ~validation.Pass & ismember(validation.Name,mutable) & ...
    validation.MetadataFound & validation.RangeDeclared & ...
    validation.Detail == "OUTSIDE_FIRMWARE_RANGE";
validation = addvars(validation,nativeWarning,validation.Pass|nativeWarning, ...
    'NewVariableNames',{'NativeMetadataWarning','ReplayAllowed'});
end
