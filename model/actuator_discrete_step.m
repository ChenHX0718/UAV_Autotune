function [state,diagnostic] = actuator_discrete_step(P,pwm,state)
%ACTUATOR_DISCRETE_STEP Measured mapping plus engineering dynamics.

dt = double(P.actuator.sample_time_s);
pwm = double(pwm(:));
if numel(pwm) ~= 5
    error("UAVV541:ActuatorInputSize","Expected five ordered PWM channels.");
end

% Plane's JSON backend emits 1500 us placeholders before the output
% functions and their non-1500 trims are active.  Holding configured trim
% through that short protocol-startup interval prevents the placeholder
% from being misinterpreted as a measured physical command.  The first
% non-placeholder surface frame permanently releases this gate.
if isfield(state,"protocol_ready") && ~state.protocol_ready
    placeholder = all(abs(pwm(2:5)-1500) <= 0.5) && ...
        any(abs(double(P.actuator.pwm_trim(2:5))-1500) > 0.5);
    if placeholder
        pwm(2:5) = double(P.actuator.pwm_trim(2:5));
    else
        state.protocol_ready = true;
    end
end

fidelity = actuatorFidelity(P);
if fidelity == "ideal"
    [target,boundedPwm] = uav_servo_mapping(P,pwm,"pwm_to_command");
    previous = state.surface;
    state.shaft = target;
    state.surface = target;
    state.rate = (target-previous)/dt;
    state.saturated = double(pwm <= P.actuator.pwm_min(:) | ...
        pwm >= P.actuator.pwm_max(:));
    state.previous_pwm = boundedPwm;
    diagnostic = struct("effective_pwm",boundedPwm,"mapped_target",target, ...
        "delayed_target",target,"fidelity",fidelity);
    return
end

deadband = double(P.actuator.deadband_pwm(:));
effectivePwm = pwm;
hold = abs(pwm-state.previous_pwm) <= deadband;
hold(1) = false;
effectivePwm(hold) = state.previous_pwm(hold);
[mappedTarget,boundedPwm] = uav_servo_mapping(P,effectivePwm,"pwm_to_command");
state.previous_pwm = boundedPwm;

historyLength = size(state.target_history,2);
writeIndex = mod(state.history_index-1,historyLength)+1;
state.target_history(:,writeIndex) = mappedTarget;
delayedTarget = zeros(5,1);
for channel = 1:5
    delaySamples = max(double(P.actuator.delay_s(channel)),0)/dt;
    whole = floor(delaySamples);
    fraction = delaySamples-whole;
    recentIndex = mod(writeIndex-whole-1,historyLength)+1;
    olderIndex = mod(writeIndex-whole-2,historyLength)+1;
    delayedTarget(channel) = (1-fraction)* ...
        state.target_history(channel,recentIndex) + fraction* ...
        state.target_history(channel,olderIndex);
end
state.history_index = mod(writeIndex,historyLength)+1;

tau = max(double(P.actuator.time_constant(:)),0);
firstOrderFraction = ones(5,1);
dynamic = tau > eps;
firstOrderFraction(dynamic) = 1-exp(-dt./tau(dynamic));
candidate = state.shaft + firstOrderFraction.*(delayedTarget-state.shaft);
requestedRate = (candidate-state.shaft)/dt;
positiveLimit = double(P.actuator.rate_positive(:));
negativeLimit = double(P.actuator.rate_negative(:));
limitedRate = min(max(requestedRate,-negativeLimit),positiveLimit);
state.shaft = state.shaft + dt*limitedRate;

limits = [P.limits.throttle;P.limits.delta_LT;P.limits.delta_RT; ...
    P.limits.delta_e;P.limits.delta_r];
previousSurface = state.surface;
state.surface = min(max(state.shaft,limits(:,1)),limits(:,2));
state.shaft = state.surface;
state.rate = (state.surface-previousSurface)/dt;
rateLimited = abs(limitedRate-requestedRate) > 1e-10;
mechanicalLimited = abs(state.surface-candidate) > 1e-10;
state.saturated = double(pwm <= P.actuator.pwm_min(:) | ...
    pwm >= P.actuator.pwm_max(:) | rateLimited | mechanicalLimited);

diagnostic = struct("effective_pwm",effectivePwm, ...
    "mapped_target",mappedTarget,"delayed_target",delayedTarget, ...
    "requested_rate",requestedRate,"limited_rate",limitedRate, ...
    "deadband_hold",hold,"fidelity",fidelity);
end

function fidelity = actuatorFidelity(P)
fidelity = "engineering";
if isfield(P,"fidelity") && isfield(P.fidelity,"actuator")
    fidelity = lower(string(P.fidelity.actuator));
elseif isfield(P,"interface") && isfield(P.interface,"actuator_fidelity")
    fidelity = lower(string(P.interface.actuator_fidelity));
end
if ismember(fidelity,["first_order","measured","stress"])
    fidelity = "engineering";
end
if ~ismember(fidelity,["ideal","engineering"])
    error("UAVV541:UnsupportedActuatorFidelity", ...
        "Unsupported actuator fidelity '%s'.",fidelity);
end
end
