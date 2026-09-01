function design = generateExcitation(axisName,options)
%GENERATEEXCITATION Build source-derived RC excitation.
arguments
    axisName (1,1) string {mustBeMember(axisName,["roll","pitch"])}
    options.AutotuneLevel (1,1) double {mustBeInteger,mustBeInRange(options.AutotuneLevel,0,10)} = 2
    % Timeout capacity only.  The mode session neutralizes immediately on
    % the first exact ArduPilot Finished event.
    options.Cycles (1,1) double {mustBeInteger,mustBePositive} = 30
    options.ParameterFile (1,1) string = fullfile(uav.projectRoot(), ...
        "config","autotune","baseline.param")
    options.OutputFile (1,1) string = ""
end
setup_project;
root = uav.projectRoot();
aircraft = jsondecode(fileread(fullfile(root,"config","aircraft","UAV_A.json")));
parameters = uav.readParamFile(options.ParameterFile);
axisName = lower(axisName);

tauTable = [1.00,0.90,0.80,0.70,0.60,0.50,0.30,0.20,0.15,0.10];
rmaxTable = [20,30,40,50,60,75,90,120,160,210];
if axisName == "roll"
    currentTau = valueOr(parameters,"RLL2SRV_TCONST",0.5);
    currentRmax = valueOr(parameters,"RLL2SRV_RMAX",0);
    attitudeLimit = double(aircraft.roll_limit_deg);
    directionLimit = [attitudeLimit,attitudeLimit];
else
    currentTau = valueOr(parameters,"PTCH2SRV_TCONST",0.5);
    currentRmax = valueOr(parameters,"PTCH2SRV_RMAX_UP",0);
    attitudeLimit = min(abs([double(aircraft.pitch_limit_max_deg), ...
        double(aircraft.pitch_limit_min_deg)]));
    directionLimit = [double(aircraft.pitch_limit_max_deg), ...
        abs(double(aircraft.pitch_limit_min_deg))];
end
if options.AutotuneLevel == 0
    targetTau = min(max(currentTau,0.1),2.0);
    targetRmax = min(max(currentRmax,20),720);
else
    targetTau = tauTable(options.AutotuneLevel);
    targetRmax = rmaxTable(options.AutotuneLevel);
    if axisName == "pitch", targetTau = 1.5*targetTau; end
end

% AP_AutoTune.cpp requires both 30% angle error and 40% of the smaller
% attitude/tau or RMAX rate. Add a bounded 15% margin, then convert the
% physical angle requirement through each direction's FBWA stick limit.
rateThreshold = 0.4*min(attitudeLimit/max(targetTau,eps),targetRmax);
requiredAngle = 1.15*max(0.3*attitudeLimit,rateThreshold*targetTau);
positiveAmplitude = requiredAngle/directionLimit(1);
negativeAmplitude = requiredAngle/directionLimit(2);
positiveAmplitude = min(max(positiveAmplitude,0.05),0.55);
negativeAmplitude = min(max(negativeAmplitude,0.05),0.55);

minimumSample = 0.100;
targetFilterTime = 1/(2*pi*4);
responseFilterTime = 1/(2*pi*0.75);
holdTime = max([0.8,2*targetTau,6*minimumSample,4*targetFilterTime]);
neutralTime = max([0.8,1.2*targetTau,4*responseFilterTime]);
% The pinned Plane build finishes defaults near 3 s.  The state-driven
% mode gate independently requires firmware/truth attitude alignment before
% FBWA/AUTOTUNE entry; excite at 10 s only after that gate is ready.
initialNeutral = max(10,4*targetTau);

times = 0; values = 0; t = initialNeutral;
for cycle = 1:options.Cycles
    [times,values] = append(times,values,t,positiveAmplitude);
    t = t+holdTime; [times,values] = append(times,values,t,0);
    t = t+neutralTime; [times,values] = append(times,values,t,-negativeAmplitude);
    t = t+holdTime; [times,values] = append(times,values,t,0);
    t = t+neutralTime;
end
[times,values] = append(times,values,t,0);

scenarioName = "native_"+axisName+"_autotune";
if strlength(options.OutputFile) == 0
    options.OutputFile = fullfile(root,"config","scenarios",scenarioName+".json");
end
scenario = struct;
scenario.name = scenarioName;
scenario.purpose = "ardupilot_native_autotune_source_derived_virtual_pilot";
scenario.flight_mode = "AUTOTUNE";
scenario.input_interface = "official_sitl_json_fdm_rc";
scenario.command_semantics = "rc_normalized";
scenario.axis = axisName;
scenario.stop_time_s = ceil(t);
scenario.scoring_start_time_s = 8;
scenario.scoring_end_time_s = floor(t)-2;
scenario.time_s = times;
scenario.("rc_"+axisName+"_normalized") = values;
scenario.allowed_rc_error_us = 2;
scenario.allowed_mapping_error_deg = 0.5;
scenario.excitation_design = struct( ...
    "source_commit","1511f27194f1dcc3728270883047bdf022b3fd53", ...
    "autotune_level",options.AutotuneLevel,"cycles",options.Cycles, ...
    "attitude_limit_deg",attitudeLimit,"target_tau_s",targetTau, ...
    "target_rmax_deg_s",targetRmax,"rate_threshold_deg_s",rateThreshold, ...
    "required_angle_error_deg",requiredAngle, ...
    "positive_rc_normalized",positiveAmplitude, ...
    "negative_rc_normalized",negativeAmplitude, ...
    "hold_time_s",holdTime,"neutral_time_s",neutralTime, ...
    "minimum_source_sample_s",minimumSample);
writeJson(options.OutputFile,scenario);
design = scenario.excitation_design;
design.scenario_file = options.OutputFile;
design.scenario_name = scenarioName;
end

function value = valueOr(parameters,name,default)
row = find(parameters.Name == name,1,"last");
if isempty(row), value = default; else, value = parameters.Value(row); end
end

function [times,values] = append(times,values,time,value)
if time <= times(end)
    if time == times(end), values(end) = value; return; end
    error("UAVV541:ExcitationTime","Excitation times must increase.");
end
times(end+1,1) = time; values(end+1,1) = value;
end

function writeJson(filePath,value)
folder = fileparts(filePath); if ~isfolder(folder), mkdir(folder); end
fid = fopen(filePath,"w"); if fid < 0, error("UAVV541:ExcitationWrite","Cannot write %s",filePath); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end
