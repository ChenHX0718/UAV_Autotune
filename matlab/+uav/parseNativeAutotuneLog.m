function summary = parseNativeAutotuneLog(runDirectory,options)
%PARSENATIVEAUTOTUNELOG Parse exact-commit ATRP without expected-flow invention.
arguments
    runDirectory (1,1) string
    options.Axis (1,1) string {mustBeMember(options.Axis,["roll","pitch","yaw"])} = "roll"
    options.OutputDirectory (1,1) string = runDirectory
end
setup_project;
axisName = lower(options.Axis);
axisValue = find(["roll","pitch","yaw"] == axisName)-1;
if ~isfolder(options.OutputDirectory), mkdir(options.OutputDirectory); end
atrpFile = fullfile(runDirectory,"internal_ATRP.csv");
if ~isfile(atrpFile)
    summary = failureSummary(axisName,"LOG_MISSING","ATRP CSV is absent.");
    writeJson(fullfile(options.OutputDirectory,"AUTOTUNE_PARSE_SUMMARY.json"),summary);
    return
end
data = readtable(atrpFile,"TextType","string");
required = ["Axis","State","Sur","PSlew","DSlew","FF0","FF", ...
    "P","I","D","Action","RMAX","TAU"];
if ~all(ismember(required,string(data.Properties.VariableNames)))
    summary = failureSummary(axisName,"LOG_MISSING","ATRP fields do not match the pinned commit.");
    writeJson(fullfile(options.OutputDirectory,"AUTOTUNE_PARSE_SUMMARY.json"),summary);
    return
end
data = data(double(data.Axis) == axisValue,:);
if isempty(data)
    summary = failureSummary(axisName,"LOG_MISSING","ATRP has no selected-axis records.");
    writeJson(fullfile(options.OutputDirectory,"AUTOTUNE_PARSE_SUMMARY.json"),summary);
    return
end
time = apTime(data);
stateMap = ["IDLE","DEMAND_POS","DEMAND_NEG"];
actionMap = ["NONE","LOW_RATE","SHORT","RAISE_PD","LOWER_PD", ...
    "IDLE_LOWER_PD","RAISE_D","RAISE_P","LOWER_D","LOWER_P"];
stateValue = double(data.State); actionValue = double(data.Action);
unknownState = ~ismember(stateValue,0:2); unknownAction = ~ismember(actionValue,0:9);
stateName = repmat("UNKNOWN",height(data),1); actionName = stateName;
stateName(~unknownState) = stateMap(stateValue(~unknownState)+1);
actionName(~unknownAction) = actionMap(actionValue(~unknownAction)+1);

trace = table(time,repmat(axisName,height(data),1),stateValue,stateName, ...
    double(data.Sur),double(data.PSlew),double(data.DSlew),double(data.FF0), ...
    double(data.FF),double(data.P),double(data.I),double(data.D), ...
    actionValue,actionName,double(data.RMAX),double(data.TAU), ...
    'VariableNames',{'Time_s','Axis','StateValue','State','Surface_deg', ...
    'P_slew','D_slew','FF_single','FF','P','I','D','ActionValue','Action', ...
    'RMAX','TAU'});
writetable(trace,fullfile(options.OutputDirectory,"AUTOTUNE_PARAMETER_TRACE.csv"));

parameterNames = ["FF","P","I","D","RMAX","TAU"];
parameterSummary = table;
parameterUpdate = false(height(trace),1);
for parameter = parameterNames
    values = trace.(parameter);
    changed = [false;abs(diff(values)) > max(1e-9,1e-7*abs(values(1:end-1)))];
    parameterUpdate = parameterUpdate | changed;
    row = table(parameter,values(1),min(values),max(values),values(end), ...
        nnz(changed),'VariableNames',{'Parameter','Initial','MinimumObserved', ...
        'MaximumObserved','Final','NumberOfUpdates'});
    parameterSummary = [parameterSummary;row]; %#ok<AGROW>
end
writetable(parameterSummary,fullfile(options.OutputDirectory, ...
    "AUTOTUNE_PARAMETER_SUMMARY.csv"));

stateChanged = [true;diff(stateValue) ~= 0];
actionChanged = [true;diff(actionValue) ~= 0];
eventMask = stateChanged | actionChanged | parameterUpdate;
event = strings(nnz(eventMask),1); sourceRow = find(eventMask);
for k = 1:numel(sourceRow)
    row = sourceRow(k); parts = strings(0,1);
    if row == 1, parts(end+1) = "ATRP_LOG_START"; end %#ok<AGROW>
    if stateChanged(row)
        if stateName(row) == "DEMAND_POS", parts(end+1) = "POSITIVE_EXCITATION_START"; end %#ok<AGROW>
        if stateName(row) == "DEMAND_NEG", parts(end+1) = "NEGATIVE_EXCITATION_START"; end %#ok<AGROW>
        if stateName(row) == "IDLE" && row > 1 && stateName(row-1) ~= "IDLE"
            parts(end+1) = "EXCITATION_END"; %#ok<AGROW>
        end
    end
    if actionChanged(row) && actionName(row) ~= "NONE"
        parts(end+1) = actionName(row); %#ok<AGROW>
    end
    if parameterUpdate(row), parts(end+1) = "PARAMETER_UPDATE"; end %#ok<AGROW>
    if isempty(parts), parts = "STATE_OBSERVATION"; end
    event(k) = join(parts,";");
