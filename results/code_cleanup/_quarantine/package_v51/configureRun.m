function [P,selectedParameters] = configureRun(cfg,runDir,backend,windowsExecutable)
%CONFIGURERUN Build one non-global parameter snapshot for SimulationInput.
arguments
    cfg struct
    runDir (1,1) string
    backend (1,1) string
    windowsExecutable (1,1) string = ""
end
root = v51.projectRoot();
P = uav_config(string(cfg.aircraft.aircraft_id), ...
    double(cfg.aircraft.nominal_airspeed_mps));
rankFile = fullfile(root,"config","ardupilot","Rank1_Candidate_C.param");
[P,selectedParameters] = v51.applyParamFile(P,rankFile);

P.meta.model_version = "5.1-WSL-ArduPilot-SITL";
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
P.controller.sitl.auto_launch = backend == "windows_compat";
P.controller.sitl.executable = windowsExecutable;
if P.controller.sitl.auto_launch
    P.controller.sitl.host = "127.0.0.1";
end

P.sensor.enable_noise = string(cfg.simulation.sensor_fidelity) ~= "ideal";
P.actuator.time_constant = P.ctrl.Ts*ones(5,1);
P.actuator.rate_limit = inf(5,1);
P.actuator.backlash = zeros(5,1);
P.autotune.test_mode = lower(string(cfg.scenario.axis));
P.sim.stop_time = double(cfg.scenario.stop_time_s);

P.v51 = struct;
P.v51.run_dir = runDir;
P.v51.adapter_log_file = fullfile(runDir,"adapter.log");
P.v51.sitl_console_log_file = fullfile(runDir,"sitl_console.log");
P.v51.packet_trace_file = fullfile(runDir,"packet_trace.csv");
P.v51.adapter_summary_file = fullfile(runDir,"adapter_summary.json");
P.v51.speedup = double(cfg.simulation.speedup);
P.v51.scenario = cfg.scenario;
P.v51.command_mapping = struct( ...
    "command_semantics",string(cfg.scenario.command_semantics), ...
    "roll_limit_deg",double(cfg.aircraft.roll_limit_deg), ...
    "pitch_limit_max_deg",double(cfg.aircraft.pitch_limit_max_deg), ...
    "pitch_limit_min_deg",double(cfg.aircraft.pitch_limit_min_deg), ...
    "pitch_command_sign",double(cfg.aircraft.rc.pitch_command_sign), ...
    "stab_pitch_down_deg",double( ...
        cfg.aircraft.fbwa_pitch_compensation.stab_pitch_down_deg), ...
    "throttle_cruise_percent",double( ...
        cfg.aircraft.fbwa_pitch_compensation.throttle_cruise_percent), ...
    "rc",cfg.aircraft.rc);
end
