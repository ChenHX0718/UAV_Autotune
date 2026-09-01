function P = apply_aircraft_definition(P,A)
%APPLY_AIRCRAFT_DEFINITION Apply and validate non-UAV_A aircraft data.
% The validation intentionally requires every aircraft-specific field so a
% new UAV cannot silently inherit values from UAV_A.

requireStructFields(A,"limits",fieldnames(P.limits));
requireStructFields(A,"actuator",fieldnames(P.actuator));
requireStructFields(A,"prop",["bus_voltage","efficiency_scale"]);

% Every pre-existing ArduPlane field except the two derived cruise-speed
% fields must be explicitly supplied for a new aircraft.
apRequired = string(fieldnames(P.ap));
apRequired = setdiff(apRequired,["SCALING_SPEED","AIRSPEED_CRUISE"]);
requireStructFields(A,"ap",apRequired);

P.mass = A.mass;
P.inertia = A.inertia;
P.geometry.span = A.geometry.span;
P.geometry.area = A.geometry.area;
P.geometry.chord = A.geometry.chord;
P.geometry.xflr5_to_body = A.geometry.xflr5_to_body;
P.geometry.cg_xflr5 = A.geometry.cg_xflr5(:);
P.geometry.cg_body = P.geometry.xflr5_to_body * P.geometry.cg_xflr5;
P.geometry.cg = P.geometry.cg_body;
P.geometry.aero_moment_reference_body = P.geometry.cg_body;
P.limits = merge_struct_recursive(P.limits,A.limits);
P.actuator = merge_struct_recursive(P.actuator,A.actuator);
P.prop = merge_struct_recursive(P.prop,A.prop);
P.ap = merge_struct_recursive(P.ap,A.ap);
P.ardupilot.target_version = string(A.ardupilot.target_version);

if ~isfield(A,"battery") || ~isfield(A.battery,"enable")
    error("UAV:AircraftDefinitionIncomplete","A.battery.enable must be explicitly set.");
end
if logical(A.battery.enable)
    requireStructFields(A,"battery",fieldnames(P.battery));
    P.battery = merge_struct_recursive(P.battery,A.battery);
    batteryScalars = [P.battery.series_cells;P.battery.capacity_Ah; ...
        P.battery.initial_soc;P.battery.initial_loaded_voltage_V; ...
        P.battery.internal_resistance_ohm;P.battery.min_voltage_V; ...
        P.battery.max_voltage_V];
    if any(~isfinite(batteryScalars)) || isempty(P.battery.soc_grid) || ...
            isempty(P.battery.ocv_per_cell_V) || ...
            numel(P.battery.soc_grid) ~= numel(P.battery.ocv_per_cell_V)
        error("UAV:AircraftDefinitionIncomplete", ...
            "Battery model is enabled but battery data are incomplete/invalid.");
    end
else
    P.battery.enable = false;
end

if isfield(A,"overrides")
    P = merge_struct_recursive(P,A.overrides);
end

requiredFinite = [P.mass;P.inertia(:);P.geometry.span;P.geometry.area; ...
    P.geometry.chord;P.geometry.cg_xflr5(:);P.actuator.time_constant(:); ...
    P.actuator.rate_limit(:);P.actuator.pwm_min(:);P.actuator.pwm_trim(:); ...
    P.actuator.pwm_max(:);P.prop.bus_voltage];
if any(~isfinite(requiredFinite))
    error("UAV:AircraftDefinitionIncomplete", ...
        "Aircraft definition still contains NaN/Inf in required physical fields.");
end
if any(P.actuator.pwm_min >= P.actuator.pwm_trim) || ...
        any(P.actuator.pwm_trim >= P.actuator.pwm_max)
    error("UAV:AircraftDefinitionInvalid", ...
        "Each PWM trim must be strictly between its min and max.");
end
apNames = fieldnames(P.ap);
for k = 1:numel(apNames)
    value = P.ap.(apNames{k});
    if isnumeric(value) && any(~isfinite(value(:)))
        error("UAV:AircraftDefinitionIncomplete", ...
            "P.ap.%s remains NaN/Inf for this aircraft.",apNames{k});
    end
end
end

function requireStructFields(A,section,names)
if ~isfield(A,section) || ~isstruct(A.(section))
    error("UAV:AircraftDefinitionIncomplete","Missing A.%s section.",section);
end
names = string(names(:));
for k = 1:numel(names)
    if ~isfield(A.(section),char(names(k)))
        error("UAV:AircraftDefinitionIncomplete", ...
            "New aircraft must explicitly define A.%s.%s (no UAV_A inheritance).", ...
            section,names(k));
    end
end
end
