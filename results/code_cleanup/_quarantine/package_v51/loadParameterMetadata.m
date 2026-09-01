function metadata = loadParameterMetadata(metadataFile)
%LOADPARAMETERMETADATA Read commit-pinned ArduPlane parameter metadata.
arguments
    metadataFile (1,1) string = fullfile(v51.projectRoot(), ...
        "config","ardupilot","apm.pdef.xml")
end
if ~isfile(metadataFile)
    error("UAVV51:ParameterMetadataMissing", ...
        "Parameter metadata does not exist: %s",metadataFile);
end

document = xmlread(char(metadataFile));
nodes = document.getElementsByTagName("param");
n = nodes.getLength;
name = strings(n,1); humanName = strings(n,1); description = strings(n,1);
minimum = nan(n,1); maximum = nan(n,1); increment = nan(n,1);
units = strings(n,1); allowedValues = strings(n,1);

for index = 1:n
    node = nodes.item(index-1);
    rawName = string(char(node.getAttribute("name")));
    if contains(rawName,":"), rawName = extractAfter(rawName,":"); end
    name(index) = rawName;
    humanName(index) = string(char(node.getAttribute("humanName")));
    description(index) = string(char(node.getAttribute("documentation")));

    fields = node.getElementsByTagName("field");
    for fieldIndex = 1:fields.getLength
        field = fields.item(fieldIndex-1);
        fieldName = string(char(field.getAttribute("name")));
        fieldValue = strtrim(string(char(field.getTextContent())));
        switch fieldName
            case "Range"
                values = sscanf(char(fieldValue),"%f");
                if numel(values) >= 2
                    minimum(index) = values(1);
                    maximum(index) = values(2);
                end
            case "Increment"
                increment(index) = str2double(fieldValue);
            case "Units"
                units(index) = fieldValue;
        end
    end

    values = node.getElementsByTagName("value");
    codes = strings(values.getLength,1);
    for valueIndex = 1:values.getLength
        codes(valueIndex) = string(char(values.item(valueIndex-1).getAttribute("code")));
    end
    allowedValues(index) = strjoin(codes,";");
end

metadata = table(name,humanName,minimum,maximum,increment,units, ...
    allowedValues,description,'VariableNames', ...
    {'Name','HumanName','Minimum','Maximum','Increment','Units', ...
    'AllowedValues','Description'});
[~,uniqueIndex] = unique(metadata.Name,"stable");
metadata = metadata(uniqueIndex,:);
end
