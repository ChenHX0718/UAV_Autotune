function physical = surface_targets(P,axisName,commandDirection)
%SURFACE_TARGETS Select actual surface extremes by moment sign.
% Channel order: throttle, left aileron, right aileron, elevator, rudder.

axisName = lower(string(axisName));
desiredSign = sign(double(commandDirection));
if desiredSign == 0
    error("UAVV541:ZeroDirection","Control-authority direction cannot be zero.");
end
physical = double(P.trim.actuator(:));
switch axisName
    case "roll"
        positive = [P.limits.delta_LT(2),P.limits.delta_RT(1)];
        negative = [P.limits.delta_LT(1),P.limits.delta_RT(2)];
        positiveEffect = P.aero.Cl_da*0.5*(positive(1)-positive(2));
        if sign(positiveEffect) == desiredSign
            selected = positive;
        else
            selected = negative;
        end
        physical(2:3) = selected;
    case "pitch"
        endpoints = P.limits.delta_e;
        effect = P.aero.Cm_de*(endpoints-P.trim.delta_e);
        physical(4) = chooseEndpoint(endpoints,effect,desiredSign,"pitch");
    case "yaw"
        endpoints = P.limits.delta_r;
        effect = P.aero.Cn_dr*endpoints;
        physical(5) = chooseEndpoint(endpoints,effect,desiredSign,"yaw");
    otherwise
        error("UAVV541:AuthorityAxis","Unsupported authority axis '%s'.",axisName);
end
end

function endpoint = chooseEndpoint(endpoints,effect,desiredSign,axisName)
candidates = find(sign(effect) == desiredSign);
if isempty(candidates)
    error("UAVV541:MomentDirection", ...
        "No %s endpoint produces the requested angular-acceleration sign.",axisName);
end
[~,local] = max(abs(effect(candidates)));
endpoint = endpoints(candidates(local));
end
