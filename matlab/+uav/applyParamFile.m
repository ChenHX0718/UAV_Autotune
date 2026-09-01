function [P,parameterTable] = applyParamFile(P,paramFile)
%APPLYPARAMFILE Apply model-relevant fields from an ArduPilot parameter file.
arguments
    P struct
    paramFile (1,1) string
end
if ~isfile(paramFile)
    error("UAVV541:ParameterFileNotFound","Parameter file not found: %s",paramFile);
end
opts = delimitedTextImportOptions("NumVariables",2);
opts.DataLines = [1,Inf];
opts.Delimiter = ',';
opts.VariableNames = ["Name","Value"];
opts.VariableTypes = ["string","double"];
opts.ExtraColumnsRule = "ignore";
allParameters = rmmissing(readtable(paramFile,opts));
applied = false(height(allParameters),1);
for index = 1:height(allParameters)
    name = strtrim(allParameters.Name(index));
    if isfield(P.ap,name)
        P.ap.(name) = allParameters.Value(index);
        applied(index) = true;
    end
end
parameterTable = allParameters(applied,:);
end
