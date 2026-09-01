function [entryMode,exitMode,session] = waitModeSession(runDirectory,options)
%WAITMODESESSION Collect the mode companion's atomic JSON evidence files.
arguments
    runDirectory (1,1) string
    options.TimeoutSeconds (1,1) double {mustBePositive} = 30
end
entryFile = fullfile(runDirectory,"mode_entry.json");
exitFile = fullfile(runDirectory,"mode_exit.json");
sessionFile = fullfile(runDirectory,"mode_session.json");
deadline = tic;
while toc(deadline) < options.TimeoutSeconds
    if isfile(entryFile) && isfile(exitFile) && isfile(sessionFile)
        break
    end
    pause(0.2)
end
entryMode = readEvidence(entryFile,"ENTRY_MODE_EVIDENCE_MISSING");
exitMode = readEvidence(exitFile,"EXIT_MODE_EVIDENCE_MISSING");
session = readEvidence(sessionFile,"MODE_SESSION_EVIDENCE_MISSING");
end

function value = readEvidence(filePath,detail)
value = struct("pass",false,"failure_reason","MODE_CHANGE_FAIL", ...
    "detail",detail);
if ~isfile(filePath), return; end
try
    value = jsondecode(fileread(filePath));
catch ME
    value.detail = "INVALID_MODE_EVIDENCE: "+string(ME.message);
end
end
