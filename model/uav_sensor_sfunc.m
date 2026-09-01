function uav_sensor_sfunc(block)
%UAV_SENSOR_SFUNC V5.4.1 sampled bias/drift/noise/delay sensor model.
setup(block);
end

function setup(block)
P = block.DialogPrm(1).Data;
block.NumDialogPrms = 1;
block.NumInputPorts = 1;
block.NumOutputPorts = 1;
block.InputPort(1).Dimensions = 16;
block.InputPort(1).DirectFeedthrough = true;
block.OutputPort(1).Dimensions = 16;
block.SampleTimes = [P.sensor.base_sample_time_s 0];
block.SimStateCompliance = "DefaultSimState";
block.RegBlockMethod("PostPropagationSetup",@postPropagationSetup);
block.RegBlockMethod("InitializeConditions",@initializeConditions);
block.RegBlockMethod("Outputs",@outputs);
block.RegBlockMethod("Update",@update);
end

function postPropagationSetup(block)
P = block.DialogPrm(1).Data;
historyLength = max(2,ceil(max(P.sensor.vector.delay_s)/ ...
    P.sensor.base_sample_time_s)+2);
block.NumDworks = 5;
dimensions = [16,16*historyLength,1,1,1];
names = ["measurement","truth_history","write_index", ...
    "initialized","sample_counter"];
for index = 1:numel(names)
    block.Dwork(index).Name = names(index);
    block.Dwork(index).Dimensions = dimensions(index);
    block.Dwork(index).DatatypeID = 0;
    block.Dwork(index).Complexity = "Real";
    block.Dwork(index).UsedAsDiscState = true;
end
end

function initializeConditions(block)
block.Dwork(1).Data = zeros(16,1);
block.Dwork(2).Data = zeros(block.Dwork(2).Dimensions,1);
block.Dwork(3).Data = 1;
block.Dwork(4).Data = 0;
block.Dwork(5).Data = 0;
end

function outputs(block)
mode = sensorMode(block.DialogPrm(1).Data);
if mode ~= "engineering" || block.Dwork(4).Data < 0.5
    block.OutputPort(1).Data = block.InputPort(1).Data;
else
    block.OutputPort(1).Data = block.Dwork(1).Data;
end
end

function update(block)
P = block.DialogPrm(1).Data;
truth = double(block.InputPort(1).Data);
if sensorMode(P) ~= "engineering"
    block.Dwork(1).Data = truth;
    block.Dwork(4).Data = 1;
    return
end

history = reshape(block.Dwork(2).Data,16,[]);
historyLength = size(history,2);
writeIndex = mod(round(block.Dwork(3).Data)-1,historyLength)+1;
if block.Dwork(4).Data < 0.5
    history = repmat(truth,1,historyLength);
end
history(:,writeIndex) = truth;

measurement = block.Dwork(1).Data;
counter = round(block.Dwork(5).Data);
baseSample = double(P.sensor.base_sample_time_s);
for channel = 1:16
    samplePeriod = max(round(P.sensor.vector.sample_time_s(channel)/baseSample),1);
    if mod(counter,samplePeriod) ~= 0 && block.Dwork(4).Data >= 0.5
        continue
    end
    delaySamples = max(P.sensor.vector.delay_s(channel),0)/baseSample;
    whole = floor(delaySamples);
    fraction = delaySamples-whole;
    recentIndex = mod(writeIndex-whole-1,historyLength)+1;
    olderIndex = mod(writeIndex-whole-2,historyLength)+1;
    delayedTruth = (1-fraction)*history(channel,recentIndex) + ...
        fraction*history(channel,olderIndex);
    time = double(block.CurrentTime);
    drift = P.sensor.vector.drift_amplitude(channel)*sin( ...
        2*pi*P.sensor.vector.drift_frequency_hz(channel)*time + 0.41*channel);
    sampleIndex = floor(time/max(P.sensor.vector.sample_time_s(channel),baseSample));
    noise = P.sensor.vector.noise_std(channel)* ...
        deterministic_gaussian(sampleIndex,P.sensor.random_seed,channel);
    value = delayedTruth + P.sensor.vector.bias(channel) + drift + noise;
    quantum = P.sensor.vector.quantization(channel);
    if quantum > 0, value = round(value/quantum)*quantum; end
    measurement(channel) = value;
end

block.Dwork(1).Data = measurement;
block.Dwork(2).Data = history(:);
block.Dwork(3).Data = mod(writeIndex,historyLength)+1;
block.Dwork(4).Data = 1;
block.Dwork(5).Data = counter+1;
end

function mode = sensorMode(P)
mode = "engineering";
if isfield(P,"fidelity") && isfield(P.fidelity,"sensor")
    mode = lower(string(P.fidelity.sensor));
elseif isfield(P,"interface") && isfield(P.interface,"sensor_fidelity")
    mode = lower(string(P.interface.sensor_fidelity));
end
if mode == "engineering" && isfield(P,"controller") && ...
        lower(string(P.controller.backend)) == "ardupilot_sitl" && ...
        isfield(P.sensor,"native_sitl") && P.sensor.native_sitl
    mode = "native_sitl";
end
if ~ismember(mode,["ideal","engineering","native_sitl"])
    error("UAVV541:SensorFidelity","Unsupported sensor fidelity '%s'.",mode);
end
end
