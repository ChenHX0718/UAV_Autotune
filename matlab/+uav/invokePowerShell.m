function output = invokePowerShell(scriptPath,arguments)
%INVOKEPOWERSHELL Execute one project script and fail on a nonzero exit.
arguments
    scriptPath (1,1) string
    arguments (1,:) string = strings(1,0)
end
parts = ["&",quote(scriptPath)];
for index = 1:numel(arguments)
    if mod(index,2) == 1 && startsWith(arguments(index),"-")
        parts(end+1) = arguments(index); %#ok<AGROW>
    else
        parts(end+1) = quote(arguments(index)); %#ok<AGROW>
    end
end
% Transport the complete invocation as UTF-16LE Base64. This avoids the
% Windows console code page corrupting non-ASCII project/run paths between
% MATLAB, powershell.exe and wsl.exe.
command = "$ProgressPreference='SilentlyContinue'; "+strjoin(parts," ");
encoded = matlab.net.base64encode(unicode2native(char(command),"UTF-16LE"));
[status,output] = system("powershell.exe -NoProfile -NonInteractive " + ...
    "-OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand "+string(encoded));
if status ~= 0
    error("UAVV541:PowerShellFailed", ...
        "PowerShell script failed (%s):\n%s",scriptPath,output);
end
end

function value = quote(value)
value = replace(string(value),"'","''");
value = "'"+value+"'";
end
