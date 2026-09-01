function evidence = changeSITLMode(modeName,outputFile,options)
%CHANGESITLMODE Require MAV_CMD_DO_SET_MODE ACK plus heartbeat read-back.
arguments
    modeName (1,1) string {mustBeMember(modeName,["FBWA","AUTOTUNE"])}
    outputFile (1,1) string
    options.Distro (1,1) string = "Ubuntu-24.04"
    options.TimeoutSeconds (1,1) double = 20
end
script = fullfile(v53.projectRoot(),"tools","change_mode_wsl.ps1");
try
    v52.invokePowerShell(script,["-Mode",modeName,"-OutputFile",outputFile, ...
        "-Distro",options.Distro,"-TimeoutSeconds",string(options.TimeoutSeconds)]);
catch ME
    if isfile(outputFile)
        evidence = jsondecode(fileread(outputFile));
        evidence.tool_error = string(ME.message);
        return
    end
    evidence = struct("requested_mode",modeName,"pass",false, ...
        "failure_reason","MODE_CHANGE_FAIL","detail",string(ME.message));
    writeJson(outputFile,evidence);
    return
end
evidence = jsondecode(fileread(outputFile));
end

function writeJson(filePath,value)
folder = fileparts(filePath); if ~isfolder(folder), mkdir(folder); end
fid = fopen(filePath,"w"); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",jsonencode(value,"PrettyPrint",true));
end
