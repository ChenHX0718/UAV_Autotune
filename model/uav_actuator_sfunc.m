function uav_actuator_sfunc(block)
%UAV_ACTUATOR_SFUNC V5.4.1 PWM calibration and engineering actuator dynamics.
setup(block);
end

function setup(block)
block.NumDialogPrms = 1;
block.NumInputPorts = 1;
block.NumOutputPorts = 3;
block.InputPort(1).Dimensions = 5;
block.InputPort(1).DirectFeedthrough = false;
for port = 1:3
    block.OutputPort(port).Dimensions = 5;
end
P = block.DialogPrm(1).Data;
block.SampleTimes = [P.actuator.sample_time_s 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("PostPropagationSetup",@postPropagationSetup);
block.RegBlockMethod("InitializeConditions",@initializeConditions);
block.RegBlockMethod("Outputs",@outputs);
block.RegBlockMethod("Update",@update);
end

function postPropagationSetup(block)
P = block.DialogPrm(1).Data;
initial = actuator_initial_state(P);
historyElements = numel(initial.target_history);
dimensions = [5,5,5,5,5,historyElements,1,1];
names = ["servo_shaft","physical_surface","physical_rate", ...
    "saturated","previous_pwm","target_history","history_index", ...
    "protocol_ready"];
block.NumDworks = numel(names);
for index = 1:numel(names)
    block.Dwork(index).Name = names(index);
    block.Dwork(index).Dimensions = dimensions(index);
    block.Dwork(index).DatatypeID = 0;
    block.Dwork(index).Complexity = "Real";
    block.Dwork(index).UsedAsDiscState = true;
end
end

function initializeConditions(block)
state = actuator_initial_state(block.DialogPrm(1).Data);
writeState(block,state);
end

function outputs(block)
block.OutputPort(1).Data = block.Dwork(2).Data;
block.OutputPort(2).Data = block.Dwork(3).Data;
block.OutputPort(3).Data = block.Dwork(4).Data;
end

function update(block)
P = block.DialogPrm(1).Data;
state = readState(block,P);
state = actuator_discrete_step(P,block.InputPort(1).Data,state);
writeState(block,state);
end

function state = readState(block,P)
state = actuator_initial_state(P);
state.shaft = block.Dwork(1).Data;
state.surface = block.Dwork(2).Data;
state.rate = block.Dwork(3).Data;
state.saturated = block.Dwork(4).Data;
state.previous_pwm = block.Dwork(5).Data;
state.target_history = reshape(block.Dwork(6).Data,5,[]);
state.history_index = block.Dwork(7).Data;
state.protocol_ready = logical(block.Dwork(8).Data);
end

function writeState(block,state)
block.Dwork(1).Data = state.shaft;
block.Dwork(2).Data = state.surface;
block.Dwork(3).Data = state.rate;
block.Dwork(4).Data = state.saturated;
block.Dwork(5).Data = state.previous_pwm;
block.Dwork(6).Data = state.target_history(:);
block.Dwork(7).Data = state.history_index;
block.Dwork(8).Data = double(state.protocol_ready);
end
