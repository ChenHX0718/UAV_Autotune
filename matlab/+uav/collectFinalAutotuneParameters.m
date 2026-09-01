function parameters = collectFinalAutotuneParameters(runDirectory,baseFile,axisName,outputFile,options)
%COLLECTFINALAUTOTUNEPARAMETERS Promote only DataFlash last-value read-back.
arguments
    runDirectory (1,1) string
    baseFile (1,1) string
    axisName (1,1) string
    outputFile (1,1) string
    options.AutotuneLevel (1,1) double = NaN
end
readbackFile = fullfile(runDirectory,"parameter_readback.csv");
if ~isfile(readbackFile)
    error("UAVV541:ReadbackMissing","Cannot promote parameters without read-back.");
end
parameters = uav.readParamFile(baseFile);
actual = readtable(readbackFile,"TextType","string");
actual.Name = strtrim(string(actual.Name));
if ~isnumeric(actual.Value), actual.Value = str2double(string(actual.Value)); end
mutable = uav.autotuneMutableParameters(axisName);
for name = mutable(:)'
    row = find(actual.Name == name,1,"last");
    if isempty(row) || ~isfinite(actual.Value(row))
        error("UAVV541:ReadbackMissing", ...
            "Final AUTOTUNE parameter %s is missing from DataFlash read-back.",name);
    end
    parameters = uav.mergeParameters(parameters, ...
        table(name,actual.Value(row),'VariableNames',{'Name','Value'}));
end
level = options.AutotuneLevel;
snapshotFile = fullfile(runDirectory,"parameter_snapshot.param");
if ~isfinite(level) && isfile(snapshotFile)
    snapshot = uav.readParamFile(snapshotFile);
    row = find(snapshot.Name == "AUTOTUNE_LEVEL",1,"last");
    if ~isempty(row), level = snapshot.Value(row); end
end
if ~isfinite(level)
    error("UAVV541:AutotuneLevelMissing", ...
        "The runtime AUTOTUNE_LEVEL is absent; params_after cannot be self-describing.");
end
parameters = uav.mergeParameters(parameters,table("AUTOTUNE_LEVEL",level, ...
    'VariableNames',{'Name','Value'}));
uav.writeParamFile(outputFile,parameters,Header= ...
    "V5.4.1 official Finished + DataFlash read-back; runtime AUTOTUNE_LEVEL retained");
end
