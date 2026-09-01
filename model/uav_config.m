function P = uav_config(aircraftId, cruiseSpeed)
%UAV_CONFIG Central plant and interface parameter file for V5.4.1.
% Edit this file only when changing AIRCRAFT data (A -> B), not when moving
% the project to another computer. Computer-specific paths are handled by
% local_machine_config.mat. Values marked PLACEHOLDER are safe starting
% estimates only and are not flight-qualified.

if nargin < 1 || strlength(string(aircraftId)) == 0
    aircraftId = get_active_aircraft();
end
if nargin < 2 || isempty(cruiseSpeed)
    cruiseSpeed = 13.0;
end
validateattributes(cruiseSpeed,{'numeric'},{'scalar','real','finite', ...
    '>=',5.0,'<=',100.0},mfilename,'cruiseSpeed');

P.meta.aircraft_id = string(aircraftId);
P.meta.model_version = "5.4.1";
P.meta.core_revision = "v5.4.1-cleanup-20260830";
P.meta.warning = "Engineering simulation evidence only; not flight qualification.";

% All generated files are project-relative, so the folder is portable.
P.paths.model_root = string(fileparts(mfilename("fullpath")));
P.paths.root = string(fileparts(P.paths.model_root));
% Every aircraft has isolated source data; generated outputs live in results.
W = uav_workspace(aircraftId,true);
read_aircraft_workspace_manifest(W); % fail early on folder/manifest mismatch
P.paths.aircraft_root = W.aircraft_root;
P.paths.input_root = W.input_root;
P.paths.aero_data = W.aero_data;
P.paths.prop_data = W.prop_data;
P.paths.battery_data = W.battery_data;
P.paths.flight_data = W.flight_data;
P.paths.results = W.results;
P.paths.final_delivery = W.final_delivery;
P.paths.sitl_runtime = W.sitl_runtime;
P.paths.reports = W.reports;
P.mp.target_vehicle = "ArduPlane fixed-wing";
P.ardupilot.target_version = "ArduPlane 4.6.3";
P.ardupilot.version_source = "0816 flight log and target Full Parameter List";

% Only the formal ArduPilot SITL backend is allowed in operational runs.
P.controller.backend = "unconfigured";
P.controller.sitl.executable = "";
P.controller.sitl.host = "127.0.0.1";
P.controller.sitl.servo_port = 9002;
P.controller.sitl.mavlink_host = "127.0.0.1";
P.controller.sitl.mavlink_port = 14550;
P.controller.sitl.use_mavlink_udp = true;
P.controller.sitl.defaults_file_override = "";
P.controller.sitl.frame_rate_hz = 50;
P.controller.sitl.receive_timeout_s = 15;
P.controller.sitl.home = [39.9042,116.4074,120,0];
P.controller.sitl.rc_pwm_min = 1000;
P.controller.sitl.rc_pwm_trim = 1500;
P.controller.sitl.rc_pwm_max = 2000;
P.controller.sitl.channels = struct("aileron_left",1,"elevator",2, ...
    "throttle",3,"rudder",4,"aileron_right",5);
P.controller.sitl.auto_launch = false;
P.controller.sitl.require_real_firmware = true;

