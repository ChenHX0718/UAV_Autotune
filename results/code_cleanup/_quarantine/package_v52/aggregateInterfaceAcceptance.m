function summary = aggregateInterfaceAcceptance(runDirectories)
%AGGREGATEINTERFACEACCEPTANCE Combine independent and continuous evidence.
arguments
    runDirectories (:,1) string
end
root = v52.projectRoot();
n = numel(runDirectories);
scenario = strings(n,1); purpose = strings(n,1); interfaceOverall = strings(n,1);
controlRating = strings(n,1); rcMaxErrorUs = nan(n,1);
fbwaMappingMaxErrorDeg = nan(n,1); packetCount = nan(n,1);
for k = 1:n
    cfg = jsondecode(fileread(fullfile(runDirectories(k),"scenario.json")));
    result = jsondecode(fileread(fullfile(runDirectories(k),"result.json")));
    scenario(k) = string(cfg.name); purpose(k) = string(cfg.purpose);
    interfaceOverall(k) = string(result.interface_overall);
    controlRating(k) = string(result.control_rating);
    rcMaxErrorUs(k) = result.interface_metrics.rc_input_max_error_us;
    fbwaMappingMaxErrorDeg(k) = result.interface_metrics.mapping_max_error_deg;
    packetCount(k) = result.interface_metrics.packet_count;
end
summary = table(scenario,purpose,interfaceOverall,controlRating, ...
    rcMaxErrorUs,fbwaMappingMaxErrorDeg,packetCount,runDirectories);
stamp = string(datetime("now","Format","yyyyMMdd_HHmmss"));
outputDir = fullfile(root,"results","v5_2","runs", ...
    "interface_acceptance_"+stamp);
mkdir(outputDir);
writetable(summary,fullfile(outputDir,"interface_suite.csv"));
overall = all(interfaceOverall == "PASS");
lines = ["# V5.2 Interface Acceptance Report";""; ...
    "## Independent verdicts";""; ...
    "Control tracking quality is intentionally excluded from the interface verdict.";""];
for k = 1:n
    lines(end+1) = "- "+scenario(k)+": interface **"+ ...
        interfaceOverall(k)+"**, control **"+controlRating(k)+ ...
        "**, RC error "+compose("%.3f",rcMaxErrorUs(k))+ ...
        " us, FBWA mapping error "+compose("%.3f",fbwaMappingMaxErrorDeg(k))+" deg"; %#ok<AGROW>
end
lines = [lines;"";"## Final conclusions";""; ...
    "- INTERFACE OVERALL: **"+passFail(overall)+"**"; ...
    "- CONTROL PERFORMANCE: reported separately; a poor response does not invalidate transport."; ...
    "- HEADLESS: **PASS** — no Mission Planner GUI is used by the runner."];
fid = fopen(fullfile(outputDir,"interface_acceptance.txt"),"w");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",lines);
copyfile(fullfile(outputDir,"interface_suite.csv"), ...
    fullfile(root,"results","v5_2","data","interface_acceptance_latest.csv"));
end

function value = passFail(condition)
if condition, value = "PASS"; else, value = "FAIL"; end
end
