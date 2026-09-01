function result = validateParameterReadback(snapshotFile,readbackFile,outputFile)
%VALIDATEPARAMETERREADBACK Enforce write -> read-back -> compare.
arguments
    snapshotFile (1,1) string
    readbackFile (1,1) string
    outputFile (1,1) string
end
requested = readParamFile(snapshotFile);
if ~isfile(readbackFile)
    result = table(requested.Name,requested.Value,nan(height(requested),1), ...
        false(height(requested),1),repmat("READBACK_MISSING",height(requested),1), ...
        'VariableNames',{'Name','Requested','ReadBack','Pass','Detail'});
    writetable(result,outputFile);
    return
end
actual = readtable(readbackFile,"TextType","string");
actual.Name = strtrim(string(actual.Name));
if ~isnumeric(actual.Value), actual.Value = str2double(string(actual.Value)); end
readBack = nan(height(requested),1);
pass = false(height(requested),1);
detail = strings(height(requested),1);
for index = 1:height(requested)
    match = find(actual.Name == requested.Name(index),1,"last");
    if isempty(match)
        detail(index) = "PARAMETER_NOT_REPORTED";
        continue
    end
    readBack(index) = actual.Value(match);
    tolerance = max(1e-6,1e-6*abs(requested.Value(index)));
    pass(index) = abs(readBack(index)-requested.Value(index)) <= tolerance;
    if pass(index), detail(index) = "MATCH"; else, detail(index) = "VALUE_MISMATCH"; end
end
result = table(requested.Name,requested.Value,readBack,pass,detail, ...
    'VariableNames',{'Name','Requested','ReadBack','Pass','Detail'});
writetable(result,outputFile);
end

function tableOut = readParamFile(filePath)
opts = delimitedTextImportOptions("NumVariables",2);
opts.Delimiter = ',';
opts.VariableNames = ["Name","Value"];
opts.VariableTypes = ["string","double"];
opts.ExtraColumnsRule = "ignore";
tableOut = rmmissing(readtable(filePath,opts));
tableOut.Name = strtrim(tableOut.Name);
end