switch upper(string(aircraftId))
    case "UAV_A"
        % Rigid body and geometry
        P.mass = 11.926;                         % kg, measured
        P.inertia = [7.533,0,-0.03595;0,1.150,0;-0.03595,0,8.634]; % kg*m^2, confirmed converted body-axis inertia about CG
        P.geometry.span = 5.525419;            % m, XFLR5 primary configuration
        P.geometry.area = 1.570552;            % m^2, XFLR5 primary configuration
        P.geometry.chord = 0.284702;           % m, XFLR5 primary configuration
        % XFLR5 axes supplied by the user: +x aft, +y lift/up, +z left.
        % Simulation body axes: +x forward, +y right, +z down. Therefore
        % [xb;yb;zb] = [-1 0 0;0 0 -1;0 -1 0]*[x5;y5;z5].
        P.geometry.xflr5_to_body = [-1,0,0;0,0,-1;0,-1,0];
        P.geometry.cg_xflr5 = [0.1099; -0.0000; 0.0142]; % m, wing-leading-edge datum
        P.geometry.cg_body = P.geometry.xflr5_to_body * ...
            P.geometry.cg_xflr5;               % [-0.1099;-0.0142;0] m
        P.geometry.cg = P.geometry.cg_body;     % compatibility alias
        % XFLR5 stability moments were generated about this reference CG.
        % If payload/battery moves the current CG, change cg_body only; the
        % aerodynamic block translates M_ref to the new CG with r x F.
        P.geometry.aero_moment_reference_body = P.geometry.cg_body;

    otherwise
        % Non-UAV_A aircraft data live in aircraft/<ID>/aircraft_definition.m.
        % The generated template is locked until config_complete=true so a
        % new UAV can never silently inherit UAV_A rigid-body data.
        Aaircraft = load_aircraft_definition(W);
        cruiseSpeed = double(Aaircraft.flight.cruise_speed);
        P.mass = Aaircraft.mass;
        P.inertia = Aaircraft.inertia;
        P.geometry.span = Aaircraft.geometry.span;
        P.geometry.area = Aaircraft.geometry.area;
        P.geometry.chord = Aaircraft.geometry.chord;
        P.geometry.xflr5_to_body = Aaircraft.geometry.xflr5_to_body;
        P.geometry.cg_xflr5 = Aaircraft.geometry.cg_xflr5(:);
        P.geometry.cg_body = P.geometry.xflr5_to_body * P.geometry.cg_xflr5;
        P.geometry.cg = P.geometry.cg_body;
        P.geometry.aero_moment_reference_body = P.geometry.cg_body;
end

% Resolve this aircraft's own Full Parameter List.  UAV_A keeps its migrated
% historical filename; new aircraft definitions must explicitly name theirs.
if upper(string(aircraftId)) == "UAV_A"
    P.mp.vehicle_parameter_file = fullfile(P.paths.flight_data, ...
        "HL20260816_afterflight.param");
else
    P.mp.vehicle_parameter_file = fullfile(P.paths.flight_data, ...
        string(Aaircraft.flight_parameter_file));
    P.ardupilot.target_version = string(Aaircraft.ardupilot.target_version);
    P.ardupilot.version_source = "aircraft/<ID>/aircraft_definition.m";
end

P.g = 9.80665;                                  % m/s^2
P.env.rho0 = 1.225;                             % kg/m^3
P.env.wind_ned = [0; 0; 0];                    % m/s [north east down]
P.env.gust_enable = false;
P.env.gust_amplitude = [1.0; 0.6; 0.4];        % m/s
P.env.gust_frequency = [0.11; 0.17; 0.23];     % Hz
P.env.gust_phase = [0; 1.1; 2.2];              % rad
P.env.gust_test_speeds = 0:1:7;                % m/s, same gain set for all cases
P.env.gust_test_directions = [1,0,0;0,1,0;0,0,1;1,1,0.5];
P.env.gust_test_direction_names = ["longitudinal","lateral", ...
    "vertical","combined"];
P.env.gust_test_stop_time = 24;                % s per case
P.env.gust_test_fixed_step = 0.01;             % s; bounded runtime for unstable cases
P.env.gust_test_hold_reference = true;         % isolate gust rejection from command steps

% Aerodynamic model loaded from the supplied XFLR5 export.
% "derivative" = local Type-7 stability/control derivative model.
% "table" = static CL/CD/Cm lookup versus alpha and airspeed, with the same
%            dynamic-rate and control derivatives added as perturbations.
P.aero = load_xflr5_aero_data(P.paths.aero_data);
P.aero.mode = "derivative";                    % derivative | table
P.aero.moment_reference_body = ...
    P.geometry.aero_moment_reference_body;

% Physical actuator channels: throttle, left tip, right tip, elevator, rudder.
P.limits.throttle = [0, 1];
servoDataRoot = fullfile(P.paths.aircraft_root,"input","servo_data");
P.servo = load_servo_configuration(servoDataRoot);
P.limits.delta_LT = deg2rad([P.servo.aileron_left.min_deflection_deg, ...
    P.servo.aileron_left.max_deflection_deg]);
