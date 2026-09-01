function merged = mergeParameters(inputs)
%MERGEPARAMETERS Merge parameter files/tables in order; last value wins.
arguments (Repeating)
    inputs
end
merged = table(strings(0,1),zeros(0,1),'VariableNames',{'Name','Value'});
for inputIndex = 1:numel(inputs)
    item = inputs{inputIndex};
    if isempty(item), continue; end
    if istable(item)
        incoming = item(:,["Name","Value"]);
        incoming.Name = string(incoming.Name);
        incoming.Value = double(incoming.Value);
    elseif isstring(item) || ischar(item)
        incoming = uav.readParamFile(string(item));
    elseif isstruct(item)
        fields = string(fieldnames(item));
        values = zeros(numel(fields),1);
        for k = 1:numel(fields), values(k) = double(item.(fields(k))); end
        incoming = table(fields,values,'VariableNames',{'Name','Value'});
    else
        error("UAVV541:ParameterMergeType","Unsupported parameter input type.");
    end
    for row = 1:height(incoming)
        match = find(merged.Name == incoming.Name(row),1,"last");
        if isempty(match)
            merged = [merged;incoming(row,:)]; %#ok<AGROW>
        else
            merged.Value(match) = incoming.Value(row);
        end
    end
end
end
