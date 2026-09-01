function result = evaluateSafetyEnvelope(runDir,options)
%EVALUATESAFETYENVELOPE Check full-aircraft physical and numerical bounds.
arguments
    runDir (1,1) string
    options.ConfigurationFile (1,1) string = fullfile(uav.projectRoot(), ...
        "config","benchmark","native_autotune_validation.json")
end
cfg = jsondecode(fileread(options.ConfigurationFile));
limit = cfg.safety;
filePath = fullfile(runDir,"simulation_data.csv");
checks = ["finite_state","roll","pitch","airspeed","aoa","sideslip", ...
    "altitude","angular_rate","servo_saturation"]';
pass = false(size(checks)); observed = nan(size(checks)); threshold = nan(size(checks));
detail = strings(size(checks));
if ~isfile(filePath)
    result = struct("pass",false,"failure_reason","LOG_MISSING", ...
        "checks",table(checks,pass,observed,threshold,detail));
    return
end
data = readtable(filePath);
numeric = data{:,vartype("numeric")};
pass(1) = all(isfinite(numeric),"all"); observed(1) = nnz(~isfinite(numeric));
threshold(1) = 0; detail(1) = sprintf("non-finite samples=%d",observed(1));

observed(2) = max(abs(data.roll_deg)); threshold(2) = limit.roll_abs_max_deg;
pass(2) = observed(2) <= threshold(2);
observed(3) = max([max(data.pitch_deg),-min(data.pitch_deg)]);
threshold(3) = max(limit.pitch_max_deg,-limit.pitch_min_deg);
pass(3) = max(data.pitch_deg) <= limit.pitch_max_deg && ...
    min(data.pitch_deg) >= limit.pitch_min_deg;
observed(4) = min(data.airspeed_mps); threshold(4) = limit.airspeed_min_mps;
pass(4) = observed(4) >= limit.airspeed_min_mps && ...
    max(data.airspeed_mps) <= limit.airspeed_max_mps;
observed(5) = max(abs(data.alpha_deg)); threshold(5) = limit.aoa_abs_max_deg;
pass(5) = observed(5) <= threshold(5);
observed(6) = max(abs(data.beta_deg)); threshold(6) = limit.sideslip_abs_max_deg;
pass(6) = observed(6) <= threshold(6);
observed(7) = min(data.altitude_m); threshold(7) = limit.altitude_min_m;
pass(7) = observed(7) >= threshold(7);
observed(8) = max(abs([data.p_deg_s;data.q_deg_s;data.r_deg_s]));
threshold(8) = limit.angular_rate_abs_max_deg_s; pass(8) = observed(8) <= threshold(8);
surfacePwm = [data.protocol_aileron_left_pwm_us,data.protocol_aileron_right_pwm_us, ...
    data.protocol_elevator_pwm_us,data.protocol_rudder_pwm_us];
observed(9) = mean(any(surfacePwm <= 1105 | surfacePwm >= 1895,2));
threshold(9) = limit.saturation_fraction_max; pass(9) = observed(9) <= threshold(9);
for k = 2:numel(checks)
    detail(k) = sprintf("observed=%.9g threshold=%.9g",observed(k),threshold(k));
end
checkTable = table(checks,pass,observed,threshold,detail, ...
    'VariableNames',{'Check','Pass','Observed','Threshold','Detail'});
writetable(checkTable,fullfile(runDir,"safety_envelope.csv"));
if ~pass(1)
    failure = "AIRCRAFT_DIVERGENCE";
elseif ~pass(9)
    failure = "ACTUATOR_SATURATION_EXCESSIVE";
elseif ~all(pass)
    failure = "ENVELOPE_VIOLATION";
else
    failure = "";
end
result = struct("pass",all(pass),"failure_reason",failure,"checks",checkTable);
end
