function result = runAutotuneRepeatability(options)
%RUNAUTOTUNEREPEATABILITY Three independent same-configuration runs.
arguments
    options.Distro (1,1) string = "Ubuntu-24.04"
    options.Level (1,1) double {mustBeInteger,mustBeInRange(options.Level,1,10)} = 2
    options.Count (1,1) double {mustBeInteger,mustBePositive} = 3
    % These are safety timeouts, not completion surrogates.  The first
    % exact firmware "<Axis>: Finished" message still ends excitation.
    % Roll needs more than 24 cycles on this plant because its P boundary
    % can be reached near cycle 24 and ArduPilot then requires three
    % additional successful cycles before declaring Finished.
    options.RollCycles (1,1) double {mustBeInteger,mustBePositive} = 30
    options.PitchCycles (1,1) double {mustBeInteger,mustBePositive} = 20
    options.ActuatorFidelity (1,1) string = "ENGINEERING"
    options.SensorFidelity (1,1) string = "ENGINEERING"
    options.RandomSeed (1,1) double = 42
    options.MaxCV (1,1) double {mustBeNonnegative} = 0.15
end

setup_project;
root = uav.projectRoot();
baseline = fullfile(root,"config","autotune","baseline.param");
campaignId = string(datetime("now","Format","yyyyMMdd_HHmmss_SSS"))+ ...
    "_repeatability_level"+options.Level;
outputRoot = fullfile(root,"results","v5_4_1", ...
    "autotune_repeatability",campaignId);
if isfolder(outputRoot)
    error("UAVV541:RepeatabilityExists","Refusing to overwrite %s",outputRoot);
end
mkdir(outputRoot);

axes = ["roll","pitch"];
allRuns = table;
axisResults = struct;
completionRows = table;
for axisName = axes
    axisDir = fullfile(outputRoot,axisName);
    mkdir(axisDir);
    names = trackedParameters(axisName);
    values = nan(options.Count,numel(names));
    runRows = table;
    for trial = 1:options.Count
        assertCampaignActive(outputRoot);
        trialDir = fullfile(axisDir,"trial_"+trial);
        mkdir(trialDir);
        writeBefore(baseline,fullfile(trialDir,"params_before.param"), ...
            options.Level,axisName,trial);
        outputFile = fullfile(trialDir,"params_after.param");
        cycles = options.RollCycles;
        if axisName == "pitch", cycles = options.PitchCycles; end
        single = struct("status","FAIL","failure_reason","NOT_STARTED");
        try
            single = uav.runNativeAutotuneAxis(axisName, ...
                Level=options.Level,Cycles=cycles, ...
                BaseParameterFile=baseline,OutputParameterFile=outputFile, ...
                Distro=options.Distro, ...
                Category=fullfile("v5_4_1","campaigns",campaignId, ...
                    axisName,"trial_"+trial), ...
                Tag="repeat_"+trial, ...
                ActuatorFidelity=options.ActuatorFidelity, ...
                SensorFidelity=options.SensorFidelity, ...
                RandomSeed=options.RandomSeed);
        catch ME
            single.status = "FAIL";
            single.failure_reason = classifyException(ME);
            writeText(fullfile(trialDir,"exception.txt"), ...
                string(getReport(ME,"extended","hyperlinks","off")));
        end
        [row,completion] = runRow(single,axisName,trial,options,outputFile);
        runRows = [runRows;row]; %#ok<AGROW>
        allRuns = [allRuns;row]; %#ok<AGROW>
        completionRows = [completionRows;completion]; %#ok<AGROW>
        if row.Status == "PASS" && isfile(outputFile)
            parameters = uav.readParamFile(outputFile);
            values(trial,:) = parameterValues(parameters,names);
        end
        writeJson(fullfile(trialDir,"trial_result.json"),single);
        writetable(runRows,fullfile(axisDir,"repeatability_runs.csv"));
    end
    valueTable = array2table(values, ...
        'VariableNames',matlab.lang.makeValidName(cellstr(names)));
    valueTable = addvars(valueTable,(1:options.Count)',runRows.Status, ...
        'Before',1,'NewVariableNames',{'Trial','Status'});
    writetable(valueTable,fullfile(axisDir,"parameter_values.csv"));
    statistics = calculateStatistics(names,values,runRows.Status, ...
        options.Count,options.MaxCV);
    writetable(statistics,fullfile(axisDir,"repeatability_statistics.csv"));
    complete = nnz(runRows.Status == "PASS") == options.Count;
    repeatabilityPass = complete && all(statistics.Pass);
    axisResults.(axisName) = struct("status",passFail(repeatabilityPass), ...
        "complete_runs",nnz(runRows.Status == "PASS"), ...
        "requested_runs",options.Count,"runs",runRows, ...
        "statistics",statistics);
end

completionDir = fullfile(root,"results","v5_4_1","autotune_completion",campaignId);
mkdir(completionDir);
writetable(completionRows,fullfile(completionDir,"official_finished_log.csv"));
writetable(allRuns,fullfile(outputRoot,"repeatability_runs_all_axes.csv"));
overallPass = axisResults.roll.status == "PASS" && ...
    axisResults.pitch.status == "PASS";
