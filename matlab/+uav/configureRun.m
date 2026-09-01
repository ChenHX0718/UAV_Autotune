function [P,selectedParameters] = configureRun(cfg,runDir,options)
%CONFIGURERUN Build a V5.4.1 run without changing the plant model.
arguments
    cfg struct
    runDir (1,1) string
    options.InitialAirspeed (1,1) double = NaN
    options.ModelPerturbation struct = struct
    options.ActuatorFidelity (1,1) string = ""
    options.SensorFidelity (1,1) string = ""
    options.RandomSeed (1,1) double = NaN
end
root = uav.projectRoot();
airspeed = double(cfg.aircraft.nominal_airspeed_mps);
if isfinite(options.InitialAirspeed)
    if options.InitialAirspeed <= 0
        error("UAVV541:InitialAirspeed","Initial airspeed must be positive.");
    end
    airspeed = options.InitialAirspeed;
end
P = uav_config(string(cfg.aircraft.aircraft_id),airspeed);
baselineFile = fullfile(root,"config","autotune","baseline.param");
[P,selectedParameters] = uav.applyParamFile(P,baselineFile);

P.meta.model_version = "5.4.1";
P.controller.backend = "ardupilot_sitl";
P.controller.sitl.host = "0.0.0.0";
P.controller.sitl.servo_port = double(cfg.project.network.json_udp_port);
P.controller.sitl.mavlink_port = double(cfg.project.network.mission_planner_udp_port);
P.controller.sitl.frame_rate_hz = double(cfg.project.timing.sitl_rate_hz);
P.controller.sitl.receive_timeout_s = double(cfg.project.network.receive_timeout_s);
P.controller.sitl.home = [double(cfg.project.home.latitude_deg), ...
    double(cfg.project.home.longitude_deg),double(cfg.project.home.altitude_m), ...
    double(cfg.project.home.yaw_deg)];
P.controller.sitl.channels = struct( ...
    "aileron_left",double(cfg.aircraft.servo_output_channels.aileron_left), ...
    "elevator",double(cfg.aircraft.servo_output_channels.elevator), ...
    "throttle",double(cfg.aircraft.servo_output_channels.throttle), ...
    "rudder",double(cfg.aircraft.servo_output_channels.rudder), ...
    "aileron_right",double(cfg.aircraft.servo_output_channels.aileron_right));
P.controller.sitl.auto_launch = false;
P.controller.sitl.executable = "";

P.fidelity.actuator = upper(string(cfg.simulation.actuator_fidelity));
P.fidelity.sensor = upper(string(cfg.simulation.sensor_fidelity));
if strlength(options.ActuatorFidelity) > 0
    P.fidelity.actuator = upper(options.ActuatorFidelity);
end
if strlength(options.SensorFidelity) > 0
    P.fidelity.sensor = upper(options.SensorFidelity);
end
if ~ismember(P.fidelity.actuator,["IDEAL","ENGINEERING"])
    error("UAVV541:ActuatorFidelity","Actuator fidelity must be IDEAL or ENGINEERING.");
end
if ~ismember(P.fidelity.sensor,["IDEAL","ENGINEERING"])
    error("UAVV541:SensorFidelity","Sensor fidelity must be IDEAL or ENGINEERING.");
end
P.sensor.enable_noise = P.fidelity.sensor ~= "IDEAL";
randomSeed = double(cfg.project.native_autotune.deterministic_seed);
if isfinite(options.RandomSeed), randomSeed = options.RandomSeed; end
P.sensor.random_seed = randomSeed;
P.sim.random_seed = randomSeed;
P.sim.stop_time = double(cfg.scenario.stop_time_s);
P.init.Va = airspeed;
P.ap.SCALING_SPEED = airspeed;
P.ap.AIRSPEED_CRUISE = airspeed;

P = applyPerturbation(P,options.ModelPerturbation);

P.interface = struct;
P.interface.run_dir = runDir;
P.interface.adapter_log_file = fullfile(runDir,"adapter.log");
P.interface.sitl_console_log_file = fullfile(runDir,"sitl_console.log");
P.interface.packet_trace_file = fullfile(runDir,"packet_trace.csv");
P.interface.feedback_trace_file = fullfile(runDir,"feedback_trace.csv");
P.interface.adapter_summary_file = fullfile(runDir,"adapter_summary.json");
P.interface.speedup = double(cfg.simulation.speedup);
P.interface.actuator_fidelity = lower(P.fidelity.actuator);
if isfield(options.ModelPerturbation,"servo_tau_scale")
    P.interface.actuator_fidelity = "first_order";
end
P.interface.sensor_fidelity = lower(P.fidelity.sensor);
P.interface.reset_strategy = "full_sitl_restart_and_model_state_reinitialization";
P.interface.scenario = cfg.scenario;
P.interface.command_mapping = struct( ...
    "command_semantics",string(cfg.scenario.command_semantics), ...
    "roll_limit_deg",double(cfg.aircraft.roll_limit_deg), ...
    "pitch_limit_max_deg",double(cfg.aircraft.pitch_limit_max_deg), ...
    "pitch_limit_min_deg",double(cfg.aircraft.pitch_limit_min_deg), ...
    "pitch_command_sign",double(cfg.aircraft.rc.pitch_command_sign), ...
    "stab_pitch_down_deg",double(cfg.aircraft.fbwa_pitch_compensation.stab_pitch_down_deg), ...
    "throttle_cruise_percent",double(cfg.aircraft.fbwa_pitch_compensation.throttle_cruise_percent), ...
    "rc",cfg.aircraft.rc);
P.session = struct("initial_airspeed_mps",airspeed, ...
    "model_perturbation",options.ModelPerturbation, ...
    "random_seed",randomSeed, ...
    "online_safety_enabled",true,"online_safety_grace_s",2, ...
    "online_safety_handover_s",2, ...
    "safety_abort_file",fullfile(runDir,"safety_abort.json"), ...
    "official_finished_file",fullfile(runDir,"official_finished.json"), ...
    "mode_ready_file",fullfile(runDir,"mode_ready.json"), ...
    "mode_dropout_file",fullfile(runDir,"mode_dropout.json"), ...
    "mode_dropout_handover_s",double(cfg.project.mode_gate.dropout_handover_s), ...
    "safety_limits",struct("roll_deg",45,"pitch_deg",25, ...
        "airspeed_min_mps",8,"aoa_deg",15,"sideslip_deg",20, ...
        "altitude_min_m",50,"angular_rate_deg_s",300));
end

function P = applyPerturbation(P,perturbation)
if isempty(fieldnames(perturbation)), return; end
if isfield(perturbation,"mass_scale"), P.mass = P.mass*perturbation.mass_scale; end
if isfield(perturbation,"inertia_scale"), P.inertia = P.inertia*perturbation.inertia_scale; end
if isfield(perturbation,"servo_tau_scale")
    nominalTau = [0.12;0.08;0.08;0.10;0.10];
    P.actuator.time_constant = nominalTau*perturbation.servo_tau_scale;
end
if isfield(perturbation,"surface_effectiveness_scale")
    fields = ["Cl_da","Cn_da","Cm_de","Cl_dr","Cn_dr"];
    for field = fields
        if isfield(P.aero,field)
            P.aero.(field) = P.aero.(field)*perturbation.surface_effectiveness_scale;
        end
    end
end
end
