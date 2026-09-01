function pwm = direct_actuator_pwm(P,time)
%DIRECT_ACTUATOR_PWM TEST ONLY plant-control-authority interface.
% This function is never used by Native AUTOTUNE. It exists only to
% identify plant control authority through the measured PWM actuator layer.

physical = double(P.trim.actuator(:));
profile = P.control_authority.profile;
if time >= profile.pulse_start_s && time < profile.pulse_end_s
    fraction = min(max(abs(profile.command_fraction),0),1);
    direction = sign(profile.command_direction);
    target = surface_targets(P,profile.axis,direction);
    physical(2:5) = physical(2:5) + ...
        fraction*(target(2:5)-physical(2:5));
end
[~,pwm] = uav_servo_mapping(P,physical,"command_to_pwm");
end
