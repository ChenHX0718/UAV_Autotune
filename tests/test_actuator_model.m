function result = test_actuator_model()
%TEST_ACTUATOR_MODEL Validate V5.4.1 static and dynamic actuator behavior.

root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"model"),"-begin");
outputDir = fullfile(root,"results","v5_4_1","validation","actuator");
if ~isfolder(outputDir), mkdir(outputDir); end
P = uav_config("UAV_A",13);
P.fidelity.actuator = "ENGINEERING";

surfaceNames = ["aileron_left","aileron_right","elevator","rudder"];
channelIndices = 2:5;
staticRows = table;
figure("Visible","off","Color","w","Position",[100,100,1000,700]);
tiledlayout(2,2,"TileSpacing","compact");
for item = 1:numel(surfaceNames)
    name = surfaceNames(item);
    cfg = P.servo.(name);
    pwm = double(cfg.PWM_breakpoints(:));
    rawMeasured = double(cfg.deflection_deg(:));
    modelPlant = zeros(size(pwm));
    for row = 1:numel(pwm)
        command = P.actuator.pwm_trim;
        command(channelIndices(item)) = pwm(row);
        physical = uav_servo_mapping(P,command,"pwm_to_command");
        modelPlant(row) = rad2deg(physical(channelIndices(item)));
    end
    modelRawConvention = modelPlant/cfg.installation_sign;
    measuredLimited = min(max(rawMeasured, ...
        cfg.min_deflection_deg/cfg.installation_sign), ...
        cfg.max_deflection_deg/cfg.installation_sign);
    if cfg.installation_sign < 0
        measuredLimited = min(max(rawMeasured, ...
            cfg.max_deflection_deg/cfg.installation_sign), ...
            cfg.min_deflection_deg/cfg.installation_sign);
    end
    errorDeg = modelRawConvention-measuredLimited;
    staticRows = [staticRows;table(name,string(cfg.data_source), ...
        sqrt(mean(errorDeg.^2)),mean(abs(errorDeg)),max(abs(errorDeg)), ...
        cfg.neutral_pwm,cfg.min_pwm,cfg.max_pwm, ...
        'VariableNames',{'Surface','DataSource','RMSE_deg','MAE_deg', ...
        'MaximumError_deg','NeutralPWM_us','MinimumPWM_us','MaximumPWM_us'})]; %#ok<AGROW>
    nexttile;
    plot(pwm,rawMeasured,"o","LineWidth",1.2,"DisplayName","Excel / substitute"); hold on;
    plot(pwm,modelRawConvention,"-","LineWidth",1.4,"DisplayName","Model");
    grid on; xlabel("PWM (us)"); ylabel("Deflection (deg)");
    title(strrep(name,"_"," ")); legend("Location","best");
end
exportgraphics(gcf,fullfile(outputDir,"static_calibration.png"),"Resolution",160);
close(gcf);
writetable(staticRows,fullfile(outputDir,"actuator_static_metrics.csv"));

profiles = { ...
    struct("Name","1500_to_1700","Times",[0,0.50,2.0],"PWM",[1500,1700,1700]), ...
    struct("Name","1500_to_1300","Times",[0,0.50,2.0],"PWM",[1500,1300,1300]), ...
    struct("Name","reverse_motion","Times",[0,0.50,1.20,2.00,2.70], ...
        "PWM",[1500,1800,1200,1500,1500])};
dynamicRows = table;
figure("Visible","off","Color","w","Position",[100,100,1000,760]);
tiledlayout(3,1,"TileSpacing","compact");
for item = 1:numel(profiles)
    profile = profiles{item};
    [time,deflection,rate] = simulateProfile(P,3,profile.Times,profile.PWM);
    stepTime = profile.Times(2);
    before = mean(deflection(time >= max(stepTime-0.05,0) & time < stepTime));
    afterMask = time >= stepTime;
    steady = mean(deflection(time >= profile.Times(end)-0.15));
    delay = firstCrossing(time,deflection,before,0.02*abs(steady-before),stepTime);
    rise = riseTime(time,deflection,before,steady,stepTime);
    dynamicRows = [dynamicRows;table(string(profile.Name),delay,rise, ...
        max(abs(rate(afterMask))),steady, ...
        'VariableNames',{'Profile','ObservedDelay_s','RiseTime10to90_s', ...
        'MaximumRate_deg_s','SteadyDeflection_deg'})]; %#ok<AGROW>
    nexttile; plot(time,deflection,"LineWidth",1.3); grid on;
    ylabel("Deflection (deg)"); title(strrep(profile.Name,"_"," "));
