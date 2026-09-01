function summary = writeSpeedupSummary(runDirectories,speedups,outputDirectory)
%WRITESPEEDUPSUMMARY Compare response invariance at 1x, 2x and 5x.
arguments
    runDirectories (:,1) string
    speedups (:,1) double
    outputDirectory (1,1) string = fullfile(v52.projectRoot(),"results")
end
if numel(runDirectories) ~= numel(speedups) || ~any(speedups == 1)
    error("UAVV52:SpeedupInputs","Run directories must match speeds and include 1x.");
end
n = numel(speedups); verdict = strings(n,1); peak = nan(n,1);
overshoot = nan(n,1); settling = nan(n,1); steadyError = nan(n,1);
rmse = nan(n,1); lost = nan(n,1); invalid = nan(n,1);
for k = 1:n
    result = jsondecode(fileread(fullfile(runDirectories(k),"result.json")));
    verdict(k) = string(result.overall); d = result.dynamic_metrics;
    peak(k)=d.peak_deg; overshoot(k)=d.overshoot_percent;
    settling(k)=d.settling_time_s; steadyError(k)=d.steady_state_error_deg;
    rmse(k)=d.rmse_deg; lost(k)=result.communication_metrics.dropped_packets;
    invalid(k)=result.communication_metrics.invalid_packets;
end
baseline = find(speedups == 1,1);
peakDiff = abs(peak-peak(baseline)); overshootDiff = abs(overshoot-overshoot(baseline));
settlingDiff = abs(settling-settling(baseline));
steadyDiff = abs(steadyError-steadyError(baseline)); rmseDiff = abs(rmse-rmse(baseline));
consistent = verdict == "PASS" & peakDiff <= 0.1 & overshootDiff <= 2 & ...
    settlingDiff <= 0.1 & steadyDiff <= 0.1 & rmseDiff <= 0.1 & ...
    lost == 0 & invalid == 0;
summary = table(speedups,runDirectories,verdict,peak,overshoot,settling, ...
    steadyError,rmse,lost,invalid,peakDiff,overshootDiff,settlingDiff, ...
    steadyDiff,rmseDiff,consistent, ...
    'VariableNames',{'Speedup','RunDirectory','Verdict','Peak_deg', ...
    'Overshoot_percent','SettlingTime_s','SteadyStateError_deg','RMSE_deg', ...
    'LostPackets','InvalidPackets','PeakDifference_deg', ...
    'OvershootDifference_pp','SettlingDifference_s', ...
    'SteadyErrorDifference_deg','RMSEDifference_deg','Consistent'});
writetable(summary,fullfile(outputDirectory,"speedup_summary.csv"));
reliable = speedups(consistent); if isempty(reliable), recommended = 0;
else, recommended = max(reliable); end
evidence = struct("verdict",passFail(all(consistent)), ...
    "recommended_max_reliable_speedup",recommended, ...
    "tested_speedups",speedups(:)',"all_consistent",all(consistent));
writeJson(fullfile(outputDirectory,"speedup_verdict.json"),evidence);
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function writeJson(path,value)
fid = fopen(path,"w"); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end
