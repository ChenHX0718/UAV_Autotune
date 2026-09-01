function uav_autopilot_sfunc(block)
%UAV_AUTOPILOT_SFUNC ArduPilot SITL adapter or explicit plant-test bypass.
% The retired in-model PID/TECS approximation is intentionally unavailable.
setup(block);
end

function setup(block)
block.NumDialogPrms = 1;
block.NumInputPorts = 1;
block.NumOutputPorts = 2;
block.InputPort(1).Dimensions = 19;
block.InputPort(1).DirectFeedthrough = true;
block.OutputPort(1).Dimensions = 9;
block.OutputPort(2).Dimensions = 14;
block.SampleTimes = [0.02 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("InitializeConditions",@initializeConditions);
block.RegBlockMethod("Outputs",@outputs);
block.RegBlockMethod("Terminate",@terminate);
end

function initializeConditions(block)
P = block.DialogPrm(1).Data;
if controllerBackend(P) == "ardupilot_sitl"
    ardupilot_sitl_controller("reset",P);
end
end

function outputs(block)
P = block.DialogPrm(1).Data;
switch controllerBackend(P)
    case "ardupilot_sitl"
        [protocolCommand,rcTrace] = ardupilot_sitl_controller( ...
            "step",P,block.CurrentTime,block.InputPort(1).Data);
    case "test_direct_actuator"
        pwm = direct_actuator_pwm(P,block.CurrentTime);
        protocolCommand = [pwm(:);block.CurrentTime;0;50;1];
        rcTrace = [zeros(4,1);1500*ones(8,1);block.CurrentTime;1];
    otherwise
        error("UAVV541:ControllerBackend", ...
            "Controller backend must be ardupilot_sitl or test_direct_actuator.");
end
block.OutputPort(1).Data = protocolCommand;
block.OutputPort(2).Data = rcTrace;
end

function terminate(block)
P = block.DialogPrm(1).Data;
if controllerBackend(P) == "ardupilot_sitl"
    ardupilot_sitl_controller("close",P);
end
end

function backend = controllerBackend(P)
backend = "unconfigured";
if isfield(P,"controller") && isfield(P.controller,"backend")
    backend = lower(string(P.controller.backend));
end
end