end
xlabel("Time (s)");
exportgraphics(gcf,fullfile(outputDir,"dynamic_responses.png"),"Resolution",160);
close(gcf);
writetable(dynamicRows,fullfile(outputDir,"actuator_dynamic_metrics.csv"));

deadbandHold = deadbandCheck(P,3,4);
deadbandMove = deadbandCheck(P,3,6);
saturationPass = saturationCheck(P,3);
delayEffectPass = delayCheck(P,3);
ratePass = all(dynamicRows.MaximumRate_deg_s <= ...
    P.servo.aileron_right.rate_positive_deg_s+1e-6);
summary = table( ...
    all(staticRows.MaximumError_deg < 1e-9),deadbandHold,deadbandMove, ...
    delayEffectPass,saturationPass,ratePass,P.servo.aileron_right.delay_s, ...
    P.servo.aileron_right.time_constant_s, ...
    'VariableNames',{'StaticCalibrationPass','DeadbandHoldPass', ...
    'DeadbandReleasePass','DelayEffectPass','SaturationPass','RateLimitPass', ...
    'ConfiguredDelay_s','ConfiguredTimeConstant_s'});
writetable(summary,fullfile(outputDir,"actuator_validation_summary.csv"));
result = struct("static",staticRows,"dynamic",dynamicRows,"summary",summary, ...
    "output_directory",outputDir);
disp(staticRows); disp(dynamicRows); disp(summary);
end

function pass = delayCheck(P,channel)
stateDelayed = actuator_initial_state(P);
stateNoDelay = stateDelayed;
pwm = P.actuator.pwm_trim;
pwm(channel) = P.actuator.pwm_max(channel);
stateDelayed = actuator_discrete_step(P,pwm,stateDelayed);
PnoDelay = P;
PnoDelay.actuator.delay_s(:) = 0;
stateNoDelay = actuator_discrete_step(PnoDelay,pwm,stateNoDelay);
pass = abs(stateDelayed.surface(channel)-stateNoDelay.surface(channel)) > 1e-9;
end

function [time,deflection,rate] = simulateProfile(P,channel,times,pwmValues)
dt = P.actuator.sample_time_s;
time = (0:dt:times(end))';
state = actuator_initial_state(P);
deflection = zeros(size(time)); rate = zeros(size(time));
for index = 1:numel(time)
    segment = find(times <= time(index),1,"last");
    pwm = P.actuator.pwm_trim;
    pwm(channel) = pwmValues(segment);
    state = actuator_discrete_step(P,pwm,state);
    deflection(index) = rad2deg(state.surface(channel));
    rate(index) = rad2deg(state.rate(channel));
end
end

function delay = firstCrossing(time,response,initial,threshold,stepTime)
mask = time >= stepTime & abs(response-initial) >= threshold;
index = find(mask,1,"first");
if isempty(index), delay = NaN; else, delay = time(index)-stepTime; end
end

function value = riseTime(time,response,initial,final,stepTime)
span = final-initial;
if abs(span) < eps, value = NaN; return; end
progress = (response-initial)/span;
i10 = find(time >= stepTime & progress >= 0.1,1,"first");
i90 = find(time >= stepTime & progress >= 0.9,1,"first");
if isempty(i10) || isempty(i90), value = NaN; else, value = time(i90)-time(i10); end
end

function pass = deadbandCheck(P,channel,increment)
state = actuator_initial_state(P);
pwm = P.actuator.pwm_trim;
initial = state.surface(channel);
for index = 1:20
    pwm(channel) = P.actuator.pwm_trim(channel)+increment;
    state = actuator_discrete_step(P,pwm,state);
end
movement = abs(rad2deg(state.surface(channel)-initial));
if increment <= P.actuator.deadband_pwm(channel)
    pass = movement < 1e-9;
else
    pass = movement > 0.01;
end
end

function pass = saturationCheck(P,channel)
pwm = P.actuator.pwm_trim;
pwm(channel) = P.actuator.pwm_max(channel)+500;
physical = uav_servo_mapping(P,pwm,"pwm_to_command");
limits = [P.limits.throttle;P.limits.delta_LT;P.limits.delta_RT; ...
    P.limits.delta_e;P.limits.delta_r];
pass = physical(channel) <= limits(channel,2)+eps && ...
    physical(channel) >= limits(channel,1)-eps;
end
