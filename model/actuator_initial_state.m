function state = actuator_initial_state(P)
%ACTUATOR_INITIAL_STATE State for the engineering actuator model.

dt = double(P.actuator.sample_time_s);
historyLength = max(2,ceil(max(P.actuator.delay_s)/dt)+2);
initial = double(P.trim.actuator(:));
state.shaft = initial;
state.surface = initial;
state.rate = zeros(5,1);
state.saturated = zeros(5,1);
state.previous_pwm = double(P.actuator.pwm_trim(:));
state.target_history = repmat(initial,1,historyLength);
state.history_index = 1;
state.protocol_ready = ~isSITLBackend(P);
end

function tf = isSITLBackend(P)
tf = isfield(P,"controller") && isfield(P.controller,"backend") && ...
    string(P.controller.backend) == "ardupilot_sitl";
end
