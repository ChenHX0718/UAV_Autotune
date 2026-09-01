function [protocolCommand,rcTrace] = ardupilot_sitl_controller(action,P,time,inputVector)
%ARDUPILOT_SITL_CONTROLLER Persistent V5.2 raw-interface JSON bridge.
persistent bridge
if nargin < 1, action = "close"; end
protocolCommand = [];
rcTrace = [];
switch lower(string(action))
    case "reset"
        closeBridge();
        bridge = ArduPilotJSONBridge(P);
    case "step"
        if isempty(bridge) || ~isvalid(bridge)
            bridge = ArduPilotJSONBridge(P);
        end
        [protocolCommand,rcTrace] = bridge.step( ...
            time,inputVector(1:3),inputVector(4:19));
    case "close"
        closeBridge();
    otherwise
        error("UAV:UnknownSITLBridgeAction", ...
            "Unknown ArduPilot SITL bridge action '%s'.",action);
end

    function closeBridge()
        if ~isempty(bridge) && isvalid(bridge)
            delete(bridge);
        end
        bridge = [];
    end
end
