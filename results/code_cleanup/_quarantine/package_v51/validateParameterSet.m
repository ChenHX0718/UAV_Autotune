function validation = validateParameterSet(parameterInput,options)
%VALIDATEPARAMETERSET Check values against exact-commit firmware metadata.
arguments
    parameterInput
    options.MetadataFile (1,1) string = fullfile(v51.projectRoot(), ...
        "config","ardupilot","apm.pdef.xml")
    options.OutputFile (1,1) string = ""
end

requested = readParameters(parameterInput);
metadata = v51.loadParameterMetadata(options.MetadataFile);
n = height(requested);
found = false(n,1); rangeDeclared = false(n,1); inRange = false(n,1);
enumDeclared = false(n,1); allowedValue = false(n,1);
incrementAligned = false(n,1); minimum = nan(n,1); maximum = nan(n,1);
increment = nan(n,1); units = strings(n,1); detail = strings(n,1);

for index = 1:n
    match = find(metadata.Name == requested.Name(index),1,"first");
    if isempty(match)
        detail(index) = "METADATA_NOT_FOUND";
        continue
    end
    found(index) = true;
    minimum(index) = metadata.Minimum(match);
    maximum(index) = metadata.Maximum(match);
    increment(index) = metadata.Increment(match);
    units(index) = metadata.Units(match);
    rangeDeclared(index) = isfinite(minimum(index)) && isfinite(maximum(index));
    inRange(index) = ~rangeDeclared(index) || ...
        (requested.Value(index) >= minimum(index)-1e-9 && ...
        requested.Value(index) <= maximum(index)+1e-9);

    codes = split(metadata.AllowedValues(match),";");
    codes = codes(strlength(codes) > 0);
    enumDeclared(index) = ~isempty(codes);
    allowedValue(index) = ~enumDeclared(index) || any(abs( ...
        str2double(codes)-requested.Value(index)) <= 1e-9);

    if isfinite(increment(index)) && increment(index) > 0
        origin = 0;
        if rangeDeclared(index), origin = minimum(index); end
        steps = (requested.Value(index)-origin)/increment(index);
        incrementAligned(index) = abs(steps-round(steps)) <= 1e-6;
    else
        incrementAligned(index) = true;
    end

    if ~inRange(index)
        detail(index) = "OUTSIDE_FIRMWARE_RANGE";
    elseif ~allowedValue(index)
        detail(index) = "NOT_IN_FIRMWARE_ENUM";
    elseif ~rangeDeclared(index) && ~enumDeclared(index)
        detail(index) = "METADATA_FOUND_NO_NUMERIC_CONSTRAINT";
    elseif ~incrementAligned(index)
        detail(index) = "LEGAL_VALUE_NON_UI_INCREMENT";
    else
        detail(index) = "LEGAL";
    end
end

pass = found & inRange & allowedValue;
validation = table(requested.Name,requested.Value,found,rangeDeclared, ...
    minimum,maximum,inRange,enumDeclared,allowedValue,increment, ...
    incrementAligned,units,pass,detail,'VariableNames', ...
    {'Name','Requested','MetadataFound','RangeDeclared','Minimum','Maximum', ...
    'InFirmwareRange','EnumDeclared','AllowedValue','Increment', ...
    'IncrementAligned','Units','Pass','Detail'});
if strlength(options.OutputFile) > 0
    writetable(validation,options.OutputFile);
end
end

function requested = readParameters(parameterInput)
if istable(parameterInput)
    requested = parameterInput(:,["Name","Value"]);
elseif ischar(parameterInput) || (isstring(parameterInput) && isscalar(parameterInput))
    opts = delimitedTextImportOptions("NumVariables",2);
    opts.Delimiter = ",";
    opts.VariableNames = ["Name","Value"];
    opts.VariableTypes = ["string","double"];
    opts.ExtraColumnsRule = "ignore";
    requested = rmmissing(readtable(string(parameterInput),opts));
else
    error("UAVV51:ParameterInput", ...
        "Parameter input must be a Name/Value table or .param path.");
end
requested.Name = strtrim(string(requested.Name));
if ~isnumeric(requested.Value), requested.Value = str2double(string(requested.Value)); end
end
