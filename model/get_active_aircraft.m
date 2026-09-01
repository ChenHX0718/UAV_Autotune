function aircraftId = get_active_aircraft()
%GET_ACTIVE_AIRCRAFT Return the aircraft selected for this project copy.
root = string(fileparts(mfilename("fullpath")));
path = fullfile(root,"active_aircraft.txt");
if isfile(path)
    aircraftId = strtrim(string(fileread(path)));
else
    aircraftId = "UAV_A";
end
if strlength(aircraftId) == 0
    aircraftId = "UAV_A";
end
end
