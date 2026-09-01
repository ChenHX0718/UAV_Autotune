function [thrust, powerW] = uav_propulsion_model(P, throttle, Va, rho, busVoltage)
%UAV_PROPULSION_MODEL Shared propulsion model used by trim and Simulink S-function.

if nargin < 5 || isempty(busVoltage)
    busVoltage = P.prop.bus_voltage;
end
busVoltage = max(double(busVoltage), 0);

throttle = min(max(throttle, P.limits.throttle(1)), P.limits.throttle(2));
Va = max(Va, 0);
rho = max(rho, 0.1);
powerW = NaN;

switch lower(string(P.prop.mode))
    case "bench_multispeed"
        %% Electrical power from cruise-calibrated Ueff relation
        ueff = max(throttle * busVoltage, 0);
        xmin = P.prop.ueff_measured_min;
        xmax = P.prop.ueff_measured_max;
        a = P.prop.power_scale;
        n = P.prop.power_exponent;

        if ueff <= xmin
            pmin = a*xmin^n;
            if xmin > 0
                powerW = pmin*(ueff/xmin)^P.prop.low_ueff_exponent;
            else
                powerW = 0;
            end
        elseif ueff <= xmax
            powerW = a*ueff^n;
        else
            % Conservative tangent continuation above measured electrical
            % power. This is intentionally milder than extending ~Ueff^3.
            pmax = a*xmax^n;
            dpdu = n*a*xmax^(n-1);
            powerW = pmax + dpdu*(ueff-xmax);
        end
        powerW = max(powerW,0);

        %% Thrust from electrical power and airspeed
        % Main measured domain begins around 7.7 m/s.  In/above that range,
        % use eta_p = T*V/P and therefore T = eta_p*P/V.  This gives a much
        % more physical high-speed continuation than a hand-picked linear
        % speed factor.
        vMin = P.prop.airspeed_measured_min;
        if Va >= vMin
            eta = P.prop.eta0 + P.prop.eta_per_W*powerW + ...
                P.prop.eta_per_mps*Va;
            eta = min(max(eta,P.prop.eta_min),P.prop.eta_max);
            thrust = eta*powerW/max(Va,0.1);
        else
            % Low-speed bounded continuation.  It is not a static-thrust
            % identification and should not be interpreted as one.
            etaAtMin = P.prop.eta0 + P.prop.eta_per_W*powerW + ...
                P.prop.eta_per_mps*vMin;
            etaAtMin = min(max(etaAtMin,P.prop.eta_min),P.prop.eta_max);
            thrustAtMin = etaAtMin*powerW/vMin;
            if Va <= 0.1
                lowFactor = P.prop.low_speed_thrust_factor_max;
            else
                lowFactor = sqrt(vMin/Va);
                lowFactor = min(max(lowFactor,1.0), ...
                    P.prop.low_speed_thrust_factor_max);
            end
            thrust = thrustAtMin*lowFactor;
        end

        densityFactor = (rho/P.env.rho0)^P.prop.rho_exponent;
        thrust = thrust*densityFactor;

    case "table"
        thrust = interp2(P.prop.V_grid, P.prop.throttle_grid, ...
            P.prop.thrust_table, Va, throttle, "linear");
        if ~isfinite(thrust)
            thrust = 0;
        end

    otherwise
        densityFactor = (rho/P.env.rho0)^P.prop.rho_exponent;
        speedFactor = max(P.prop.min_speed_factor,1-P.prop.speed_loss*Va);
        thrust = P.prop.max_static_thrust*throttle^1.35* ...
            densityFactor*speedFactor;
end

efficiencyScale = 1.0;
if isfield(P.prop,"efficiency_scale")
    efficiencyScale = max(P.prop.efficiency_scale,0);
end
thrust = max(thrust*efficiencyScale,0);
end
