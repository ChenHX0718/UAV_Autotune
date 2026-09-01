function parameters = readParamFile(filePath)
%READPARAMFILE Read comma/whitespace ArduPilot parameters, ignoring comments.
arguments
    filePath (1,1) string
end
if ~isfile(filePath)
    error("UAVV541:ParameterFileMissing","Parameter file not found: %s",filePath);
end
lines = splitlines(string(fileread(filePath)));
name = strings(0,1); value = zeros(0,1);
for k = 1:numel(lines)
    line = strtrim(lines(k));
    if strlength(line) == 0 || startsWith(line,"#")
        continue
    end
    token = regexp(char(line),'^\s*([^,\s]+)\s*(?:,|\s)\s*([-+0-9.eE]+)', ...
        'tokens','once');
    if isempty(token)
        error("UAVV541:InvalidParameterLine", ...
            "Invalid parameter line %d in %s: %s",k,filePath,line);
    end
    parsed = str2double(token{2});
    if ~isfinite(parsed)
        error("UAVV541:InvalidParameterValue", ...
            "Non-finite parameter value on line %d in %s.",k,filePath);
    end
    name(end+1,1) = string(token{1}); %#ok<AGROW>
    value(end+1,1) = parsed; %#ok<AGROW>
end
parameters = table(name,value,'VariableNames',{'Name','Value'});
end
