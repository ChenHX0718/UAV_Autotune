function [pass,detail] = exportDataFlash(runDir,backend,distro,missionPlannerHome)
%EXPORTDATAFLASH Produce ATT/RCIN/RCOU/PID/PARM evidence without a GCS.
arguments
    runDir (1,1) string
    backend (1,1) string
    distro (1,1) string
    missionPlannerHome (1,1) string = ""
end
root = v51.projectRoot();
pass = false;
detail = "";
if backend == "wsl"
    script = fullfile(root,"tools","export_dataflash_wsl.ps1");
    try
        detail = v51.invokePowerShell(script, ...
            ["-RunDirectory",runDir,"-Distro",distro]);
        pass = isfile(fullfile(runDir,"internal_ATT.csv"));
    catch ME
        detail = string(ME.message);
    end
    return
end

binFiles = dir(fullfile(runDir,"logs","*.BIN"));
if isempty(binFiles)
    detail = "No DataFlash BIN log was produced.";
    return
end
if strlength(missionPlannerHome) == 0 || ~isfolder(missionPlannerHome)
    detail = "Mission Planner parser path was not supplied for Windows compatibility export.";
    return
end
[~,latest] = max([binFiles.datenum]);
binFile = fullfile(binFiles(latest).folder,binFiles(latest).name);
script = fullfile(root,"tools","export_dataflash_missionplanner.ps1");
waitForStableLog(binFile,30,90);
for attempt = 1:3
    try
        parserOutput = v51.invokePowerShell(script,["-BinFile",binFile, ...
            "-OutputDirectory",runDir,"-MissionPlannerHome",missionPlannerHome]);
        pass = isfile(fullfile(runDir,"internal_ATT.csv")) && ...
            isfile(fullfile(runDir,"internal_RCIN.csv")) && ...
            isfile(fullfile(runDir,"parameter_readback.csv"));
        if pass
            detail = "DATAFLASH_EXPORT_PASS";
            break
        end
        detail = "Parser returned without producing the required CSV evidence.";
    catch ME
        detail = string(ME.message);
    end
    % A force-stopped Windows compatibility process can need several
    % seconds for its DataFlash file to become fully readable.
    pause(2+2*attempt);
end
end

function waitForStableLog(filePath,requiredStableSeconds,timeoutSeconds)
% Mission Planner's parser can observe an incomplete Windows DataFlash file
% briefly after the SITL process exits. Require unchanged size and write
% timestamp before opening it.
started = tic;
stableStarted = [];
previousSize = -1;
previousStamp = NaN;
while toc(started) < timeoutSeconds
    info = dir(filePath);
    if ~isempty(info) && info.bytes > 0 && info.bytes == previousSize && ...
            info.datenum == previousStamp
        if isempty(stableStarted), stableStarted = tic; end
        if toc(stableStarted) >= requiredStableSeconds, return; end
    else
        stableStarted = [];
        if ~isempty(info)
            previousSize = info.bytes;
            previousStamp = info.datenum;
        end
    end
    pause(2);
end
error("UAVV51:DataFlashNotStable", ...
    "DataFlash log did not become stable within %g seconds: %s", ...
    timeoutSeconds,filePath);
end
