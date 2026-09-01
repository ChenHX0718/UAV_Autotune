function summary = writeRepeatabilitySummary(runDirectories,outputDirectory)
%WRITEREPEATABILITYSUMMARY Compare identical FBWA roll runs.
arguments
    runDirectories (:,1) string
    outputDirectory (1,1) string = fullfile(v52.projectRoot(),"results")
end
if numel(runDirectories) < 3
    error("UAVV52:RepeatabilityCount","At least three runs are required.");
end
n = numel(runDirectories); run = (1:n)'; verdict = strings(n,1);
peak = nan(n,1); settling = nan(n,1); steadyError = nan(n,1); rmse = nan(n,1);
for k = 1:n
    result = jsondecode(fileread(fullfile(runDirectories(k),"result.json")));
    verdict(k) = string(result.overall);
    peak(k) = result.dynamic_metrics.peak_deg;
    settling(k) = result.dynamic_metrics.settling_time_s;
    steadyError(k) = result.dynamic_metrics.steady_state_error_deg;
    rmse(k) = result.dynamic_metrics.rmse_deg;
end
summary = table(run,runDirectories,verdict,peak,settling,steadyError,rmse, ...
    'VariableNames',{'Run','RunDirectory','Verdict','Peak_deg', ...
    'SettlingTime_s','SteadyStateError_deg','RMSE_deg'});
writetable(summary,fullfile(outputDirectory,"repeatability_summary.csv"));
ranges = struct("peak_difference_deg",max(peak)-min(peak), ...
    "settling_time_difference_s",max(settling)-min(settling), ...
    "steady_state_error_difference_deg",max(steadyError)-min(steadyError), ...
    "rmse_difference_deg",max(rmse)-min(rmse));
tolerance = struct("peak_difference_deg",0.05, ...
    "settling_time_difference_s",0.05, ...
    "steady_state_error_difference_deg",0.05,"rmse_difference_deg",0.05);
pass = all(verdict == "PASS") && ...
    ranges.peak_difference_deg <= tolerance.peak_difference_deg && ...
    ranges.settling_time_difference_s <= tolerance.settling_time_difference_s && ...
    ranges.steady_state_error_difference_deg <= tolerance.steady_state_error_difference_deg && ...
    ranges.rmse_difference_deg <= tolerance.rmse_difference_deg;
evidence = struct("verdict",passFail(pass),"run_count",n, ...
    "ranges",ranges,"tolerances",tolerance);
writeJson(fullfile(outputDirectory,"repeatability_verdict.json"),evidence);
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end

function writeJson(path,value)
fid = fopen(path,"w"); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end
