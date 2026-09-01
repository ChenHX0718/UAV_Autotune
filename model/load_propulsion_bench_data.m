function prop = load_propulsion_bench_data(dataFolder)
%LOAD_PROPULSION_BENCH_DATA Load cleaned multi-airspeed thrust-stand data.
%
% Data coverage supplied by the user:
%   Va ~= 7.7, 11.45 and 13.0 m/s
%   nominal supplies 22, 23.5 and 25 V
%   clean electrical-power range ~= 70-155 W
%
% IMPORTANT DATA QUALITY NOTES
% 1) Samples after programmable-supply collapse are already excluded from
%    propulsion_bench_multispeed_clean.csv.
% 2) The 11.45 m/s group has a systematic absolute-force inconsistency:
%    its TV/P efficiency has a large power-dependent bias compared with the
%    internally consistent 7.7 and 13 m/s groups.  It is therefore retained
%    as a validation/uncertainty set, but is not forced into the central
%    thrust fit.  This avoids teaching the simulator an artificial thrust
%    valley around 11-12 m/s.
% 3) Throttle-to-electrical-power calibration differs strongly between test
%    sessions.  Therefore the central throttle->power map is fitted only to
%    the 13 m/s group, which is the intended cruise neighborhood.  Measured
%    electrical power is used to identify the airspeed effect on thrust.

csvFile = fullfile(dataFolder, "propulsion_bench_multispeed_clean.csv");
assert(isfile(csvFile), "Missing propulsion bench data: %s", csvFile);
T = readtable(csvFile, VariableNamingRule="preserve");

Va = T.("airspeed_mid_mps");
ueff = T.("effective_voltage_V");
powerW = T.("power_W");
thrustN = T.("thrust_N");

valid = isfinite(Va) & isfinite(ueff) & isfinite(powerW) & isfinite(thrustN) & ...
    Va > 0 & ueff > 0 & powerW > 0 & thrustN > 0;
Va = Va(valid);
ueff = ueff(valid);
powerW = powerW(valid);
thrustN = thrustN(valid);

%% 1) Throttle + loaded bus voltage -> electrical power
% Use the 13 m/s group because it is the cruise operating neighborhood and
% has three repeatable voltage sweeps.  Ueff = throttle * loaded bus voltage.
refVa = 13.0;
refMask = abs(Va-refVa) < 0.25;
assert(nnz(refMask) >= 10, "Not enough 13 m/s propulsion points.");

cP = polyfit(log(ueff(refMask)), log(powerW(refMask)), 1);
prop.power_exponent = cP(1);
prop.power_scale = exp(cP(2));

powerFit = prop.power_scale .* ueff(refMask).^prop.power_exponent;
prop.fit_power_rmse_W = sqrt(mean((powerFit-powerW(refMask)).^2));
prop.fit_power_R2 = 1 - sum((powerFit-powerW(refMask)).^2) / ...
    sum((powerW(refMask)-mean(powerW(refMask))).^2);

prop.ueff_measured_min = min(ueff(refMask));
prop.ueff_measured_max = max(ueff(refMask));
prop.power_measured_min = min(powerW);
prop.power_measured_max = max(powerW);
prop.low_ueff_exponent = 3.0;

%% 2) Electrical power + airspeed -> thrust
% For a propeller in forward flight, a useful physically interpretable
% quantity is propulsive efficiency eta_p = T*Va/P_elec.  The 7.7 and 13 m/s
% groups are internally tight. Fit a mild plane:
%   eta_p = eta0 + etaP*P + etaV*Va
% and calculate T = eta_p*P/Va.
trustedMask = abs(Va-7.7) < 0.25 | abs(Va-13.0) < 0.25;
etaObs = thrustN(trustedMask).*Va(trustedMask)./powerW(trustedMask);
Xeta = [ones(nnz(trustedMask),1), powerW(trustedMask), Va(trustedMask)];
cEta = Xeta \ etaObs;
prop.eta0 = cEta(1);
prop.eta_per_W = cEta(2);
prop.eta_per_mps = cEta(3);

etaFit = Xeta*cEta;
thrustFit = etaFit .* powerW(trustedMask) ./ Va(trustedMask);
prop.fit_thrust_rmse_N = sqrt(mean((thrustFit-thrustN(trustedMask)).^2));
prop.fit_thrust_R2 = 1 - sum((thrustFit-thrustN(trustedMask)).^2) / ...
    sum((thrustN(trustedMask)-mean(thrustN(trustedMask))).^2);

% Quantify the systematic 11.45 m/s disagreement instead of hiding it.
midMask = abs(Va-11.45) < 0.25;
if any(midMask)
    etaMid = prop.eta0 + prop.eta_per_W.*powerW(midMask) + ...
        prop.eta_per_mps.*Va(midMask);
    thrustMidPred = etaMid.*powerW(midMask)./Va(midMask);
    midErr = thrustMidPred-thrustN(midMask);
    prop.validation_11p45_bias_N = mean(midErr);
    prop.validation_11p45_rmse_N = sqrt(mean(midErr.^2));
else
    prop.validation_11p45_bias_N = NaN;
    prop.validation_11p45_rmse_N = NaN;
end

%% Model settings and extrapolation policy
prop.mode = "bench_multispeed";      % bench_multispeed | analytic | table
prop.reference_airspeed = refVa;
prop.bus_voltage = 22.2;              % loaded in-flight voltage; set from log data
prop.airspeed_measured_min = min(Va);
prop.airspeed_measured_max = max(Va);
prop.thrust_measured_min = min(thrustN);
prop.thrust_measured_max = max(thrustN);

% High-speed extrapolation:
% Continue eta_p smoothly rather than applying an arbitrary linear thrust
% loss.  Since T = eta_p*P/V, thrust naturally drops roughly with 1/V.  Eta
% is bounded to prevent an unconstrained polynomial from becoming absurd.
prop.eta_min = 0.30;
prop.eta_max = 0.62;
prop.high_speed_soft_limit = 20.0;    % m/s; above this model is low-confidence

% Low-speed side is not the purpose of this dataset. A bounded continuation
% is provided so simulations remain numerically well behaved below 7.7 m/s.
prop.low_speed_thrust_factor_max = 1.35;
prop.rho_exponent = 0.7;
prop.roll_torque_per_thrust = 0.0;

% Legacy analytic fallback retained only for comparison/debugging.
prop.max_static_thrust = 30.0;        % N, legacy placeholder
prop.speed_loss = 0.025;
prop.min_speed_factor = 0.35;
prop.V_grid = [0 5 10 15 20 25];
prop.throttle_grid = [0 0.25 0.5 0.75 1.0];
[VMap, TMap] = meshgrid(prop.V_grid, prop.throttle_grid);
prop.thrust_table = prop.max_static_thrust .* TMap.^1.35 .* ...
    max(prop.min_speed_factor, 1-prop.speed_loss.*VMap);

prop.data_file = csvFile;
prop.data_point_count = numel(Va);
prop.thrust_fit_point_count = nnz(trustedMask);
prop.validation_point_count = nnz(midMask);
end
