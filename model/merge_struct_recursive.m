function out = merge_struct_recursive(base,override)
%MERGE_STRUCT_RECURSIVE Recursively replace fields from override.
out = base;
if isempty(override), return; end
names = fieldnames(override);
for k = 1:numel(names)
    name = names{k};
    if isfield(out,name) && isstruct(out.(name)) && isstruct(override.(name))
        out.(name) = merge_struct_recursive(out.(name),override.(name));
    else
        out.(name) = override.(name);
    end
end
end
