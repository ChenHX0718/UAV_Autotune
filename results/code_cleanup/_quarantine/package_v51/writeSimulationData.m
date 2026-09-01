function data = writeSimulationData(out,P,loggingStep,outputFile)
%WRITESIMULATIONDATA Save all truth, command, actuator and rate channels.
arguments
    out Simulink.SimulationOutput
    P struct
    loggingStep (1,1) double {mustBePositive}
    outputFile (1,1) string
end
truthSignal = out.get("truth_state_log");
commandSignal = out.get("cmd_log");
actuatorCommandSignal = out.get("actuator_cmd_log");
actuatorActualSignal = out.get("actuator_actual_log");
t = (0:loggingStep:min(P.sim.stop_time,double(truthSignal.Time(end))))';
truth = sampleSignal(truthSignal,t,"linear");
command = sampleSignal(commandSignal,t,"previous");
actuatorCommand = sampleSignal(actuatorCommandSignal,t,"previous");
actuatorActual = sampleSignal(actuatorActualSignal,t,"previous");

rollTarget = zeros(size(t));
pitchTarget = zeros(size(t));
axisName = lower(string(P.v51.scenario.axis));
if axisName == "roll"
    rollTarget = rad2deg(command(:,3));
elseif axisName == "pitch"
    pitchTarget = rad2deg(command(:,2)-P.trim.alpha);
end

data = table(t,rollTarget,pitchTarget,command(:,1), ...
    truth(:,1),truth(:,2),truth(:,3),truth(:,4),truth(:,5),truth(:,6), ...
    rad2deg(truth(:,7)),rad2deg(truth(:,8)),rad2deg(truth(:,9)), ...
    rad2deg(truth(:,10)),rad2deg(truth(:,11)),rad2deg(truth(:,12)), ...
    rad2deg(truth(:,13)),rad2deg(truth(:,14)),truth(:,15),truth(:,16), ...
    actuatorCommand(:,1),rad2deg(actuatorCommand(:,2)), ...
    rad2deg(actuatorCommand(:,3)),rad2deg(actuatorCommand(:,4)), ...
    rad2deg(actuatorCommand(:,5)),actuatorActual(:,1), ...
    rad2deg(actuatorActual(:,2)),rad2deg(actuatorActual(:,3)), ...
    rad2deg(actuatorActual(:,4)),rad2deg(actuatorActual(:,5)), ...
    'VariableNames',{'time_s','external_roll_target_deg', ...
    'external_pitch_target_deg','command_airspeed_mps','north_m','east_m', ...
    'down_m','u_mps','v_mps','w_mps','p_deg_s','q_deg_s','r_deg_s', ...
    'roll_deg','pitch_deg','yaw_deg','alpha_deg','beta_deg','airspeed_mps', ...
    'altitude_m','throttle_command','aileron_left_command_deg', ...
    'aileron_right_command_deg','elevator_command_deg','rudder_command_deg', ...
    'throttle_actual','aileron_left_actual_deg','aileron_right_actual_deg', ...
    'elevator_actual_deg','rudder_actual_deg'});
writetable(data,outputFile);
end

function data = sampleSignal(signal,t,method)
sourceTime = double(signal.Time(:));
sourceData = squeeze(double(signal.Data));
if isvector(sourceData), sourceData = sourceData(:); end
[sourceTime,index] = unique(sourceTime,"stable");
sourceData = sourceData(index,:);
if isscalar(sourceTime)
    data = repmat(sourceData,numel(t),1);
else
    data = interp1(sourceTime,sourceData,t,method,"extrap");
end
end
