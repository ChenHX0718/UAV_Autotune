function root = projectRoot()
%PROJECTROOT Absolute UAV Autotune V5.4.1 project root.
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
