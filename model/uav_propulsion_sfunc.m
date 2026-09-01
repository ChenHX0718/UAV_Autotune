function uav_propulsion_sfunc(block)
%UAV_PROPULSION_SFUNC Electric propulsion force using the shared propulsion model.
setup(block);
end

function setup(block)
block.NumDialogPrms = 1;
block.NumInputPorts = 3;
block.NumOutputPorts = 2;
block.InputPort(1).Dimensions = 5;
block.InputPort(2).Dimensions = 3;
block.InputPort(3).Dimensions = 1;
for k = 1:3
    block.InputPort(k).DirectFeedthrough = true;
end
block.OutputPort(1).Dimensions = 3;
block.OutputPort(2).Dimensions = 3;
P = block.DialogPrm(1).Data;
block.SampleTimes = [P.ctrl.Ts 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("PostPropagationSetup", @postPropagationSetup);
block.RegBlockMethod("InitializeConditions", @initializeConditions);
block.RegBlockMethod("Outputs", @outputs);
block.RegBlockMethod("Update", @update);
end

function postPropagationSetup(block)
block.NumDworks = 2;
block.Dwork(1).Name = "battery_soc";
block.Dwork(1).Dimensions = 1;
block.Dwork(1).DatatypeID = 0;
block.Dwork(1).Complexity = "Real";
block.Dwork(1).UsedAsDiscState = true;
block.Dwork(2).Name = "bus_voltage";
block.Dwork(2).Dimensions = 1;
block.Dwork(2).DatatypeID = 0;
block.Dwork(2).Complexity = "Real";
block.Dwork(2).UsedAsDiscState = true;
end

function initializeConditions(block)
P = block.DialogPrm(1).Data;
if isfield(P,"battery") && P.battery.enable
    block.Dwork(1).Data = min(max(P.battery.initial_soc,0),1);
    block.Dwork(2).Data = P.battery.initial_loaded_voltage_V;
else
    block.Dwork(1).Data = 1;
    block.Dwork(2).Data = P.prop.bus_voltage;
end
end

function outputs(block)
P = block.DialogPrm(1).Data;
actuator = block.InputPort(1).Data;
airdata = block.InputPort(2).Data;
rho = max(block.InputPort(3).Data, 0.1);
throttle = actuator(1);
Va = max(airdata(3), 0);

[thrust, ~] = uav_propulsion_model(P, throttle, Va, rho, ...
    block.Dwork(2).Data);
block.OutputPort(1).Data = [thrust; 0; 0];
block.OutputPort(2).Data = [P.prop.roll_torque_per_thrust*thrust; 0; 0];
end

function update(block)
P = block.DialogPrm(1).Data;
if ~isfield(P,"battery") || ~P.battery.enable
    block.Dwork(2).Data = P.prop.bus_voltage;
    return
end
actuator = block.InputPort(1).Data;
airdata = block.InputPort(2).Data;
rho = max(block.InputPort(3).Data,0.1);
voltage = max(block.Dwork(2).Data,P.battery.min_voltage_V);
[~, powerW] = uav_propulsion_model(P, actuator(1), max(airdata(3),0), ...
    rho, voltage);
currentA = max(powerW,0)/max(voltage,1);
soc = block.Dwork(1).Data - currentA*P.ctrl.Ts/ ...
    max(P.battery.capacity_Ah*3600,eps);
soc = min(max(soc,0),1);
block.Dwork(1).Data = soc;
block.Dwork(2).Data = battery_terminal_voltage(P,soc,currentA);
end
