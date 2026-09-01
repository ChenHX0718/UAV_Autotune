function [P,parameterTable] = applyParamFile(P,paramFile)
%APPLYPARAMFILE Apply the frozen Rank1 gains to the aircraft structure.
arguments
    P struct
    paramFile (1,1) string
end
if ~isfile(paramFile)
    error("UAVV51:ParameterFileNotFound","Parameter file not found: %s",paramFile);
end
opts = delimitedTextImportOptions("NumVariables",2);
opts.DataLines = [1,Inf];
opts.Delimiter = ',';
opts.VariableNames = ["Name","Value"];
opts.VariableTypes = ["string","double"];
opts.ExtraColumnsRule = "ignore";
parameterTable = rmmissing(readtable(paramFile,opts));
for index = 1:height(parameterTable)
    name = strtrim(parameterTable.Name(index));
    if ~isfield(P.ap,name)
        error("UAVV51:UnsupportedParameter", ...
            "Aircraft parameter structure has no field for %s.",name);
    end
    P.ap.(name) = parameterTable.Value(index);
end
end