end
timeline = trace(eventMask,["Time_s","Axis","State","Action","Surface_deg", ...
    "P_slew","D_slew","FF_single","FF","P","I","D","RMAX","TAU"]);
timeline = addvars(timeline,event,'Before','State','NewVariableNames','Event');

[finished,finishedTime,finishedText] = completionMessage(runDirectory,axisName);
if finished
    completionRow = timeline(end,:);
    completionRow.Time_s = finishedTime; completionRow.Event = "AUTOTUNE_COMPLETE";
    completionRow.State = "MESSAGE"; completionRow.Action = finishedText;
    timeline = [timeline;completionRow];
end
writetable(timeline,fullfile(options.OutputDirectory,"AUTOTUNE_TIMELINE.csv"));

eventEnd = stateName == "IDLE" & [false;stateName(1:end-1) ~= "IDLE"];
rejected = eventEnd & ismember(actionName,["LOW_RATE","SHORT"]);
effectiveCount = nnz(eventEnd & ~rejected);
hasDLimit = any(actionName == "LOWER_D");
hasPLimit = any(actionName == "LOWER_P");
hasFFUpdates = parameterSummary.NumberOfUpdates(parameterSummary.Parameter == "FF") >= 4;
if any(unknownState | unknownAction)
    failure = "UNKNOWN_AUTOTUNE_STATE";
elseif effectiveCount == 0
    failure = "INSUFFICIENT_EXCITATION";
elseif finished && hasDLimit && hasPLimit && hasFFUpdates
    failure = "";
elseif ~hasFFUpdates
    failure = "AUTOTUNE_NO_PROGRESS";
else
    failure = "INCOMPLETE_TIMEOUT";
end
summary = struct("axis",axisName,"status",passFail(strlength(failure)==0), ...
    "completion_class",completionClass(failure,finished), ...
    "failure_reason",failure,"atrp_rows",height(trace), ...
    "effective_excitation_count",effectiveCount, ...
    "rejected_excitation_count",nnz(rejected),"d_boundary_observed",hasDLimit, ...
    "p_boundary_observed",hasPLimit,"finished_message_observed",finished, ...
    "first_finished_time_s",finishedTime,"finished_message",finishedText, ...
    "parameter_summary",parameterSummary, ...
    "timeline_file",fullfile(options.OutputDirectory,"AUTOTUNE_TIMELINE.csv"));
writeJson(fullfile(options.OutputDirectory,"AUTOTUNE_PARSE_SUMMARY.json"),summary);
writePlots(trace,options.OutputDirectory,axisName);
end

function [found,time,text] = completionMessage(runDirectory,axisName)
found = false; time = NaN; text = "";
filePath = fullfile(runDirectory,"internal_MSG.csv");
if ~isfile(filePath), return; end
messages = readtable(filePath,"TextType","string");
variables = string(messages.Properties.VariableNames);
messageField = variables(contains(lower(variables),"message"));
if isempty(messageField), return; end
needle = upper(extractBefore(axisName,2))+extractAfter(axisName,1)+": Finished";
values = string(messages.(messageField(1)));
% V5.4.1 contract: the first exact native Finished event is authoritative.
row = find(contains(lower(values),lower(needle)),1,"first");
if isempty(row), return; end
found = true; text = values(row);
if ismember("ap_time_s",variables), time = double(messages.ap_time_s(row));
elseif ismember("TimeUS",variables), time = double(messages.TimeUS(row))/1e6;
end
end

function time = apTime(data)
if ismember("ap_time_s",string(data.Properties.VariableNames))
    time = double(data.ap_time_s);
else
    time = double(data.TimeUS)/1e6;
end
end

function writePlots(trace,outputDirectory,axisName)
try
    fig = figure("Visible","off","Color","w","Position",[100 100 1200 850]);
    tiledlayout(fig,3,1,"TileSpacing","compact");
    nexttile; plot(trace.Time_s,[trace.FF,trace.P,trace.I,trace.D],"LineWidth",1.1); ...
        grid on; ylabel("Gain"); legend("FF","P","I","D","Location","best");
    title(upper(axisName)+" Native AUTOTUNE parameter history");
    nexttile; plot(trace.Time_s,[trace.P_slew,trace.D_slew],"LineWidth",1); ...
        grid on; ylabel("Slew"); legend("P slew","D slew");
    nexttile; yyaxis left; stairs(trace.Time_s,trace.StateValue); ylabel("State"); ...
        yyaxis right; stairs(trace.Time_s,trace.ActionValue); ylabel("Action"); ...
        grid on; xlabel("ArduPilot time (s)");
    exportgraphics(fig,fullfile(outputDirectory,"AUTOTUNE_TIMELINE.png"),"Resolution",160);
    close(fig);
catch
end
end

function summary = failureSummary(axisName,reason,detail)
summary = struct("axis",axisName,"status","FAIL","failure_reason",reason, ...
    "completion_class","INCOMPLETE", ...
    "detail",detail,"atrp_rows",0,"effective_excitation_count",0, ...
    "finished_message_observed",false);
end

function value = completionClass(failure,finished)
if strlength(failure) == 0 && finished
    value = "COMPLETE_OFFICIAL_FINISHED";
elseif failure == "INCOMPLETE_TIMEOUT"
    value = "INCOMPLETE_TIMEOUT";
else
    value = "INCOMPLETE";
end
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function writeJson(filePath,value)
fid = fopen(filePath,"w"); if fid < 0, return; end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end