P.limits.delta_RT = deg2rad([P.servo.aileron_right.min_deflection_deg, ...
    P.servo.aileron_right.max_deflection_deg]);
P.limits.delta_e = deg2rad([P.servo.elevator.min_deflection_deg, ...
    P.servo.elevator.max_deflection_deg]);
P.limits.delta_r = deg2rad([P.servo.rudder.min_deflection_deg, ...
    P.servo.rudder.max_deflection_deg]);
servoChannels = servo_channels(P);
P.actuator.pwm_min = cellfun(@(s) s.min_pwm,servoChannels)';
P.actuator.pwm_trim = cellfun(@(s) s.neutral_pwm,servoChannels)';
P.actuator.pwm_max = cellfun(@(s) s.max_pwm,servoChannels)';
P.actuator.pwm_to_positive_surface_sign = [1; ...
    P.servo.aileron_left.direction;P.servo.aileron_right.direction; ...
    P.servo.elevator.direction;P.servo.rudder.direction];
P.actuator.servo_reversed = [0;0;0;0;1];
P.actuator.time_constant = cellfun(@(s) s.time_constant_s,servoChannels)';
P.actuator.delay_s = cellfun(@(s) s.delay_s,servoChannels)';
P.actuator.deadband_pwm = cellfun(@(s) s.deadband_pwm,servoChannels)';
P.actuator.rate_positive = [inf;deg2rad(cellfun( ...
    @(s) s.rate_positive_deg_s,servoChannels(2:5))')];
P.actuator.rate_negative = [inf;deg2rad(cellfun( ...
    @(s) s.rate_negative_deg_s,servoChannels(2:5))')];
P.actuator.rate_limit = max(P.actuator.rate_positive,P.actuator.rate_negative);
P.actuator.sample_time_s = 0.005;
P.actuator.backlash = zeros(5,1);              % V5.4.1 nominal: disabled
P.actuator.pwm_quantization_us = 1;

% Electric propulsion model from the supplied X2820 thrust-stand data.
% Clean steady plateaus cover about 7.7, 11.45 and 13.0 m/s with
% 22/23.5/25 V supply settings. Programmable-supply collapse samples are
% excluded. See README_推进测力台多空速数据接入说明.md for the treatment of
% the systematic 11.45 m/s force-offset inconsistency.
P.prop = load_propulsion_bench_data(P.paths.prop_data);
P.prop.mode = "bench_multispeed";               % bench_multispeed | analytic | table
% IMPORTANT: this is LOADED terminal voltage, not nominal pack voltage.
% Set it from the representative cruise BAT.Volt / power-module log value.
P.prop.bus_voltage = 24.34;                    % V, 0816 AUTO median BAT.Volt
P.prop.efficiency_scale = 1.0;                 % robust-case multiplier

% First-order battery model: Vbus = Voc(SOC,T) - I*R(T). Capacity and
% resistance are deliberately centralized so flight-log identification can
% replace these initial estimates without touching the propulsion code.
P.battery.enable = true;
P.battery.series_cells = 6;
P.battery.capacity_Ah = 80.0;                  % rated; 1C measured 80.118 Ah
P.battery.measured_capacity_1C_Ah = 80.1182;
P.battery.measured_capacity_3C_Ah = 78.9261;
P.battery.initial_soc = 0.99;
P.battery.initial_loaded_voltage_V = P.prop.bus_voltage;
P.battery.cell_dcir_ohm = 0.00061;             % post-test cell result
P.battery.cell_only_pack_resistance_ohm = 6*P.battery.cell_dcir_ohm;
P.battery.internal_resistance_ohm = 0.0209;    % installed-system median BAT.Res, 0816
P.battery.temperature_C = 45;                  % representative installed log temperature
P.battery.reference_temperature_C = 25;
P.battery.resistance_temp_coefficient = 0.012; % fractional increase per degC below ref
P.battery.soc_grid = [0,0.02,0.05,0.10,0.25,0.50,0.75,0.90,0.95,0.98,1.00];
P.battery.ocv_per_cell_V = [2.50,2.605,2.725,2.861,3.126,3.502, ...
    3.843,3.992,4.036,4.078,4.218];
P.battery.min_voltage_V = 19.8;                % installed load LVD, 3.30 V/cell
P.battery.max_voltage_V = 25.5;

% Initial condition used by both the native SITL chain and plant validation.
P.init.Va = double(cruiseSpeed);
P.init.altitude = 120;
P.init.heading = 0;
P.init.position_ned = [0; 0; -P.init.altitude];
% V5.4.1 PLANT-ONLY physical control-authority configuration. These values
% define the engineering measurement window, not ArduPilot firmware rules.
P.control_authority.test_mode = "PLANT_ONLY_CONTROL_AUTHORITY_TEST";
P.control_authority.test_airspeeds_mps = [10,13,16];
P.control_authority.roll_min_deg = -45;
P.control_authority.roll_max_deg = 45;
P.control_authority.pitch_min_deg = -15;
P.control_authority.pitch_max_deg = 15;
P.control_authority.alpha_min_deg = -5;
P.control_authority.alpha_max_deg = 12;
P.control_authority.beta_max_deg = 15;
P.control_authority.yaw_roll_limit_deg = 30;
P.control_authority.airspeed_min_mps = 8;
P.control_authority.case_stop_time_s = struct("roll",5,"pitch",5,"yaw",3);
P.control_authority.feasibility_thresholds = struct( ...
    "comfortable_max",0.70,"matched_max",0.90,"boundary_max",1.00);
P.control_authority.repeatability_max_cv = 0.15;

% Controller scheduler. This is a model setting, not a Mission Planner gain.
P.ctrl.Ts = 0.02;                               % s, 50 Hz

% ArduPlane fixed-wing attitude parameters. Field names intentionally match
% Mission Planner exactly. The rate loops use rad/s internally, the same
% airspeed-squared scaling, PID+FF meaning, IMAX convention, and nominal
% +/-45 degree servo-output convention as ArduPlane AP_FW_Controller.
P.ap.RLL2SRV_TCONST = 0.50;                    % 0816 0.70->0.85 worsened lag; restore 0.50 baseline
P.ap.RLL2SRV_RMAX = 0;                         % 0816 value; 0 disables
P.ap.RLL_RATE_P = 0.08;                        % 0816 baseline
P.ap.RLL_RATE_I = 0.15;                        % 0816 baseline
P.ap.RLL_RATE_D = 0.001;                       % 0816 was 0; current MP-supported seed floor
P.ap.RLL_RATE_FF = 0.345;
P.ap.RLL_RATE_IMAX = 0.666;                    % normalized AC_PID integrator output
P.ap.RLL_RATE_FLTT = 3.0;                      % Hz, target filter
P.ap.RLL_RATE_FLTE = 0.0;                      % Hz, 0 disables error filter
P.ap.RLL_RATE_FLTD = 12.0;                     % Hz, derivative filter

P.ap.PTCH2SRV_TCONST = 0.50;                   % s
P.ap.PTCH2SRV_RMAX_UP = 60;                    % deg/s; 0 disables
P.ap.PTCH2SRV_RMAX_DN = 60;                    % deg/s; 0 disables
P.ap.PTCH2SRV_RLL = 1.0;                       % coordinated-turn pitch feedforward
P.ap.PTCH_RATE_P = 0.08;                       % 0816 was 0.04; current MP-supported seed floor
P.ap.PTCH_RATE_I = 0.15;                       % 0816 baseline
P.ap.PTCH_RATE_D = 0.001;                      % 0816 was 0; current MP-supported seed floor
P.ap.PTCH_RATE_FF = 0.345;
P.ap.PTCH_RATE_IMAX = 0.666;
P.ap.PTCH_RATE_FLTT = 3.0;                     % Hz
P.ap.PTCH_RATE_FLTE = 0.0;                     % Hz
P.ap.PTCH_RATE_FLTD = 12.0;                    % Hz

% ArduPlane coordinated-yaw controller. This package tunes the normal
% fixed-wing YAW2SRV path, not the aerobatic YAW_RATE controller.
P.ap.KFF_RDDRMIX = 0.60;                       % 0816 baseline; optimizer must justify changes
P.ap.YAW2SRV_DAMP = 0.00;                      % 0816 baseline
P.ap.YAW2SRV_INT = 0.00;                       % 0816 baseline
P.ap.YAW2SRV_RLL = 1.00;                       % coordinated-turn yaw-rate multiplier
P.ap.YAW2SRV_SLIP = 0.00;                      % 0816 baseline
P.ap.YAW2SRV_IMAX = 1500;                      % cdeg, +/-4500 is full servo travel

% ArduPlane TECS energy-controller baseline parameters retained for SITL.
P.ap.TECS_TIME_CONST = 5.0;                    % s
P.ap.TECS_THR_DAMP = 0.50;                     % dimensionless
P.ap.TECS_INTEG_GAIN = 0.30;                   % 0816 baseline
P.ap.TECS_PTCH_DAMP = 0.30;                    % dimensionless
P.ap.TECS_SPDWEIGHT = 1.00;                    % 0=height, 2=airspeed priority
P.ap.TECS_RLL2THR = 8.0;                       % 0816 baseline; 10 retained in search range
P.ap.TECS_CLMB_MAX = 3.0;                      % m/s
P.ap.TECS_SINK_MAX = 3.0;                      % m/s
P.ap.TECS_SINK_MIN = 2.0;                      % m/s, 0816 baseline
P.ap.TECS_PITCH_MAX = 15.0;                    % deg
P.ap.TECS_PITCH_MIN = 0.0;                     % deg, 0816 baseline; not in default export
P.ap.TECS_VERT_ACC = 7.0;                      % m/s^2

P.ap.SCALING_SPEED = cruiseSpeed;
P.ap.AIRSPEED_MIN = 8.0;                       % UAV_A baseline; new aircraft MUST override
P.ap.AIRSPEED_CRUISE = cruiseSpeed;

if upper(string(aircraftId)) ~= "UAV_A"
    % Apply all explicitly supplied aircraft-specific actuator, battery,
    % propulsion and ArduPlane baseline values, then validate no critical
    % placeholder remains.  This is the anti-data-mixing safety barrier.
    P = apply_aircraft_definition(P,Aaircraft);
    P.ap.SCALING_SPEED = cruiseSpeed;
    P.ap.AIRSPEED_CRUISE = cruiseSpeed;
end

% V5.4.1 control-oriented sensor chain. Individual sensor parameters retain
% their source classification in P.sensor.<sensor>.data_source.
P.sensor = load_sensor_configuration();
P.fidelity.actuator = "ENGINEERING";
P.fidelity.sensor = "ENGINEERING";

P.sim.stop_time = 55;
P.sim.max_step = 0.01;
P.sim.solver = "ode23t";
P.sim.random_seed = 42;

% Straight-and-level trim using the selected aerodynamic representation.
if exist("atmosisa", "file") == 2
    [~, ~, ~, rhoTrim] = atmosisa(P.init.altitude);
else
    rhoTrim = 1.2107;
end
qbar = 0.5 * rhoTrim * P.init.Va^2;
CLRequired = P.mass * P.g / (qbar * P.geometry.area);
[P.trim.alpha, P.trim.delta_e, P.trim.CL, P.trim.CD] = ...
    solveAerodynamicTrim(P, CLRequired);
requiredThrust = qbar * P.geometry.area * P.trim.CD;
P.trim.throttle = solvePropulsionTrim(P, requiredThrust, P.init.Va, rhoTrim);
[~, P.trim.propulsion_power_W] = uav_propulsion_model(P, P.trim.throttle, ...
    P.init.Va, rhoTrim);
P.trim.required_thrust_N = requiredThrust;
P.trim.actuator = [P.trim.throttle; 0; 0; P.trim.delta_e; 0];
P.init.velocity_body = [P.init.Va*cos(P.trim.alpha); 0; ...
    P.init.Va*sin(P.trim.alpha)];
P.init.euler = [0; P.trim.alpha; P.init.heading];
P.init.body_rates = [0; 0; 0];

% Parameter provenance used by the migration guide and validation report.
P.source.mass = "handover sheet / measured";
P.source.surface_limits = "handover sheet";
P.source.inertia = "confirmed converted body-axis inertia about CG; unchanged by v4.1";
P.source.geometry = "XFLR5 primary configuration";
P.source.aerodynamics = "XFLR5 supplied polar + stability/control derivative package";
P.source.propulsion = "X2820 thrust-stand data at 12.7-13.3 m/s; PSU-collapse samples removed; off-speed/high-power portions are explicit extrapolation";
P.source.cg = "XFLR5 screenshot: [0.1099,0,0.0142] m; explicit XFLR5-to-body transform";
P.source.actuators = "1100--1900 us and measured PWM/surface map; backlash disabled for v4.2";
P.source.sensors = "PLACEHOLDER: generic estimator lag/noise";
P.source.battery = "90150267NSH4 80 Ah 1C/3C curves + 0816 installed BAT.Res/BAT.Volt";
P.source.flight_reference = "0816 00000046.BIN analysis and before-flight Full Parameter List";

% Portable record of the flight evidence used to define the starting point
% and safety envelope. These are validation targets, not identified plant
% derivatives, so the XFLR5 control derivatives are not silently rescaled.
P.flight_reference.log = "00000046.BIN";
P.flight_reference.firmware = "ArduPlane 4.6.3";
P.flight_reference.low_speed_mps = 13.46;
P.flight_reference.high_speed_mps = 18.38;
P.flight_reference.low_speed_roll_rate_ratio = 0.32;
P.flight_reference.high_speed_roll_rate_ratio = 0.52;
P.flight_reference.low_speed_sideslip_rms_deg = 9.98;
P.flight_reference.high_speed_sideslip_rms_deg = 3.77;
P.flight_reference.roll_tracking_lag_s = [2.5,3.3];
P.flight_reference.crash_roll_deg = 79.52;
P.flight_reference.crash_pitch_deg = -37.16;
P.flight_reference.crash_airspeed_mps = 39.88;
P.flight_reference.mechanical_trim_target_pwm = 1500;

if upper(string(aircraftId)) ~= "UAV_A"
    % Remove UAV_A provenance from a new aircraft.  New-aircraft flight-log
    % evidence may be added later through A.overrides.flight_reference.
    P.source.mass = "aircraft/<ID>/aircraft_definition.m";
    P.source.surface_limits = "aircraft/<ID>/aircraft_definition.m";
    P.source.inertia = "aircraft/<ID>/aircraft_definition.m";
    P.source.geometry = "aircraft/<ID>/aircraft_definition.m + input/aero_data";
    P.source.aerodynamics = "aircraft/<ID>/input/aero_data";
    P.source.propulsion = "aircraft/<ID>/input/prop_data";
    P.source.cg = "aircraft/<ID>/aircraft_definition.m";
    P.source.actuators = "aircraft/<ID>/aircraft_definition.m";
    P.source.battery = "aircraft/<ID>/aircraft_definition.m + input/battery_data";
    P.source.flight_reference = "aircraft/<ID>/input/flight_data";
    P.flight_reference = struct;
    P.flight_reference.log = "not supplied";
    P.flight_reference.firmware = P.ardupilot.target_version;
    if isfield(Aaircraft,"overrides") && isfield(Aaircraft.overrides,"flight_reference")
        P.flight_reference = merge_struct_recursive(P.flight_reference, ...
            Aaircraft.overrides.flight_reference);
    end
end

% V5.4.1 identity: hashes aircraft-defining parameters plus this workspace's
% input data.  Computer paths and output files are excluded so the same UAV
% keeps the same fingerprint after moving to another PC.
[P.meta.aircraft_fingerprint,P.meta.aircraft_fingerprint_manifest] = ...
    aircraft_fingerprint(P);
end

function throttleTrim = solvePropulsionTrim(P, thrustRequired, Va, rho)
% Solve throttle required to balance aerodynamic drag with the selected
% propulsion model.  This keeps trim consistent with the same model used in
% the Simulink S-function.
grid = linspace(P.limits.throttle(1), P.limits.throttle(2), 501);
thrustGrid = zeros(size(grid));
for k = 1:numel(grid)
    thrustGrid(k) = uav_propulsion_model(P, grid(k), Va, rho);
end

% Guard small numerical non-monotonicity introduced by interpolation or
% future table edits.
thrustGrid = cummax(thrustGrid);
[thrustUnique, ia] = unique(thrustGrid, "stable");
gridUnique = grid(ia);
if thrustRequired <= thrustUnique(1)
    throttleTrim = gridUnique(1);
elseif thrustRequired >= thrustUnique(end)
    throttleTrim = gridUnique(end);
else
    throttleTrim = interp1(thrustUnique, gridUnique, thrustRequired, "linear");
end
end

function [alphaTrim, deltaETrim, CLTrim, CDTrim] = solveAerodynamicTrim(P, CLRequired)
% Solve lift and pitch-moment equilibrium at P.init.Va.
alphaLo = max(-P.aero.alpha_limit, P.aero.table_alpha_min);
alphaHi = min( P.aero.alpha_limit, P.aero.table_alpha_max);
residual = @(a) trimLiftResidual(a, P, CLRequired);

scan = linspace(alphaLo, alphaHi, 200);
y = arrayfun(residual, scan);
idx = find(y(1:end-1).*y(2:end) <= 0, 1, "first");
if isempty(idx)
    [~, best] = min(abs(y));
    alphaTrim = scan(best);
else
    alphaTrim = fzero(residual, [scan(idx), scan(idx+1)]);
end
[CLBase, CDBase, CmBase] = staticAeroCoefficients(P, alphaTrim, P.init.Va);
deltaETrim = -CmBase / P.aero.Cm_de;
CLTrim = CLBase + P.aero.CL_de*deltaETrim;
CDTrim = CDBase + P.aero.CD_de*deltaETrim + ...
    P.aero.CD_ctrl*deltaETrim^2;
end

function r = trimLiftResidual(alpha, P, CLRequired)
[CLBase, ~, CmBase] = staticAeroCoefficients(P, alpha, P.init.Va);
deltaE = -CmBase / P.aero.Cm_de;
r = CLBase + P.aero.CL_de*deltaE - CLRequired;
end

function [CL, CD, Cm] = staticAeroCoefficients(P, alpha, Va)
if strcmpi(P.aero.mode, "table")
    a = min(max(alpha, P.aero.table_alpha_min), P.aero.table_alpha_max);
    v = min(max(Va, P.aero.table_speed_min), P.aero.table_speed_max);
    nV = numel(P.aero.speed_grid);
    clv = zeros(nV,1); cdv = zeros(nV,1); cmv = zeros(nV,1);
    for k = 1:nV
        clv(k) = interp1(P.aero.alpha_grid, P.aero.CL_table(k,:), a, "linear");
        cdv(k) = interp1(P.aero.alpha_grid, P.aero.CD_table(k,:), a, "linear");
        cmv(k) = interp1(P.aero.alpha_grid, P.aero.Cm_table(k,:), a, "linear");
    end
    if nV == 1
        CL = clv(1); CD = cdv(1); Cm = cmv(1);
    else
        CL = interp1(P.aero.speed_grid, clv, v, "linear");
        CD = interp1(P.aero.speed_grid, cdv, v, "linear");
        Cm = interp1(P.aero.speed_grid, cmv, v, "linear");
    end
else
    da = alpha - P.aero.reference_alpha;
    CL = P.aero.CL_ref + P.aero.CL_alpha*da;
    CD = P.aero.CD_ref + P.aero.CD_alpha*da;
    Cm = P.aero.Cm_ref + P.aero.Cm_alpha*da;
end
end
