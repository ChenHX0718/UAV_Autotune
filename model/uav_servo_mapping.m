function [physical, pwm] = uav_servo_mapping(P, values, mode)
%UAV_SERVO_MAPPING Common physical-command/PWM calibration for MIL and SITL.
% Channel order: throttle, left aileron, right aileron, elevator, rudder.

mode = lower(string(mode));
values = double(values(:));
if numel(values) ~= 5
    error("UAV:ServoMappingSize", ...
        "Servo mapping requires five ordered channels.");
end
limits = [P.limits.throttle; P.limits.delta_LT; P.limits.delta_RT; ...
    P.limits.delta_e; P.limits.delta_r];
pwmMin = double(P.actuator.pwm_min(:));
pwmMax = double(P.actuator.pwm_max(:));
channels = servo_channels(P);

switch mode
    case "command_to_pwm"
        physical = min(max(values,limits(:,1)),limits(:,2));
        pwm = zeros(5,1);
        pwm(1) = pwmMin(1) + physical(1) * ...
            (pwmMax(1)-pwmMin(1));
        for k = 2:5
            cfg = channels{k};
            physicalNormalized = normalizePhysical(rad2deg(physical(k)),cfg);
            basicNormalized = physicalNormalized/cfg.direction;
            [curveSorted,order] = sort(double( ...
                cfg.basic_deflection_normalized(:)));
            pwmSorted = double(cfg.PWM_breakpoints(order));
            pwm(k) = interp1(curveSorted,pwmSorted,basicNormalized,"linear");
        end
        quantum = max(double(P.actuator.pwm_quantization_us),1);
        pwm = round(pwm/quantum)*quantum;
        pwm = min(max(pwm,pwmMin),pwmMax);

    case "pwm_to_command"
        pwm = min(max(values,pwmMin),pwmMax);
        physical = zeros(5,1);
        physical(1) = (pwm(1)-pwmMin(1))/max(pwmMax(1)-pwmMin(1),1);
        for k = 2:5
            cfg = channels{k};
            boundedPwm = min(max(pwm(k),min(cfg.PWM_breakpoints)), ...
                max(cfg.PWM_breakpoints));
            basicNormalized = interp1(double(cfg.PWM_breakpoints(:)), ...
                double(cfg.basic_deflection_normalized(:)),boundedPwm,"linear");
            physicalNormalized = cfg.direction*basicNormalized;
            physical(k) = deg2rad(denormalizePhysical(physicalNormalized,cfg));
            physical(k) = min(max(physical(k),limits(k,1)),limits(k,2));
        end

    otherwise
        error("UAV:ServoMappingMode", ...
            "Unknown mode '%s'.",mode);
end
end

function value = normalizePhysical(deflectionDeg,cfg)
if deflectionDeg >= 0
    value = deflectionDeg/max(double(cfg.max_deflection_deg),eps);
else
    value = deflectionDeg/max(abs(double(cfg.min_deflection_deg)),eps);
end
value = min(max(value,-1),1);
end

function value = denormalizePhysical(normalized,cfg)
if normalized >= 0
    value = normalized*double(cfg.max_deflection_deg);
else
    value = normalized*abs(double(cfg.min_deflection_deg));
end
end
