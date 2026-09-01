function report = checkEnvironment(outputFile)
%CHECKENVIRONMENT Detect dependencies without installing or deleting anything.
arguments
    outputFile (1,1) string = fullfile(v52.projectRoot(),"results","v5_4_1", ...
        "logs","environment_report_current.txt")
end
root = v52.projectRoot();
cfg = v52.loadConfiguration("fbwa_roll_rc_positive");
items = strings(0,1); status = strings(0,1); detail = strings(0,1);
add("PROJECT_ROOT",isfolder(root),root);
add("TRUTH_MODEL",isfile(fullfile(root,"model", ...
    string(cfg.project.model_name)+".slx")),fullfile(root,"model", ...
    string(cfg.project.model_name)+".slx"));
add("MATLAB_RELEASE",true,string(version("-release"))+" / "+string(version));
installedProducts = ver;
toolboxNames = string({installedProducts.Name});
add("SIMULINK",any(toolboxNames == "Simulink"),strjoin(toolboxNames,", "));
add("INSTRUMENT_CONTROL",any(contains(toolboxNames,"Instrument Control")), ...
    "udpport is required");
add("AEROSPACE_BLOCKSET",any(contains(toolboxNames,"Aerospace Blockset")), ...
    "6DOF and atmosphere blocks are required");
try
    socket = udpport("datagram","IPV4","LocalPort", ...
        double(cfg.project.network.json_udp_port));
    clear socket
    udpAvailable = true; udpDetail = "UDP "+cfg.project.network.json_udp_port;
catch ME
    udpAvailable = false; udpDetail = string(ME.message);
end
add("JSON_UDP_PORT",udpAvailable,udpDetail);

wslReport = "NOT_AVAILABLE";
try
    script = fullfile(root,"tools","report_wsl_environment.ps1");
    wslReport = string(v52.invokePowerShell(script,["-Distro", ...
        string(cfg.project.wsl.preferred_distro)]));
catch ME
    wslReport = string(ME.message);
end
wslPass = contains(wslReport,"DISTRO="+string(cfg.project.wsl.preferred_distro)) && ...
    contains(wslReport,"WSL_VERSION=2");
linuxPass = contains(wslReport,"OS_ID=ubuntu") && ...
    contains(wslReport,"OS_VERSION_ID=24.04") && ...
    contains(wslReport,"PYTHON=Python 3.12") && ...
    contains(wslReport,"BINARY_SHA256=");
commitPass = contains(wslReport, ...
    "ARDUPILOT_COMMIT="+string(cfg.project.ardupilot.commit));
add("WSL",wslPass,wslReport);
add("LINUX_TOOLCHAIN",wslPass && linuxPass,wslReport);
add("ARDUPILOT_COMMIT",commitPass,wslReport);
report = table(items,status,detail,'VariableNames',{'Item','Status','Detail'});

lines = ["V5.2 environment report"; ...
    "Generated: "+string(datetime("now","Format","yyyy-MM-dd HH:mm:ss Z")); ...
    "Project: "+root; ...
    "ArduPilot tag: "+string(cfg.project.ardupilot.tag); ...
    "ArduPilot commit: "+string(cfg.project.ardupilot.commit); ...
    "Build target: "+string(cfg.project.ardupilot.build_target); ...
    ""; compose("%-24s %-8s %s",report.Item,report.Status,report.Detail)];
writeText(outputFile,strjoin(lines,newline));

    function add(name,passed,text)
        items(end+1,1) = string(name);
        if passed, status(end+1,1) = "PASS"; else, status(end+1,1) = "FAIL"; end
        detail(end+1,1) = string(text);
    end
end

function writeText(filePath,content)
fid = fopen(filePath,"w");
if fid < 0, error("UAVV52:EnvironmentReport","Cannot write %s",filePath); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",content);
end