result = struct("status",passFail(overallPass),"campaign_id",campaignId, ...
    "campaign_root",outputRoot,"level",options.Level, ...
    "count",options.Count,"max_cv",options.MaxCV, ...
    "actuator_fidelity",options.ActuatorFidelity, ...
    "sensor_fidelity",options.SensorFidelity, ...
    "random_seed",options.RandomSeed,"roll",axisResults.roll, ...
    "pitch",axisResults.pitch);
writeJson(fullfile(outputRoot,"repeatability_summary.json"),result);
end

function names = trackedParameters(axisName)
if axisName == "roll"
    names = ["RLL_RATE_FF","RLL_RATE_P","RLL_RATE_I","RLL_RATE_D", ...
        "RLL2SRV_RMAX","RLL2SRV_TCONST"];
else
    names = ["PTCH_RATE_FF","PTCH_RATE_P","PTCH_RATE_I","PTCH_RATE_D", ...
        "PTCH2SRV_RMAX_UP","PTCH2SRV_RMAX_DN","PTCH2SRV_TCONST"];
end
end

function values = parameterValues(parameters,names)
values = nan(1,numel(names));
for k = 1:numel(names)
    row = find(parameters.Name == names(k),1,"last");
    if ~isempty(row), values(k) = parameters.Value(row); end
end
end

function statistics = calculateStatistics(names,values,status,count,maxCV)
meanValue = mean(values,1,"omitnan")';
stdValue = std(values,0,1,"omitnan")';
minimum = min(values,[],1,"omitnan")';
maximum = max(values,[],1,"omitnan")';
n = sum(isfinite(values),1)';
cv = stdValue./abs(meanValue);
zeroStable = abs(meanValue) <= eps & stdValue <= eps;
cv(zeroStable) = 0;
cv(abs(meanValue) <= eps & ~zeroStable) = Inf;
pass = n == count & isfinite(cv) & cv <= maxCV & ...
    nnz(status == "PASS") == count;
statistics = table(names',n,meanValue,stdValue,cv,minimum,maximum,pass, ...
    'VariableNames',{'Parameter','N','Mean','Std','CV','Minimum','Maximum','Pass'});
end

function [row,completion] = runRow(single,axisName,trial,options,outputFile)
runDir = ""; completionClass = "INCOMPLETE"; finishedTime = NaN;
finishedText = "";
if isfield(single,"run")
    runDir = string(single.run.run_directory);
    completionClass = string(single.run.autotune_completion_class);
end
if isfield(single,"parse")
    if isfield(single.parse,"first_finished_time_s")
        finishedTime = double(single.parse.first_finished_time_s);
    end
    if isfield(single.parse,"finished_message")
        finishedText = string(single.parse.finished_message);
    end
end
parameterFile = "";
if string(single.status) == "PASS" && isfile(outputFile)
    parameterFile = string(outputFile);
end
row = table(trial,axisName,options.Level,string(single.status), ...
    string(single.failure_reason),completionClass,finishedTime,runDir, ...
    parameterFile,options.RandomSeed,options.ActuatorFidelity, ...
    options.SensorFidelity, ...
    'VariableNames',{'Trial','Axis','Level','Status','FailureReason', ...
    'CompletionClass','FirstFinishedTime_s','RunDirectory','ParameterFile', ...
    'RandomSeed','ActuatorFidelity','SensorFidelity'});
completion = table(axisName,trial,string(single.status),completionClass, ...
    finishedTime,finishedText,runDir, ...
    'VariableNames',{'Axis','Trial','Status','CompletionClass', ...
    'FirstFinishedTime_s','FinishedText','RunDirectory'});
end

function writeBefore(baseline,outputFile,level,axisName,trial)
parameters = uav.readParamFile(baseline);
parameters = uav.mergeParameters(parameters,table("AUTOTUNE_LEVEL",level, ...
    'VariableNames',{'Name','Value'}));
uav.writeParamFile(outputFile,parameters,Header= ...
    "V5.4.1 repeatability baseline; axis="+axisName+"; trial="+trial);
end

function value = classifyException(ME)
id = string(ME.identifier); message = string(ME.message);
if contains(id,"Mode") || contains(message,"mode","IgnoreCase",true)
    value = "MODE_CHANGE_FAIL";
elseif contains(id,"Readback"), value = "PARAMETER_READBACK_FAIL";
elseif contains(id,"SITL") || contains(message,"SITL"), value = "SITL_CRASH";
elseif contains(id,"Excitation"), value = "INSUFFICIENT_EXCITATION";
else, value = "UNKNOWN_AUTOTUNE_STATE";
end
end

function writeJson(path,value)
folder = fileparts(path); if ~isfolder(folder), mkdir(folder); end
fid = fopen(path,"w"); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end

function writeText(path,value)
fid = fopen(path,"w"); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",value);
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function assertCampaignActive(outputRoot)
marker = fullfile(outputRoot,"INVALIDATED.json");
if isfile(marker)
    error("UAVV541:CampaignInvalidated", ...
        "Repeatability campaign was invalidated and will not launch another trial: %s", ...
        outputRoot);
end
end
