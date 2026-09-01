function result = test_sensor_model()
%TEST_SENSOR_MODEL Verify IDEAL/ENGINEERING sensor chains and SIM_* map.

root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"model"),"-begin");
addpath(fullfile(root,"matlab"),"-begin");
create_interface_buses();
modelName = "UAV_Autotune_Model_4Axis";
open_system(fullfile(root,"model",modelName+".slx"));

fidelities = ["IDEAL","ENGINEERING"];
inputs(1,2) = Simulink.SimulationInput(modelName);
for index = 1:2
    P = uav_config("UAV_A",13);
    P.controller.backend = "test_direct_actuator";
    P.control_authority.profile = struct("axis","roll", ...
        "command_fraction",0,"command_direction",1, ...
        "pulse_start_s",0,"pulse_end_s",23,"test_only",true);
    P.fidelity.actuator = "ENGINEERING";
    P.fidelity.sensor = fidelities(index);
    P.sensor.native_sitl = false;
    inputs(index) = Simulink.SimulationInput(modelName);
    inputs(index) = inputs(index).setVariable("P",P);
    inputs(index) = inputs(index).setModelParameter("StopTime","22", ...
        "SolverType","Fixed-step","Solver","ode4","FixedStep","0.005", ...
        "ReturnWorkspaceOutputs","on");
end
outputs = sim(inputs,"ShowProgress","off");
close_system(modelName,0);

idealTruth = double(outputs(1).truth_state_log.Data);
idealMeasured = double(outputs(1).measured_state_log.Data);
engineeringTruth = double(outputs(2).truth_state_log.Data);
engineeringMeasured = double(outputs(2).measured_state_log.Data);
t = double(outputs(2).measured_state_log.Time);
idealMaxError = max(abs(idealMeasured-idealTruth),[],"all");
errorSignal = engineeringMeasured-engineeringTruth;

gyroError = errorSignal(:,7:9);
gyroBias = mean(gyroError,1);
gyroNoiseStd = std(gyroError-movmean(gyroError,401,1),0,1);
gyroDriftRange = range(movmean(gyroError(:,1),2001));
baroBias = mean(errorSignal(:,16));
airspeedBias = mean(errorSignal(:,15));
magBiasDeg = rad2deg(mean(errorSignal(:,12)));

gpsChanges = find([true;any(abs(diff(engineeringMeasured(:,1:3),1,1)) > 1e-9,2)]);
gpsChangeTimes = t(gpsChanges);
gpsIntervals = diff(gpsChangeTimes);
gpsIntervals = gpsIntervals(gpsIntervals > 0.05);
gpsUpdateInterval = median(gpsIntervals);
delay = P.sensor.gps_position.delay_s;
truthDelayed = interp1(t,engineeringTruth(:,1),max(t-delay,t(1)),"linear");
gpsZeroDelayRmse = sqrt(mean((engineeringMeasured(:,1)-engineeringTruth(:,1)).^2));
gpsAlignedRmse = sqrt(mean((engineeringMeasured(:,1)-truthDelayed).^2));

native = uav.sensorParameterOverrides(P);
names = string(fieldnames(native));
values = cellfun(@(name) double(native.(name)),cellstr(names));
nativeTable = table(names,values,'VariableNames',{'Parameter','EngineeringValue'});
outputDir = fullfile(root,"results","v5_4_1","validation","sensor");
if ~isfolder(outputDir), mkdir(outputDir); end
writetable(nativeTable,fullfile(outputDir,"native_sitl_sensor_parameters.csv"));

summary = table(idealMaxError,logical(norm(gyroBias) > 0), ...
    logical(any(gyroNoiseStd > 0)),logical(gyroDriftRange > 0), ...
    logical(abs(gpsUpdateInterval-0.2) <= 0.02), ...
    logical(gpsAlignedRmse < gpsZeroDelayRmse), ...
    logical(abs(baroBias) > 0),logical(abs(airspeedBias) > 0), ...
    logical(abs(magBiasDeg) > 0), ...
    logical(native.SIM_ACC1_RND > 0 && native.SIM_ACC1_BIAS_Z ~= 0), ...
    'VariableNames',{'IdealMaximumError','GyroBiasPass','GyroNoisePass', ...
    'GyroDriftPass','GPSSamplingPass','GPSDelayPass','BarometerBiasPass', ...
    'AirspeedBiasPass','MagnetometerBiasPass','AccelerometerNativeInjectionPass'});
details = table(norm(gyroBias),mean(gyroNoiseStd),gyroDriftRange, ...
    gpsUpdateInterval,gpsZeroDelayRmse,gpsAlignedRmse,baroBias, ...
    airspeedBias,magBiasDeg, ...
    'VariableNames',{'GyroBiasNorm_rad_s','GyroNoiseStd_rad_s', ...
    'GyroDriftRange_rad_s','GPSUpdateInterval_s','GPSZeroDelayRMSE_m', ...
    'GPSAlignedRMSE_m','BarometerMeanError_m','AirspeedMeanError_m_s', ...
    'MagnetometerMeanHeadingError_deg'});
writetable(summary,fullfile(outputDir,"sensor_validation_summary.csv"));
writetable(details,fullfile(outputDir,"sensor_validation_metrics.csv"));

figure("Visible","off","Color","w","Position",[100,100,1050,760]);
tiledlayout(3,1,"TileSpacing","compact");
nexttile; plot(t,rad2deg(gyroError),"LineWidth",0.8); grid on;
ylabel("Gyro error (deg/s)"); legend("x","y","z");
nexttile; plot(t,errorSignal(:,[1,2,3,16]),"LineWidth",0.8); grid on;
ylabel("GPS/baro error (m)"); legend("N","E","D","baro");
nexttile; plot(t,[errorSignal(:,15),rad2deg(errorSignal(:,12))],"LineWidth",0.8); grid on;
ylabel("Airspeed / heading error"); xlabel("Time (s)");
legend("airspeed (m/s)","heading (deg)");
exportgraphics(gcf,fullfile(outputDir,"sensor_error_time_histories.png"),"Resolution",170);
close(gcf);
result = struct("summary",summary,"metrics",details,"native_parameters",nativeTable);
disp(summary); disp(details);
end
