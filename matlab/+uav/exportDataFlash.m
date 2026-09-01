function [pass,detail] = exportDataFlash(runDir,distro)
%EXPORTDATAFLASH Export WSL ArduPlane DataFlash evidence for one run.
arguments
    runDir (1,1) string
    distro (1,1) string
end

script = fullfile(uav.projectRoot(),"scripts","sitl", ...
    "export_dataflash_wsl.ps1");
pass = false;
detail = "";
try
    detail = uav.invokePowerShell(script, ...
        ["-RunDirectory",runDir,"-Distro",distro]);
    pass = isfile(fullfile(runDir,"internal_ATT.csv"));
catch ME
    detail = string(ME.message);
end
end
