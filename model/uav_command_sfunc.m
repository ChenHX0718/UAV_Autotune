function uav_command_sfunc(block)
%UAV_COMMAND_SFUNC Emit the formal normalized-RC scenario command.
setup(block);
end

function setup(block)
block.NumDialogPrms = 1;
block.NumInputPorts = 0;
block.NumOutputPorts = 1;
block.OutputPort(1).Dimensions = 3;
block.OutputPort(1).SamplingMode = "Sample";
block.SampleTimes = [0 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("Outputs",@outputs);
end

function outputs(block)
P = block.DialogPrm(1).Data;
if ~isfield(P,"interface") || ~isfield(P.interface,"scenario")
    % Plant-only authority validation does not use RC input.
    block.OutputPort(1).Data = [P.init.Va;0;0];
    return
end
scenario = P.interface.scenario;
if lower(string(scenario.command_semantics)) ~= "rc_normalized"
    error("UAVV541:CommandSemantics", ...
        "Only rc_normalized scenario commands are supported.");
end
axisName = lower(string(scenario.axis));
if ~ismember(axisName,["roll","pitch"])
    error("UAVV541:CommandAxis", ...
        "Formal native AUTOTUNE supports roll or pitch, not %s.",axisName);
end
fieldName = "rc_"+axisName+"_normalized";
if ~isfield(scenario,fieldName)
    error("UAVV541:InvalidScenario","Scenario lacks %s.",fieldName);
end
times = double(scenario.time_s(:));
values = double(scenario.(fieldName)(:));
if numel(times) ~= numel(values) || isempty(times) || times(1) ~= 0 || ...
        any(diff(times) <= 0) || any(abs(values) > 1)
    error("UAVV541:InvalidScenario", ...
        "RC time/value arrays must match, start at zero, increase, and stay in [-1,1].");
end
index = find(times <= block.CurrentTime,1,"last");
if isempty(index), index = 1; end
value = values(index);
if axisName == "roll"
    command = [P.init.Va;0;value];
else
    command = [P.init.Va;value;0];
end
block.OutputPort(1).Data = command;
end
