function A = load_aircraft_definition(W)
%LOAD_AIRCRAFT_DEFINITION Load a non-UAV_A aircraft definition safely.
if ~isfile(W.definition_file)
    error("UAV:AircraftDefinitionMissing", ...
        "Missing %s. Run create_new_aircraft('%s').",W.definition_file,W.aircraft_id);
end
A = struct; %#ok<NASGU>
run(W.definition_file);
if ~exist("A","var") || ~isstruct(A)
    error("UAV:AircraftDefinitionInvalid", ...
        "aircraft_definition.m must create struct A.");
end
if ~isfield(A,"config_complete") || ~logical(A.config_complete)
    error("UAV:AircraftDefinitionIncomplete", ...
        ["Aircraft %s is intentionally locked because A.config_complete is false. " ...
         "Fill and check aircraft_definition.m before running the model."],W.aircraft_id);
end
validateattributes(A.mass,{'numeric'},{'scalar','positive','finite'});
validateattributes(A.inertia,{'numeric'},{'size',[3,3],'finite'});
for name = ["span","area","chord"]
    if ~isfield(A.geometry,name) || ~isfinite(A.geometry.(name)) || A.geometry.(name) <= 0
        error("UAV:AircraftDefinitionInvalid","geometry.%s must be positive and finite.",name);
    end
end
if any(~isfinite(A.geometry.cg_xflr5))
    error("UAV:AircraftDefinitionInvalid","geometry.cg_xflr5 contains NaN/Inf.");
end
if ~isfield(A,"flight") || any(~isfinite([A.flight.cruise_speed, ...
        A.flight.stall_speed])) || A.flight.stall_speed >= A.flight.cruise_speed
    error("UAV:AircraftDefinitionInvalid", ...
        "A.flight must explicitly define valid cruise and stall speeds.");
end
if ~isfield(A,"flight_parameter_file") || strlength(string(A.flight_parameter_file)) == 0
    error("UAV:AircraftDefinitionInvalid","flight_parameter_file must name this aircraft's .param file.");
end
if ~isfield(A,"ardupilot") || strlength(string(A.ardupilot.target_version)) == 0
    error("UAV:AircraftDefinitionInvalid","ardupilot.target_version must be set.");
end
end
