function validation = validateParameterReadback(snapshotFile,readbackFile,mutableNames)
%VALIDATEPARAMETERREADBACK Last-value read-back with declared AUTOTUNE changes.
arguments
    snapshotFile (1,1) string
    readbackFile (1,1) string
    mutableNames string = strings(0,1)
end
requested = uav.readParamFile(snapshotFile);
readBack = nan(height(requested),1); pass = false(height(requested),1);
detail = repmat("READBACK_MISSING",height(requested),1);
if isfile(readbackFile)
    actual = readtable(readbackFile,"TextType","string");
    actual.Name = strtrim(string(actual.Name));
    if ~isnumeric(actual.Value), actual.Value = str2double(string(actual.Value)); end
    for row = 1:height(requested)
        match = find(actual.Name == requested.Name(row),1,"last");
        if isempty(match), continue; end
        readBack(row) = actual.Value(match);
        tolerance = max(1e-6,1e-6*abs(requested.Value(row)));
        same = abs(readBack(row)-requested.Value(row)) <= tolerance;
        mutable = any(mutableNames == requested.Name(row));
        pass(row) = same || mutable;
        if same
            detail(row) = "MATCH";
        elseif mutable
            detail(row) = "NATIVE_AUTOTUNE_CHANGED";
        else
            detail(row) = "VALUE_MISMATCH";
        end
    end
end
validation = table(requested.Name,requested.Value,readBack,pass,detail, ...
    'VariableNames',{'Name','Requested','ReadBack','Pass','Detail'});
end
