function root = projectRoot()
%PROJECTROOT Absolute V5.1 root derived without a hard-coded drive or user.
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
