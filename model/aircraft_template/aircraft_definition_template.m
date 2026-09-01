%% Aircraft-specific definition template
% This script is executed only for the aircraft workspace that contains it.
% IMPORTANT: leave config_complete=false until EVERY field has been checked.
% No UAV_A results or data are copied into a new aircraft workspace.
A = struct;
A.config_complete = false;
A.notes = "Replace all PLACEHOLDER/NaN values with data for this aircraft.";

% ---------- Required rigid-body and geometry data ----------
A.mass = NaN;                          % kg
A.inertia = nan(3,3);                  % kg*m^2, body axes about CG
A.geometry.span = NaN;                 % m
A.geometry.area = NaN;                 % m^2
A.geometry.chord = NaN;                % m
A.geometry.xflr5_to_body = eye(3);     % edit if XFLR5 axes differ
A.geometry.cg_xflr5 = [NaN;NaN;NaN];  % m, XFLR5 datum

% ---------- Required flight-speed data ----------
A.flight.cruise_speed = NaN;           % nominal cruise speed, m/s
A.flight.stall_speed = NaN;            % theoretical/known stall reference, m/s

% ---------- Required actuator limits / PWM calibration ----------
A.limits.throttle = [0,1];
A.limits.delta_LT = deg2rad([NaN,NaN]);
A.limits.delta_RT = deg2rad([NaN,NaN]);
A.limits.delta_e  = deg2rad([NaN,NaN]);
A.limits.delta_r  = deg2rad([NaN,NaN]);
A.actuator.time_constant = [NaN;NaN;NaN;NaN;NaN];
A.actuator.delay_s = [NaN;NaN;NaN;NaN;NaN];
A.actuator.deadband_pwm = [NaN;NaN;NaN;NaN;NaN];
A.actuator.rate_positive = [NaN;NaN;NaN;NaN;NaN];
A.actuator.rate_negative = [NaN;NaN;NaN;NaN;NaN];
A.actuator.rate_limit = [NaN;NaN;NaN;NaN;NaN];
A.actuator.pwm_min  = [NaN;NaN;NaN;NaN;NaN];
A.actuator.pwm_trim = [NaN;NaN;NaN;NaN;NaN];
A.actuator.pwm_max  = [NaN;NaN;NaN;NaN;NaN];
A.actuator.pwm_to_positive_surface_sign = [NaN;NaN;NaN;NaN;NaN];
A.actuator.servo_reversed = [NaN;NaN;NaN;NaN;NaN];
A.actuator.sample_time_s = NaN;
A.actuator.backlash = zeros(5,1);
A.actuator.pwm_quantization_us = 1;

% ---------- Propulsion operating values ----------
% Actual thrust/propeller data belong in input/prop_data and are hashed.
A.prop.bus_voltage = NaN;              % representative loaded cruise voltage, V
A.prop.efficiency_scale = 1.0;

% ---------- Battery model ----------
A.battery.enable = true;
A.battery.series_cells = NaN;
A.battery.capacity_Ah = NaN;
A.battery.measured_capacity_1C_Ah = NaN;
A.battery.measured_capacity_3C_Ah = NaN;
A.battery.initial_soc = NaN;
A.battery.initial_loaded_voltage_V = NaN;
A.battery.cell_dcir_ohm = NaN;
A.battery.cell_only_pack_resistance_ohm = NaN;
A.battery.internal_resistance_ohm = NaN;
A.battery.temperature_C = NaN;
A.battery.reference_temperature_C = NaN;
A.battery.resistance_temp_coefficient = NaN;
A.battery.soc_grid = [];
A.battery.ocv_per_cell_V = [];
A.battery.min_voltage_V = NaN;
A.battery.max_voltage_V = NaN;

% ---------- Target ArduPlane / Mission Planner ----------
A.ardupilot.target_version = "";       % e.g. "ArduPlane 4.7.0"
A.flight_parameter_file = "";          % filename stored in input/flight_data

% ---------- REQUIRED baseline ArduPlane parameters ----------
% Copy actual values from THIS aircraft's Full Parameter List.
A.ap = struct;
A.ap.RLL2SRV_TCONST = NaN;
A.ap.RLL2SRV_RMAX = NaN;
A.ap.RLL_RATE_P = NaN;
A.ap.RLL_RATE_I = NaN;
A.ap.RLL_RATE_D = NaN;
A.ap.RLL_RATE_FF = NaN;
A.ap.RLL_RATE_IMAX = NaN;
A.ap.RLL_RATE_FLTT = NaN;
A.ap.RLL_RATE_FLTE = NaN;
A.ap.RLL_RATE_FLTD = NaN;
A.ap.PTCH2SRV_TCONST = NaN;
A.ap.PTCH2SRV_RMAX_UP = NaN;
A.ap.PTCH2SRV_RMAX_DN = NaN;
A.ap.PTCH2SRV_RLL = NaN;
A.ap.PTCH_RATE_P = NaN;
A.ap.PTCH_RATE_I = NaN;
A.ap.PTCH_RATE_D = NaN;
A.ap.PTCH_RATE_FF = NaN;
A.ap.PTCH_RATE_IMAX = NaN;
A.ap.PTCH_RATE_FLTT = NaN;
A.ap.PTCH_RATE_FLTE = NaN;
A.ap.PTCH_RATE_FLTD = NaN;
A.ap.KFF_RDDRMIX = NaN;
A.ap.YAW2SRV_DAMP = NaN;
A.ap.YAW2SRV_INT = NaN;
A.ap.YAW2SRV_RLL = NaN;
A.ap.YAW2SRV_SLIP = NaN;
A.ap.YAW2SRV_IMAX = NaN;
A.ap.TECS_TIME_CONST = NaN;
A.ap.TECS_THR_DAMP = NaN;
A.ap.TECS_INTEG_GAIN = NaN;
A.ap.TECS_PTCH_DAMP = NaN;
A.ap.TECS_SPDWEIGHT = NaN;
A.ap.TECS_RLL2THR = NaN;
A.ap.TECS_CLMB_MAX = NaN;
A.ap.TECS_SINK_MAX = NaN;
A.ap.TECS_SINK_MIN = NaN;
A.ap.TECS_PITCH_MAX = NaN;
A.ap.TECS_PITCH_MIN = NaN;
A.ap.TECS_VERT_ACC = NaN;
A.ap.AIRSPEED_MIN = NaN;
% SCALING_SPEED and AIRSPEED_CRUISE are derived from cruise_speed.

% Optional nested overrides for generic model settings.
A.overrides = struct;
