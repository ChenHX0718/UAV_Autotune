function results = measureControlAuthority(axisName)
%MEASURECONTROLAUTHORITY Retired V5.4 fractional-pulse estimator.

% The old 25/50/75/100%%, 0.6 s pulse approach is not a formal control-
% authority result because it can score a transient before the physical
% endpoint/envelope limit.  Keep this entry point only to prevent silent
% reuse by older scripts.
error("UAVV541:RetiredAuthorityMethod", ...
    ["V5.4 fractional-pulse control-authority logic is invalidated. " ...
     "Run run_v541_physical_control_authority instead."]);

%#ok<UNRCH>

axisName = lower(string(axisName));
if ~ismember(axisName,["roll","pitch"])
    error("UAVV54:AuthorityAxis","Axis must be roll or pitch.");
end
root = v53.projectRoot();
modelRoot = fullfile(root,"model");
addpath(modelRoot,"-begin");
create_v52_buses();
modelName = "UAV_Autotune_Model_4Axis";
open_system(fullfile(modelRoot,modelName+".slx"));

cfg = jsondecode(fileread(fullfile(root,"config","aircraft","UAV_A.json")));
margin = 3;
airspeeds = unique([max(10,double(cfg.nominal_airspeed_mps)-margin), ...
    double(cfg.nominal_airspeed_mps),double(cfg.nominal_airspeed_mps)+margin]);
fractions = [0.25,0.50,0.75,1.00];
directions = [-1,1];
caseCount = numel(airspeeds)*numel(fractions)*numel(directions);
inputs(1,caseCount) = Simulink.SimulationInput(modelName);
metadata = repmat(struct("Airspeed",0,"Fraction",0,"Direction",0),caseCount,1);
caseIndex = 0;
for airspeed = airspeeds
    for fraction = fractions
        for direction = directions
            caseIndex = caseIndex+1;
            P = uav_config("UAV_A",airspeed);
            P.controller.backend = "test_direct_actuator";
            P.fidelity.actuator = "ENGINEERING";
            P.fidelity.sensor = "IDEAL";
            P.sensor.native_sitl = false;
            P.v54.control_authority = struct("axis",axisName, ...
                "command_fraction",fraction,"command_direction",direction, ...
                "pulse_start_s",0.50,"pulse_end_s",1.10,"test_only",true);
            inputs(caseIndex) = Simulink.SimulationInput(modelName);
            inputs(caseIndex) = inputs(caseIndex).setVariable("P",P);
            inputs(caseIndex) = inputs(caseIndex).setModelParameter( ...
                "StopTime","2.5","SolverType","Fixed-step","Solver","ode4", ...
                "FixedStep","0.005","ReturnWorkspaceOutputs","on");
            metadata(caseIndex) = struct("Airspeed",airspeed, ...
                "Fraction",fraction,"Direction",direction);
        end
    end
end

outputs = sim(inputs,"ShowProgress","off");
rows = table;
for index = 1:caseCount
    rows = [rows;analyzeCase(outputs(index),metadata(index),axisName)]; %#ok<AGROW>
end
results = rows;
close_system(modelName,0);
end

function row = analyzeCase(out,meta,axisName)
t = double(out.truth_state_log.Time);
x = double(out.truth_state_log.Data);
surface = double(out.actuator_actual_log.Data);
pwm = double(out.actuator_cmd_log.Data);
tSurface = double(out.actuator_actual_log.Time);
tPwm = double(out.actuator_cmd_log.Time);
pulseStart = 0.50; pulseEnd = 1.10;
safetyViolation = abs(rad2deg(x(:,10))) > 45 | ...
    abs(rad2deg(x(:,13))) > 15 | x(:,15) < 8 | ...
    abs(rad2deg(x(:,14))) > 20 | any(~isfinite(x),2);
violationIndex = find(t >= pulseStart & safetyViolation,1,"first");
cutoff = pulseEnd;
if ~isempty(violationIndex), cutoff = min(cutoff,t(violationIndex)); end
mask = t >= pulseStart & t <= cutoff;
safetyPass = isempty(violationIndex) || t(violationIndex) >= pulseEnd;
validDuration = max(cutoff-pulseStart,0);
if nnz(mask) < 3
    rate = NaN; peak = NaN; sustained = NaN; time90 = NaN;
else
    if axisName == "roll", rate = rad2deg(x(mask,7)); else, rate = rad2deg(x(mask,8)); end
    peak = max(abs(rate));
    tailStart = max(pulseStart,cutoff-0.15);
    tailMask = t >= tailStart & t <= cutoff;
    if axisName == "roll", tailRate = rad2deg(x(tailMask,7)); else, tailRate = rad2deg(x(tailMask,8)); end
    sustained = median(abs(tailRate));
    target = 0.9*peak;
    localTime = t(mask);
    crossing = find(abs(rate) >= target,1,"first");
    if isempty(crossing), time90 = NaN; else, time90 = localTime(crossing)-pulseStart; end
end

surfacePulseMask = tSurface >= pulseStart & tSurface < min(pulseEnd,max(tSurface));
pwmPulseMask = tPwm >= pulseStart & tPwm < min(pulseEnd,max(tPwm));
pwmNeutralMask = tPwm < pulseStart;
if axisName == "roll"
    usedDeflection = max(abs(rad2deg(0.5*(surface(surfacePulseMask,2)-surface(surfacePulseMask,3)))));
    pwmUsed = max(abs(pwm(pwmPulseMask,[2,3])- ...
        mean(pwm(pwmNeutralMask,[2,3]),1)),[],"all");
else
    usedDeflection = max(abs(rad2deg(surface(surfacePulseMask,4))));
    pwmUsed = max(abs(pwm(pwmPulseMask,4)-mean(pwm(pwmNeutralMask,4))));
end
if isempty(rate) || all(isnan(rate))
    positiveSustained = NaN; negativeSustained = NaN;
else
    positiveSustained = max(median(max(rate,0)),0);
    negativeSustained = max(median(max(-rate,0)),0);
    if any(rate > 0), positiveSustained = max(median(rate(rate >= prctile(rate,75))),0); end
    if any(rate < 0), negativeSustained = max(median(-rate(rate <= prctile(rate,25))),0); end
end
row = table(meta.Airspeed,meta.Fraction,meta.Direction,pwmUsed, ...
    usedDeflection,peak,sustained,positiveSustained,negativeSustained, ...
    time90,validDuration,safetyPass, ...
    'VariableNames',{'Airspeed_mps','CommandFraction','CommandDirection', ...
    'PWMExcursion_us','SurfaceDeflection_deg','PeakRate_deg_s', ...
    'SustainedRate_deg_s','PositiveSustainedRate_deg_s', ...
    'NegativeSustainedRate_deg_s','TimeTo90Rate_s','ValidPulseDuration_s', ...
    'SafetyPass'});
end
