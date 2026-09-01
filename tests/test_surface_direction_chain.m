function audit = test_surface_direction_chain()
%TEST_SURFACE_DIRECTION_CHAIN Audit command-to-angular-acceleration signs.
% This is a model-chain audit. Right aileron/elevator/rudder installation
% signs remain ASSUMED_FROM_LEFT_AILERON until a hardware bench audit exists.

root = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(root,"model"),"-begin");
P = uav_config("UAV_A",13);
outDir = fullfile(root,"results","v5_4_1","validation","surface_direction");
if ~isfolder(outDir), mkdir(outDir); end

axes = ["roll","roll","pitch","pitch","yaw","yaw"]';
directions = [1;-1;1;-1;1;-1];
rows = cell(numel(axes),1);
for k = 1:numel(axes)
    rows{k} = auditCase(P,axes(k),directions(k));
end
audit = vertcat(rows{:});
writetable(audit,fullfile(outDir,"surface_direction_audit.csv"));

channels = ["Left Aileron";"Right Aileron";"Elevator";"Rudder"];
cfg = {P.servo.aileron_left;P.servo.aileron_right; ...
    P.servo.elevator;P.servo.rudder};
source = strings(4,1); direction = zeros(4,1); minimum = zeros(4,1);
maximum = zeros(4,1); neutralPwm = zeros(4,1);
for k = 1:4
    source(k) = string(cfg{k}.data_source);
    direction(k) = double(cfg{k}.direction);
    minimum(k) = double(cfg{k}.min_deflection_deg);
    maximum(k) = double(cfg{k}.max_deflection_deg);
    neutralPwm(k) = double(cfg{k}.neutral_pwm);
end
sourceAudit = table(channels,source,direction,minimum,maximum,neutralPwm, ...
    'VariableNames',{'Surface','DataSource','Direction', ...
    'MinDeflection_deg','MaxDeflection_deg','NeutralPWM_us'});
writetable(sourceAudit,fullfile(outDir,"surface_data_source_audit.csv"));

assert(all(audit.Pass),"UAVV541:SurfaceDirectionAudit", ...
    "At least one command-to-angular-acceleration chain failed.");
disp(audit);
end

function row = auditCase(P,axisName,direction)
surface = surface_targets(P,axisName,direction);
[~,pwm] = uav_servo_mapping(P,surface,"command_to_pwm");
[roundTrip,~] = uav_servo_mapping(P,pwm,"pwm_to_command");
deltaA = 0.5*(roundTrip(2)-roundTrip(3));
deltaS = 0.5*(roundTrip(2)+roundTrip(3));
deltaE = roundTrip(4); deltaR = roundTrip(5);

Cl = P.aero.Cl_da*deltaA + P.aero.Cl_dr*deltaR;
Cm = P.aero.Cm_de*(deltaE-P.trim.delta_e) + P.aero.Cm_ds*deltaS;
Cn = P.aero.Cn_da*deltaA + P.aero.Cn_dr*deltaR;
rho = 1.2107; qbar = 0.5*rho*P.init.Va^2;
moment = qbar*P.geometry.area*[P.geometry.span*Cl; ...
    P.geometry.chord*Cm;P.geometry.span*Cn];
angularAccel = P.inertia\moment;

opposite = true; differential = true;
if axisName == "roll"
    opposite = roundTrip(2)*roundTrip(3) < 0;
    % The shared same-PWM left/right model has asymmetric endpoint travel
    % across opposite roll directions, but it does not claim measured
    % inter-surface magnitude differential at one command direction.
    differential = abs(abs(roundTrip(2))-abs(roundTrip(3))) > deg2rad(0.1);
end
axisIndex = find(["roll","pitch","yaw"] == axisName,1);
momentCoefficient = [Cl,Cm,Cn];
signPass = sign(momentCoefficient(axisIndex)) == direction && ...
    sign(angularAccel(axisIndex)) == direction;
roundTripError = max(abs(rad2deg(roundTrip(2:5)-surface(2:5))));
pass = opposite && signPass && roundTripError <= 0.15;

row = table(axisName,direction,pwm(2),pwm(3),pwm(4),pwm(5), ...
    rad2deg(roundTrip(2)),rad2deg(roundTrip(3)),rad2deg(roundTrip(4)), ...
    rad2deg(roundTrip(5)),opposite,differential,Cl,Cm,Cn, ...
    rad2deg(angularAccel(1)),rad2deg(angularAccel(2)), ...
    rad2deg(angularAccel(3)),roundTripError,pass, ...
    'VariableNames',{'Axis','CommandDirection','PWM_L_us','PWM_R_us', ...
    'PWM_E_us','PWM_Rudder_us','AileronLeft_deg','AileronRight_deg', ...
    'Elevator_deg','Rudder_deg','AileronsOpposite','DifferentialActive', ...
    'Cl','Cm','Cn','p_dot_deg_s2','q_dot_deg_s2','r_dot_deg_s2', ...
    'RoundTripError_deg','Pass'});
end
