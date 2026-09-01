function result = runPhysicalControlAuthority(options)
%RUNPHYSICALCONTROLAUTHORITY Three-axis plant-only capability test.
arguments
    options.Axes string = ["roll","pitch","yaw"]
end

root = uav.projectRoot();
modelRoot = fullfile(root,"model");
addpath(modelRoot,"-begin"); addpath(fullfile(root,"matlab"),"-begin");
create_interface_buses();
axesToRun = lower(string(options.Axes(:)'));
if any(~ismember(axesToRun,["roll","pitch","yaw"]))
    error("UAVV541:AuthorityAxis","Axes must contain roll, pitch, or yaw.");
end
modelName = "UAV_Autotune_Model_4Axis";
modelFile = fullfile(modelRoot,modelName+".slx");
if bdIsLoaded(modelName)
    loadedFile = string(get_param(modelName,"FileName"));
    if ~strcmpi(loadedFile,modelFile), close_system(modelName,0); end
end
open_system(modelFile);

baseP = uav_config("UAV_A",13);
airspeeds = double(baseP.control_authority.test_airspeeds_mps(:)');
directions = [1,-1];
caseCount = numel(axesToRun)*numel(airspeeds)*numel(directions);
inputs(1,caseCount) = Simulink.SimulationInput(modelName);
metadata = repmat(struct("axis","","airspeed",0,"direction",0, ...
    "stop_time",0,"initial_pitch_deg",0,"flight_path_deg",0),caseCount,1);
caseIndex = 0;
for axisName = axesToRun
    for airspeed = airspeeds
        for direction = directions
            caseIndex = caseIndex+1;
            P = configureCase(axisName,airspeed,direction);
            inputs(caseIndex) = Simulink.SimulationInput(modelName);
            inputs(caseIndex) = inputs(caseIndex).setVariable("P",P);
            inputs(caseIndex) = inputs(caseIndex).setModelParameter( ...
                "StopTime",string(P.control_authority.case.stop_time_s), ...
                "SolverType","Fixed-step","Solver","ode4", ...
                "FixedStep","0.005","ReturnWorkspaceOutputs","on");
            metadata(caseIndex) = struct("axis",axisName, ...
                "airspeed",airspeed,"direction",direction, ...
                "stop_time",P.control_authority.case.stop_time_s, ...
                "initial_pitch_deg",rad2deg(P.init.euler(2)), ...
                "flight_path_deg",rad2deg( ...
                    P.control_authority.case.initial_flight_path_rad));
        end
    end
end

outputs = sim(inputs,"ShowProgress","off");
rollSummary = table; pitchSummary = table; yawSummary = table;
for k = 1:caseCount
    [summary,trace] = analyzeCase(outputs(k),metadata(k),baseP);
    outputDir = fullfile(root,"results","v5_4_1", ...
        "physical_control_authority",metadata(k).axis);
    if ~isfolder(outputDir), mkdir(outputDir); end
    directionName = directionLabel(metadata(k).axis,metadata(k).direction);
    fileName = sprintf("%s_%02gmps_%s.csv",metadata(k).axis, ...
        metadata(k).airspeed,lower(directionName));
    writetable(trace,fullfile(outputDir,fileName));
    switch metadata(k).axis
        case "roll", rollSummary = [rollSummary;summary]; %#ok<AGROW>
        case "pitch", pitchSummary = [pitchSummary;summary]; %#ok<AGROW>
        case "yaw", yawSummary = [yawSummary;summary]; %#ok<AGROW>
    end
end

result = struct("test_mode","PLANT_ONLY_CONTROL_AUTHORITY_TEST", ...
    "roll",rollSummary,"pitch",pitchSummary,"yaw",yawSummary);
if ~isempty(rollSummary)
    dirPath = fullfile(root,"results","v5_4_1", ...
        "physical_control_authority","roll");
    writetable(rollSummary,fullfile(dirPath,"roll_capability_summary.csv"));
    plotRoll(dirPath,rollSummary);
end
if ~isempty(pitchSummary)
    dirPath = fullfile(root,"results","v5_4_1", ...
        "physical_control_authority","pitch");
    writetable(pitchSummary,fullfile(dirPath,"pitch_capability_summary.csv"));
    plotPitch(dirPath,pitchSummary);
end
if ~isempty(yawSummary)
    dirPath = fullfile(root,"results","v5_4_1", ...
        "physical_control_authority","yaw");
    writetable(yawSummary,fullfile(dirPath,"yaw_capability_summary.csv"));
    plotYaw(dirPath,yawSummary);
end
close_system(modelName,0);

    function P = configureCase(axisName,airspeed,direction)
        P = uav_config("UAV_A",airspeed);
        P.controller.backend = "test_direct_actuator";
        P.fidelity.actuator = "ENGINEERING";
        P.fidelity.sensor = "IDEAL";
        P.sensor.enable_noise = false;
        P.env.gust_enable = false; P.env.wind_ned = zeros(3,1);
        P.init.body_rates = zeros(3,1);
        target = surface_targets(P,axisName,direction);
        % Initial actuator state equals the requested maximum actual surface.
        P.trim.actuator = target;
        stopTime = double(P.control_authority.case_stop_time_s.(axisName));
        P.control_authority.profile = struct("axis",axisName, ...
            "command_fraction",1,"command_direction",direction, ...
            "pulse_start_s",0,"pulse_end_s",stopTime+1,"test_only",true);
        P.control_authority.case = struct("stop_time_s",stopTime, ...
            "test_mode","PLANT_ONLY_CONTROL_AUTHORITY_TEST");
        if axisName == "roll"
            if direction > 0
                P.init.euler(1) = deg2rad(P.control_authority.roll_min_deg);
            else
                P.init.euler(1) = deg2rad(P.control_authority.roll_max_deg);
            end
        elseif axisName == "pitch"
            if direction > 0
                theta = deg2rad(P.control_authority.pitch_min_deg);
            else
                theta = deg2rad(P.control_authority.pitch_max_deg);
            end
            % Keep aerodynamic alpha at trim and obtain gamma=theta-alpha.
            P.init.euler(2) = theta;
        else
            P.init.euler(1) = 0;
        end
        P.control_authority.case.initial_flight_path_rad = ...
            P.init.euler(2)-P.trim.alpha;
    end
end

function [summary,trace] = analyzeCase(out,meta,P)
t = double(out.truth_state_log.Time);
x = double(out.truth_state_log.Data);
surface = alignLog(out.actuator_actual_log,t);
pwm = alignLog(out.actuator_cmd_log,t);
roll = rad2deg(x(:,10)); pitch = rad2deg(x(:,11)); yaw = rad2deg(x(:,12));
p = rad2deg(x(:,7)); q = rad2deg(x(:,8)); r = rad2deg(x(:,9));
alpha = rad2deg(x(:,13)); beta = rad2deg(x(:,14)); airspeed = x(:,15);
flightPath = pitch-alpha;
finite = all(isfinite([x,surface,pwm]),2);
baseSafe = finite & alpha >= P.control_authority.alpha_min_deg & ...
    alpha <= P.control_authority.alpha_max_deg & ...
    airspeed >= P.control_authority.airspeed_min_mps;

switch meta.axis
    case "roll"
        if meta.direction > 0
            crossing = find(roll >= P.control_authority.roll_max_deg,1,"first");
        else
            crossing = find(roll <= P.control_authority.roll_min_deg,1,"first");
        end
        cutoff = cutoffIndex(crossing,numel(t));
        operational = baseSafe & roll >= P.control_authority.roll_min_deg & ...
            roll <= P.control_authority.roll_max_deg & (1:numel(t))' <= cutoff;
        completed = ~isempty(crossing);
        T90 = NaN; if completed, T90 = t(crossing)-t(1); end
        averageRate = NaN; if completed && T90 > 0, averageRate = 90/T90; end
        limit = "INCOMPLETE_TIMEOUT"; if completed, limit = "ANGLE_COMPLETE"; end
        summary = table(meta.airspeed,directionLabel("roll",meta.direction), ...
            T90,averageRate,maxAbs(p(operational)),maxAbs(alpha(operational)), ...
            maxAbs(beta(operational)),string(limit), ...
            'VariableNames',{'Airspeed_mps','Direction','T90_s', ...
            'p_avg_90_deg_s','p_op_max_deg_s','AlphaMax_deg','BetaMax_deg','Limit'});
    case "pitch"
        if meta.direction > 0
            angleCross = find(pitch >= P.control_authority.pitch_max_deg,1,"first");
            directionName = "PITCH_UP";
        else
            angleCross = find(pitch <= P.control_authority.pitch_min_deg,1,"first");
            directionName = "PITCH_DOWN";
        end
        aoaCross = find(alpha > P.control_authority.alpha_max_deg | ...
            alpha < P.control_authority.alpha_min_deg,1,"first");
        airspeedCross = find(airspeed < P.control_authority.airspeed_min_mps,1,"first");
        numericCross = find(~finite,1,"first");
        [cutoff,limit] = firstLimit(numel(t),angleCross,"ANGLE_COMPLETE", ...
            aoaCross,"AOA_LIMITED",airspeedCross,"AIRSPEED_LIMITED", ...
            numericCross,"NUMERICAL_LIMIT");
        safe = baseSafe & pitch >= P.control_authority.pitch_min_deg & ...
            pitch <= P.control_authority.pitch_max_deg & (1:numel(t))' <= cutoff;
        completed = limit == "ANGLE_COMPLETE";
        duration = NaN; if completed, duration = t(cutoff)-t(1); end
        angleRange = P.control_authority.pitch_max_deg- ...
            P.control_authority.pitch_min_deg;
        averageRate = NaN; if completed && duration > 0, averageRate = angleRange/duration; end
        summary = table(meta.airspeed,string(directionName),angleRange,duration, ...
            averageRate,maxAbs(q(safe)),maxOrNaN(alpha(safe)), ...
            minOrNaN(alpha(safe)),minOrNaN(airspeed(safe)),string(limit), ...
            meta.initial_pitch_deg,meta.flight_path_deg, ...
            'VariableNames',{'Airspeed_mps','Direction','AngleRange_deg', ...
            'Time_s','q_avg_deg_s','q_op_max_deg_s','AlphaMax_deg', ...
            'AlphaMin_deg','AirspeedMin_mps','Limit','InitialPitch_deg', ...
            'InitialFlightPath_deg'});
    case "yaw"
        betaCross = find(abs(beta) >= P.control_authority.beta_max_deg,1,"first");
        rollCross = find(abs(roll) >= P.control_authority.yaw_roll_limit_deg,1,"first");
        aoaCross = find(alpha > P.control_authority.alpha_max_deg | ...
            alpha < P.control_authority.alpha_min_deg,1,"first");
        airspeedCross = find(airspeed < P.control_authority.airspeed_min_mps,1,"first");
        numericCross = find(~finite,1,"first");
        [cutoff,limit] = firstLimit(numel(t),betaCross,"BETA_LIMITED", ...
            rollCross,"ROLL_COUPLING_LIMITED",aoaCross,"AOA_LIMITED", ...
            airspeedCross,"AIRSPEED_LIMITED",numericCross,"NUMERICAL_LIMIT");
        safe = baseSafe & abs(beta) <= P.control_authority.beta_max_deg & ...
            abs(roll) <= P.control_authority.yaw_roll_limit_deg & ...
            (1:numel(t))' <= cutoff;
        rPeak = maxAbs(r(safe)); pPeak = maxAbs(p(safe));
        coupling = pPeak/max(rPeak,eps);
        timeToBeta = NaN; if ~isempty(betaCross), timeToBeta = t(betaCross)-t(1); end
        summary = table(meta.airspeed,directionLabel("yaw",meta.direction), ...
            maxAbs(r(safe)),maxAbs(beta(safe)),timeToBeta,pPeak, ...
            maxAbs(roll(safe)),rPeak,coupling,string(limit), ...
            'VariableNames',{'Airspeed_mps','Direction','r_op_max_deg_s', ...
            'BetaPeak_deg','TimeToBetaLimit_s','p_peak_deg_s','phi_peak_deg', ...
            'r_peak_deg_s','K_yaw_roll','Limit'});
end

keep = 1:cutoff;
trace = table(t(keep),roll(keep),p(keep),pitch(keep),flightPath(keep), ...
    q(keep),yaw(keep),r(keep),airspeed(keep),alpha(keep),beta(keep), ...
    rad2deg(surface(keep,2)),rad2deg(surface(keep,3)), ...
    rad2deg(surface(keep,4)),rad2deg(surface(keep,5)), ...
    pwm(keep,2),pwm(keep,3),pwm(keep,4),pwm(keep,5), ...
    'VariableNames',{'time_s','roll_deg','p_deg_s','pitch_deg', ...
    'flight_path_deg','q_deg_s','yaw_deg','r_deg_s','airspeed_mps', ...
    'alpha_deg','beta_deg', ...
    'aileron_left_deg','aileron_right_deg','elevator_deg','rudder_deg', ...
    'pwm_left_us','pwm_right_us','pwm_elevator_us','pwm_rudder_us'});
end

function data = alignLog(logValue,t)
data = double(logValue.Data);
logTime = double(logValue.Time);
if numel(logTime) ~= numel(t) || any(abs(logTime-t) > 1e-9)
    data = interp1(logTime,data,t,"previous","extrap");
end
end

function [index,label] = firstLimit(defaultIndex,varargin)
index = defaultIndex; label = "INCOMPLETE_TIMEOUT";
for k = 1:2:numel(varargin)
    candidate = varargin{k};
    if ~isempty(candidate) && candidate < index
        index = candidate; label = string(varargin{k+1});
    elseif ~isempty(candidate) && candidate == index && label == "INCOMPLETE_TIMEOUT"
        label = string(varargin{k+1});
    end
end
end

function value = cutoffIndex(candidate,defaultValue)
if isempty(candidate), value = defaultValue; else, value = candidate; end
end

function value = maxAbs(x)
x = x(isfinite(x)); if isempty(x), value = NaN; else, value = max(abs(x)); end
end
function value = maxOrNaN(x)
x = x(isfinite(x)); if isempty(x), value = NaN; else, value = max(x); end
end
function value = minOrNaN(x)
x = x(isfinite(x)); if isempty(x), value = NaN; else, value = min(x); end
end

function value = directionLabel(axisName,direction)
if axisName == "roll"
    if direction > 0, value = "RIGHT"; else, value = "LEFT"; end
elseif axisName == "yaw"
    if direction > 0, value = "YAW_RIGHT"; else, value = "YAW_LEFT"; end
else
    if direction > 0, value = "POSITIVE"; else, value = "NEGATIVE"; end
end
end

function plotRoll(folder,summary)
plotMetric(summary,"T90_s","T90 (s)",fullfile(folder,"T90_vs_Airspeed.png"));
plotMetric(summary,"p_avg_90_deg_s","p avg 90 (deg/s)", ...
    fullfile(folder,"p_avg_90_vs_Airspeed.png"));
plotMetric(summary,"p_op_max_deg_s","p op max (deg/s)", ...
    fullfile(folder,"p_op_max_vs_Airspeed.png"));
plotTraces(folder,"roll_*.csv","roll_deg","Roll angle (deg)","Roll_Angle_vs_Time.png");
plotTraces(folder,"roll_*.csv","p_deg_s","Roll rate (deg/s)","Roll_Rate_vs_Time.png");
end

function plotPitch(folder,summary)
up = summary(summary.Direction == "PITCH_UP",:);
down = summary(summary.Direction == "PITCH_DOWN",:);
plotSingle(up,"Time_s","Pitch-up time (s)",fullfile(folder,"Pitch_Up_Time_vs_Airspeed.png"));
plotSingle(down,"Time_s","Pitch-down time (s)",fullfile(folder,"Pitch_Down_Time_vs_Airspeed.png"));
plotMetric(summary,"q_avg_deg_s","q avg (deg/s)",fullfile(folder,"q_avg_vs_Airspeed.png"));
plotMetric(summary,"q_op_max_deg_s","q op max (deg/s)",fullfile(folder,"q_op_max_vs_Airspeed.png"));
plotTraces(folder,"pitch_*.csv","pitch_deg","Pitch angle (deg)","Pitch_Angle_vs_Time.png");
plotTraces(folder,"pitch_*.csv","q_deg_s","Pitch rate (deg/s)","Pitch_Rate_vs_Time.png");
plotTraces(folder,"pitch_*.csv","alpha_deg","Angle of attack (deg)","AoA_vs_Time.png");
end

function plotYaw(folder,summary)
plotMetric(summary,"r_op_max_deg_s","r op max (deg/s)",fullfile(folder,"r_op_max_vs_Airspeed.png"));
plotMetric(summary,"K_yaw_roll","|p peak| / |r peak|",fullfile(folder,"Roll_Yaw_Coupling_vs_Airspeed.png"));
plotTraces(folder,"yaw_*.csv","beta_deg","Sideslip beta (deg)","Beta_vs_Time.png");
plotTraces(folder,"yaw_*.csv","r_deg_s","Yaw rate (deg/s)","Yaw_Rate_vs_Time.png");
plotTraces(folder,"yaw_*.csv","p_deg_s","Rudder-induced roll rate (deg/s)", ...
    "Roll_Rate_induced_by_Rudder_vs_Time.png");
end

function plotMetric(summary,fieldName,yLabel,filePath)
fig = figure("Visible","off","Color","w"); hold on;
for direction = unique(summary.Direction,'stable')'
    data = summary(summary.Direction == direction,:);
    plot(data.Airspeed_mps,data.(fieldName),"-o","LineWidth",1.3, ...
        "DisplayName",strrep(direction,"_"," "));
end
grid on; xlabel("Airspeed (m/s)"); ylabel(yLabel); legend("Location","best");
exportgraphics(fig,filePath,"Resolution",160); close(fig);
end

function plotSingle(summary,fieldName,yLabel,filePath)
fig = figure("Visible","off","Color","w");
plot(summary.Airspeed_mps,summary.(fieldName),"-o","LineWidth",1.3);
grid on; xlabel("Airspeed (m/s)"); ylabel(yLabel);
exportgraphics(fig,filePath,"Resolution",160); close(fig);
end

function plotTraces(folder,pattern,fieldName,yLabel,fileName)
files = dir(fullfile(folder,pattern));
files = files(~contains(string({files.name}),"summary"));
fig = figure("Visible","off","Color","w"); hold on;
for k = 1:numel(files)
    data = readtable(fullfile(files(k).folder,files(k).name));
    plot(data.time_s,data.(fieldName),"LineWidth",1.0, ...
        "DisplayName",erase(string(files(k).name),".csv"));
end
grid on; xlabel("Time (s)"); ylabel(yLabel); legend("Location","best");
exportgraphics(fig,fullfile(folder,fileName),"Resolution",160); close(fig);
end
