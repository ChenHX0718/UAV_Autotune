classdef ArduPilotJSONBridge < handle
    %ARDUPILOTJSONBRIDGE State-aware ArduPlane JSON physics adapter.
    % Simulink is the only truth model. ArduPlane supplies controller logic.

    properties (SetAccess=private)
        LastFrameCount uint32 = uint32(0)
        LastPWM double = 1500*ones(1,16)
        LastProtocolCommand double = [1500;1500;1500;1500;1500;0;0;0;0]
        RxPackets double = 0
        TxPackets double = 0
        InvalidPackets double = 0
        DroppedPackets double = 0
        DuplicatePackets double = 0
        LastRttMs double = NaN
    end

    properties (Access=private)
        P
        Socket
        Process
        SenderAddress string = ""
        SenderPort double = NaN
        LastTime double = NaN
        PreviousBodyVelocity double = zeros(3,1)
        StateInitialized logical = false
        RuntimeFolder string = ""
        AdapterLogFile string = ""
        SitlConsoleLogFile string = ""
        PacketTraceFile string = ""
        FeedbackTraceFile string = ""
        SummaryFile string = ""
        LastFrameRate double = 0
        LastSentTimestamp double = 0
        LastWallReceive double = NaN
        LastRc double = [1500,1500,1000,1500,1500,1000,1900,1000]
        LastRcNormalized double = [0,0,0,0]
        LastExternalRollDeg double = 0
        LastExternalPitchDeg double = 0
        LastStateFrame struct = struct()
        AdapterState string = "STARTING"
        SafetyAbortTime double = NaN
        ModeGateAbortTime double = NaN
        OfficialFinishedObserved logical = false
    end

    methods
        function obj = ArduPilotJSONBridge(P)
            obj.P = P;
            obj.RuntimeFolder = string(P.interface.run_dir);
            obj.AdapterLogFile = string(P.interface.adapter_log_file);
            obj.SitlConsoleLogFile = string(P.interface.sitl_console_log_file);
            obj.PacketTraceFile = string(P.interface.packet_trace_file);
            obj.FeedbackTraceFile = string(P.interface.feedback_trace_file);
            obj.SummaryFile = string(P.interface.adapter_summary_file);
            if exist("udpport","file") ~= 2
                error("UAVV541:MissingUdpport", ...
                    "Instrument Control Toolbox udpport is required.");
            end
            if ~isfolder(obj.RuntimeFolder), mkdir(obj.RuntimeFolder); end
            obj.initializeLogs();
            executable = string(P.controller.sitl.executable);
            if P.controller.sitl.auto_launch && ...
                    (strlength(executable) == 0 || ~isfile(executable))
                error("UAVV541:ArduPlaneSITLNotFound", ...
                    "Windows compatibility SITL not found: %s",executable);
            end
            obj.Socket = udpport("datagram","IPV4", ...
                "LocalHost",char(P.controller.sitl.host), ...
                "LocalPort",P.controller.sitl.servo_port, ...
                "Timeout",P.controller.sitl.receive_timeout_s);
            obj.setState("WAITING_FOR_SITL","UDP listener ready");
            obj.log("UDP_LISTEN",sprintf("local=%s:%d", ...
                P.controller.sitl.host,P.controller.sitl.servo_port));
            defaultsFile = string(P.controller.sitl.defaults_file_override);
            if strlength(defaultsFile) == 0 || ~isfile(defaultsFile)
                error("UAVV541:DefaultsNotFound", ...
                    "V5.2 parameter snapshot not found: %s",defaultsFile);
            end
            if P.controller.sitl.auto_launch
                obj.Process = obj.launchFirmware(executable,defaultsFile);
            end
            obj.receiveServoPacket(true,false);
            obj.LastProtocolCommand = obj.pwmToProtocolCommand(obj.LastPWM);
            obj.setState("CONNECTED","First valid servo frame received");
            obj.log("BIDIRECTIONAL_HANDSHAKE",sprintf( ...
                "sender=%s:%d frame=%u",obj.SenderAddress,obj.SenderPort, ...
                obj.LastFrameCount));
        end

        function [protocolCommand,rcTrace] = step(obj,time,cmd,state)
            if isfinite(obj.LastTime) && abs(time-obj.LastTime) <= 1e-12
                protocolCommand = obj.LastProtocolCommand;
                rcTrace = obj.rcTraceVector();
                return
            end
            cmd = obj.applyModeGate(time,cmd);
            obj.enforceOnlineSafety(time,state);
            frame = obj.makeStateFrame(time,cmd,state);
            obj.LastStateFrame = frame;
            payload = [unicode2native(jsonencode(frame),"UTF-8"),uint8(10)];
            if obj.TxPackets == 0
                % Seed Plane-4.7.0's retained delimiter on the first record.
                % Later records reuse the retained trailing delimiter; adding
                % another leading delimiter would make it parse an empty row.
                payload = [uint8(10),payload];
            end
            roundTripTimer = tic;
            write(obj.Socket,payload,"uint8",obj.SenderAddress,obj.SenderPort);
            obj.TxPackets = obj.TxPackets + 1;
            obj.receiveServoPacket(true,true);
            obj.LastRttMs = 1000*toc(roundTripTimer);
            obj.LastProtocolCommand = obj.pwmToProtocolCommand(obj.LastPWM);
            obj.LastTime = time;
            obj.PreviousBodyVelocity = state(4:6);
            obj.StateInitialized = true;
            if obj.AdapterState == "CONNECTED"
                obj.setState("READY",sprintf( ...
                    "Fresh frame=%u timestamp=%.6f and PWM mapping valid", ...
                    obj.LastFrameCount,obj.LastSentTimestamp));
            end
            if obj.AdapterState ~= "RUNNING"
                obj.setState("RUNNING","Lock-step exchange active");
            end
            obj.appendPacketTrace(time);
            obj.appendFeedbackTrace(time);
            if mod(obj.TxPackets,50) == 0
                obj.log("LOCKSTEP",sprintf( ...
                    "t=%.3f tx=%d rx=%d frame=%u dropped=%d invalid=%d", ...
                    time,obj.TxPackets,obj.RxPackets,obj.LastFrameCount, ...
                    obj.DroppedPackets,obj.InvalidPackets));
            end
            protocolCommand = obj.LastProtocolCommand;
            rcTrace = obj.rcTraceVector();
        end

        function s = status(obj)
            s = struct("rx_packets",obj.RxPackets,"tx_packets",obj.TxPackets, ...
                "invalid_packets",obj.InvalidPackets, ...
                "dropped_packets",obj.DroppedPackets, ...
                "duplicate_packets",obj.DuplicatePackets, ...
                "last_frame_count",double(obj.LastFrameCount), ...
                "last_frame_rate_hz",obj.LastFrameRate, ...
                "last_rtt_ms",obj.LastRttMs, ...
                "actuator_representation","pwm_us", ...
                "bridge_normalizes_actuator",false, ...
                "state",obj.AdapterState, ...
                "sender_address",obj.SenderAddress, ...
                "sender_port",obj.SenderPort);
        end

        function delete(obj)
            obj.setState("STOPPING","Bridge delete requested");
            obj.writeSummary();
            try
                if ~isempty(obj.Socket)
                    configureCallback(obj.Socket,"off");
                    flush(obj.Socket);
                    obj.Socket = [];
                end
            catch
            end
            try
                if ~isempty(obj.Process) && ~obj.Process.HasExited
                    obj.Process.Kill();
                    exited = obj.Process.WaitForExit(5000);
                    if ~exited
                        obj.log("SITL_STOP_TIMEOUT",sprintf("pid=%d",obj.Process.Id));
                    end
                end
            catch
            end
            obj.log("ADAPTER_CLOSED",sprintf( ...
                "tx=%d rx=%d dropped=%d invalid=%d",obj.TxPackets, ...
                obj.RxPackets,obj.DroppedPackets,obj.InvalidPackets));
            obj.AdapterState = "STOPPED";
        end
    end

    methods (Static)
        function [pwm,frameRate,frameCount,valid] = parseServoPacket(bytes)
            bytes = uint8(bytes(:)');
            pwm = [];
            frameRate = 0;
            frameCount = uint32(0);
            valid = false;
            if numel(bytes) < 40, return; end
            magic = typecast(bytes(1:2),"uint16");
            if magic == 18458
                channelCount = 16;
            elseif magic == 29569
                channelCount = 32;
            else
                return
            end
            requiredLength = 8 + 2*channelCount;
            if numel(bytes) < requiredLength, return; end
            frameRate = double(typecast(bytes(3:4),"uint16"));
            frameCount = typecast(bytes(5:8),"uint32");
            pwm = double(typecast(bytes(9:requiredLength),"uint16"));
            valid = all(pwm == 0 | (pwm >= 500 & pwm <= 2500));
        end
    end

    methods (Access=private)
        function cmd = applyModeGate(obj,time,cmd)
            if ~isfield(obj.P,"v53"), return; end
            readyFile = string(obj.fieldOr(obj.P.session,"mode_ready_file",""));
            dropoutFile = string(obj.fieldOr(obj.P.session,"mode_dropout_file",""));
            finishedFile = string(obj.fieldOr(obj.P.session,"official_finished_file",""));
            dropout = strlength(dropoutFile) > 0 && isfile(dropoutFile);
            finished = strlength(finishedFile) > 0 && isfile(finishedFile);
            ready = strlength(readyFile) == 0 || isfile(readyFile);
            if ~ready || dropout || finished
                % Keep airspeed/throttle control alive but neutralize the two
                % attitude RC axes until the state-driven mode gate is ready.
                if numel(cmd) >= 2, cmd(2) = 0; end
                if numel(cmd) >= 3, cmd(3) = 0; end
            end
            if finished && ~obj.OfficialFinishedObserved
                obj.log("OFFICIAL_FINISHED_EXCITATION_NEUTRAL",sprintf("t=%.3f",time));
                obj.OfficialFinishedObserved = true;
            end
            if ~dropout, return; end
            if ~isfinite(obj.ModeGateAbortTime)
                obj.ModeGateAbortTime = time;
                obj.log("MODE_GATE_ABORT_REQUESTED",sprintf("t=%.3f",time));
            end
            handover = obj.fieldOr(obj.P.session,"mode_dropout_handover_s",2);
            if time-obj.ModeGateAbortTime >= handover
                error("UAVV541:ModeGateAbort", ...
                    "Mode gate abort handover completed at %.3f s.",time);
            end
        end

        function enforceOnlineSafety(obj,time,state)
            if ~isfield(obj.P,"v53") || ...
                    ~obj.fieldOr(obj.P.session,"online_safety_enabled",false) || ...
                    time < obj.fieldOr(obj.P.session,"online_safety_grace_s",2)
                return
            end
            if isfinite(obj.SafetyAbortTime)
                handover = obj.fieldOr(obj.P.session,"online_safety_handover_s",2);
                if time-obj.SafetyAbortTime >= handover
                    error("UAVV541:OnlineSafetyAbort", ...
                        "Online safety handover window completed at %.3f s.",time);
                end
                return
            end
            limits = obj.P.session.safety_limits;
            values = [abs(rad2deg(state(10))),abs(rad2deg(state(11))), ...
                state(15),abs(rad2deg(state(13))),abs(rad2deg(state(14))), ...
                state(16),max(abs(rad2deg(state(7:9))))];
            thresholds = [limits.roll_deg,limits.pitch_deg, ...
                limits.airspeed_min_mps,limits.aoa_deg, ...
                limits.sideslip_deg,limits.altitude_min_m, ...
                limits.angular_rate_deg_s];
            pass = [values(1)<=thresholds(1),values(2)<=thresholds(2), ...
                values(3)>=thresholds(3),values(4)<=thresholds(4), ...
                values(5)<=thresholds(5),values(6)>=thresholds(6), ...
                values(7)<=thresholds(7)];
            if all(pass), return; end
            names = ["roll","pitch","airspeed","aoa","sideslip", ...
                "altitude","angular_rate"];
            failed = names(~pass);
            evidence = struct("time_s",time,"failure_reason", ...
                "ENVELOPE_VIOLATION","failed_checks",failed, ...
                "observed",values,"thresholds",thresholds, ...
                "handover_window_s",obj.fieldOr( ...
                    obj.P.session,"online_safety_handover_s",2));
            filePath = string(obj.P.session.safety_abort_file);
            fid = fopen(filePath,"w");
            if fid >= 0
                fprintf(fid,"%s",jsonencode(evidence,"PrettyPrint",true));
                fclose(fid);
            end
            obj.SafetyAbortTime = time;
            obj.log("ONLINE_SAFETY_ABORT_REQUESTED",sprintf( ...
                "t=%.3f failed=%s",time,join(failed,",")));
        end

        function initializeLogs(obj)
            fid = fopen(obj.AdapterLogFile,"w");
            if fid < 0, error("UAVV541:AdapterLogOpen","Cannot open adapter log."); end
            fprintf(fid,"V5.2 ArduPlane JSON adapter log\n");
            fclose(fid);
            fid = fopen(obj.PacketTraceFile,"w");
            if fid < 0, error("UAVV541:TraceOpen","Cannot open packet trace."); end
            header = "sim_time_s,packet_timestamp_s,wall_time_utc_s," + ...
                "frame_count,frame_rate_hz,packet_interval_ms," + ...
                "round_trip_ms,design_internal_roll_deg,design_internal_pitch_deg," + ...
                "rc_roll_normalized,rc_pitch_normalized,rc_yaw_normalized," + ...
                "rc_throttle_normalized,rc1_sent_us,rc2_sent_us,rc3_sent_us," + ...
                "rc4_sent_us,rc5_sent_us,rc6_sent_us,rc7_sent_us,rc8_sent_us," + ...
                "protocol_throttle_pwm_us,protocol_aileron_left_pwm_us," + ...
                "protocol_aileron_right_pwm_us,protocol_elevator_pwm_us," + ...
                "protocol_rudder_pwm_us," + ...
                "tx_packets,rx_packets,dropped_packets,duplicate_packets," + ...
                "invalid_packets";
            fprintf(fid,"%s\n",header);
            fclose(fid);
            fid = fopen(obj.FeedbackTraceFile,"w");
            if fid < 0, error("UAVV541:FeedbackTraceOpen", ...
                    "Cannot open feedback trace."); end
            header = "sim_time_s,json_timestamp_s,gyro_x_rad_s,gyro_y_rad_s," + ...
                "gyro_z_rad_s,accel_x_m_s2,accel_y_m_s2,accel_z_m_s2," + ...
                "position_n_m,position_e_m,position_d_m,roll_rad,pitch_rad," + ...
                "yaw_rad,velocity_n_m_s,velocity_e_m_s,velocity_d_m_s," + ...
                "wind_n_m_s,wind_e_m_s,wind_d_m_s,airspeed_m_s," + ...
                "no_time_sync,no_lockstep";
            fprintf(fid,"%s\n",header);
            fclose(fid);
            if obj.P.controller.sitl.auto_launch
                fid = fopen(obj.SitlConsoleLogFile,"w");
                if fid >= 0
                    fprintf(fid,"V5.2 ArduPlane SITL console\n");
                    fclose(fid);
                end
            end
            obj.log("ADAPTER_CREATED",sprintf("run_dir=%s",obj.RuntimeFolder));
        end

        function value = fieldOr(~,s,name,default)
            if isstruct(s) && isfield(s,name)
                value = s.(name);
            else
                value = default;
            end
        end

        function process = launchFirmware(obj,executable,defaultsFile)
            home = obj.P.controller.sitl.home;
            serialArgument = sprintf('--serial0 udpclient:%s:%d', ...
                obj.P.controller.sitl.mavlink_host, ...
                obj.P.controller.sitl.mavlink_port);
            arguments = sprintf([ ...
                '--model JSON:%s --speedup %.6g --rate %d %s ' ...
                '--defaults "%s" --home %.8f,%.8f,%.3f,%.3f --wipe'], ...
                obj.P.controller.sitl.host,obj.P.interface.speedup, ...
                obj.P.controller.sitl.frame_rate_hz, ...
                serialArgument,defaultsFile,home(1),home(2),home(3),home(4));
            startInfo = System.Diagnostics.ProcessStartInfo;
            % Launch the firmware directly so Process refers to ArduPlane,
            % not a short-lived cmd.exe wrapper. This makes log closure and
            % subsequent DataFlash parsing deterministic.
            startInfo.FileName = char(executable);
            startInfo.Arguments = char(arguments);
            startInfo.WorkingDirectory = char(obj.RuntimeFolder);
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            process = System.Diagnostics.Process.Start(startInfo);
            if isempty(process)
                error("UAVV541:ArduPlaneSITLLaunchFailed", ...
                    "Failed to launch ArduPlane SITL: %s",executable);
            end
            obj.log("SITL_STARTED",sprintf("pid=%d command=%s %s", ...
                process.Id,executable,arguments));
        end

        function receiveServoPacket(obj,waitForPacket,requireFreshFrame)
            started = tic;
            while true
                while obj.Socket.NumDatagramsAvailable == 0
                    if ~waitForPacket, return; end
                    if ~isempty(obj.Process) && obj.Process.HasExited
                        error("UAVV541:ArduPlaneSITLExited", ...
                            "ArduPlane SITL exited before producing a servo packet. See %s", ...
                            obj.SitlConsoleLogFile);
                    end
                    if toc(started) > obj.P.controller.sitl.receive_timeout_s
                        error("UAVV541:ArduPlaneSITLTimeout", ...
                            "Timed out waiting for a fresh ArduPlane frame on UDP %d.", ...
                            obj.P.controller.sitl.servo_port);
                    end
                    pause(0.01);
                end
                datagrams = read(obj.Socket,obj.Socket.NumDatagramsAvailable,"uint8");
                found = false;
                for k = 1:numel(datagrams)
                    [pwm,frameRate,frameCount,valid] = ...
                        ArduPilotJSONBridge.parseServoPacket(datagrams(k).Data);
                    if valid
                        obj.RxPackets = obj.RxPackets + 1;
                        if requireFreshFrame && frameCount <= obj.LastFrameCount
                            obj.DuplicatePackets = obj.DuplicatePackets + 1;
                            continue
                        end
                        if frameCount > obj.LastFrameCount + 1
                            obj.DroppedPackets = obj.DroppedPackets + ...
                                double(frameCount-obj.LastFrameCount-1);
                        end
                        if all(pwm == 0)
                            pwm = 1500*ones(size(pwm));
                            pwm(obj.P.controller.sitl.channels.throttle) = ...
                                obj.P.actuator.pwm_min(1);
                        end
                        obj.LastPWM = pwm;
                        obj.LastFrameCount = frameCount;
                        obj.LastFrameRate = frameRate;
                        obj.SenderAddress = string(datagrams(k).SenderAddress);
                        obj.SenderPort = double(datagrams(k).SenderPort);
                        found = true;
                    else
                        obj.InvalidPackets = obj.InvalidPackets + 1;
                    end
                end
                if found || ~waitForPacket, return; end
            end
        end

        function frame = makeStateFrame(obj,time,cmd,state)
            bodyVelocity = state(4:6);
            bodyRates = state(7:9);
            euler = state(10:12);
            Cbn = bodyToNed(euler);
            velocityNed = Cbn*bodyVelocity;
            if obj.StateInitialized
                dt = max(time-obj.LastTime,1e-4);
                bodyAcceleration = (bodyVelocity-obj.PreviousBodyVelocity)/dt + ...
                    cross(bodyRates,bodyVelocity) - Cbn'*[0;0;obj.P.g];
            else
                bodyAcceleration = -Cbn'*[0;0;obj.P.g];
            end
            relativePosition = state(1:3)-obj.P.init.position_ned;
            rc = obj.commandToRC(cmd,state);
            frame = struct;
            % The frame-zero packet is emitted before the configured
            % SIM_RATE_HZ has propagated and therefore reports the built-in
            % 1200 Hz default. Bootstrap that stale frame with the configured
            % communication step; the first response then reports 50 Hz.
            % All subsequent steps honor the live rate requested by SITL.
            if obj.TxPackets == 0 && obj.LastFrameCount == 0
                requestedStep = obj.P.ctrl.Ts;
                obj.log("RATE_BOOTSTRAP",sprintf( ...
                    "initial_request_hz=%.3f applied_step_s=%.6f", ...
                    obj.LastFrameRate,requestedStep));
            else
                requestedStep = 1/max(obj.LastFrameRate,1);
            end
            obj.LastSentTimestamp = obj.LastSentTimestamp + ...
                min(requestedStep,obj.P.ctrl.Ts);
            frame.timestamp = obj.LastSentTimestamp;
            frame.imu = struct("gyro",bodyRates(:)', ...
                "accel_body",bodyAcceleration(:)');
            frame.position = relativePosition(:)';
            frame.attitude = euler(:)';
            % Plane-4.7.0 prefers quaternion when both representations are
            % present.  Supplying the normalized scalar-first quaternion
            % avoids relying on the legacy Euler-only JSON path for sensor
            % truth used by the AHRS/EKF.
            frame.quaternion = eulerToQuaternion(euler);
            frame.velocity = velocityNed(:)';
            frame.velocity_wind = obj.P.env.wind_ned(:)';
            frame.airspeed = max(state(15),0);
            frame.rc = rc;
            frame.no_time_sync = false;
            frame.no_lockstep = false;
        end

        function rc = commandToRC(obj,cmd,state) %#ok<INUSD>
            mapping = obj.P.interface.command_mapping;
            semantics = lower(string(mapping.command_semantics));
            if semantics ~= "rc_normalized"
                error("UAVV541:CommandSemantics", ...
                    "Only rc_normalized commands may reach ArduPilot SITL.");
            end
            axisName = lower(string(obj.P.interface.scenario.axis));
            speedError = cmd(1)-state(15);
            throttleDemand = obj.P.trim.throttle + 0.12*speedError;
            throttleFraction = min(max(throttleDemand,0),1);
            if axisName == "roll"
                rollDemand = min(max(double(cmd(3)),-1),1);
                obj.LastExternalRollDeg = rollDemand*mapping.roll_limit_deg;
                pitchDemand = 0;
                obj.LastExternalPitchDeg = 0;
            elseif axisName == "pitch"
                rollDemand = 0;
                obj.LastExternalRollDeg = 0;
                pitchDemand = min(max(double(cmd(2)),-1),1);
                obj.LastExternalPitchDeg = NaN;
            else
                error("UAVV541:CommandAxis", ...
                    "Formal native AUTOTUNE supports roll or pitch, not %s.",axisName);
            end
            rc = struct;
            rc.rc_1 = obj.normalizedPWM(rollDemand);
            rc.rc_2 = obj.normalizedPWM(pitchDemand);
            rc.rc_3 = obj.throttlePWM(throttleDemand);
            rc.rc_4 = obj.normalizedPWM(0);
            rc.rc_5 = mapping.rc.trim_us;
            rc.rc_6 = 1000;
            rc.rc_7 = 1900;
            rc.rc_8 = 1000;
            obj.LastRc = [rc.rc_1,rc.rc_2,rc.rc_3,rc.rc_4, ...
                rc.rc_5,rc.rc_6,rc.rc_7,rc.rc_8];
            obj.LastRcNormalized = [rollDemand,pitchDemand,0,throttleFraction];
        end

        function command = pwmToProtocolCommand(obj,pwm)
            channels = obj.P.controller.sitl.channels;
            orderedPwm = [pwm(channels.throttle); ...
                pwm(channels.aileron_left); pwm(channels.aileron_right); ...
                pwm(channels.elevator); pwm(channels.rudder)];
            valid = double(all(isfinite(orderedPwm)) && ...
                all(orderedPwm >= 500 & orderedPwm <= 2500));
            command = [orderedPwm;obj.LastSentTimestamp; ...
                double(obj.LastFrameCount);obj.LastFrameRate;valid];
        end

        function trace = rcTraceVector(obj)
            valid = double(all(isfinite(obj.LastRc)) && ...
                all(obj.LastRc >= 500 & obj.LastRc <= 2500));
            trace = [obj.LastRcNormalized(:);obj.LastRc(:); ...
                obj.LastSentTimestamp;valid];
        end

        function pwm = normalizedPWM(obj,value)
            value = min(max(double(value),-1),1);
            rcCfg = obj.P.interface.command_mapping.rc;
            if value >= 0
                pwm = rcCfg.trim_us + value*(rcCfg.max_us-rcCfg.trim_us);
            else
                pwm = rcCfg.trim_us + value*(rcCfg.trim_us-rcCfg.min_us);
            end
        end

        function pwm = throttlePWM(obj,value)
            value = min(max(double(value),0),1);
            rcCfg = obj.P.interface.command_mapping.rc;
            pwm = rcCfg.min_us + value*(rcCfg.max_us-rcCfg.min_us);
        end

        function appendPacketTrace(obj,time)
            c = obj.P.controller.sitl.channels;
            ordered = [obj.LastPWM(c.throttle),obj.LastPWM(c.aileron_left), ...
                obj.LastPWM(c.aileron_right),obj.LastPWM(c.elevator), ...
                obj.LastPWM(c.rudder)];
            wallNow = posixtime(datetime("now","TimeZone","UTC"));
            if isfinite(obj.LastWallReceive)
                packetIntervalMs = 1000*(wallNow-obj.LastWallReceive);
            else
                packetIntervalMs = NaN;
            end
            obj.LastWallReceive = wallNow;
            fid = fopen(obj.PacketTraceFile,"a");
            if fid < 0, return; end
            prefix = sprintf("%.9f,%.9f,%.6f,%u,%.3f,%.6f,%.6f", ...
                time,obj.LastSentTimestamp,wallNow,obj.LastFrameCount, ...
                obj.LastFrameRate,packetIntervalMs,obj.LastRttMs);
            values = [obj.LastExternalRollDeg,obj.LastExternalPitchDeg, ...
                obj.LastRcNormalized,obj.LastRc,ordered];
            middle = sprintf(",%.9g",values);
            suffix = sprintf(",%d,%d,%d,%d,%d\n",obj.TxPackets, ...
                obj.RxPackets,obj.DroppedPackets,obj.DuplicatePackets, ...
                obj.InvalidPackets);
            fprintf(fid,"%s%s%s",prefix,middle,suffix);
            fclose(fid);
        end

        function appendFeedbackTrace(obj,time)
            if isempty(fieldnames(obj.LastStateFrame)), return; end
            frame = obj.LastStateFrame;
            row = [time,frame.timestamp,frame.imu.gyro, ...
                frame.imu.accel_body,frame.position,frame.attitude, ...
                frame.velocity,frame.velocity_wind,frame.airspeed, ...
                double(frame.no_time_sync),double(frame.no_lockstep)];
            fid = fopen(obj.FeedbackTraceFile,"a");
            if fid < 0, return; end
            fprintf(fid,"%.9g",row(1));
            fprintf(fid,",%.9g",row(2:end));
            fprintf(fid,"\n");
            fclose(fid);
        end

        function setState(obj,newState,detail)
            previous = obj.AdapterState;
            obj.AdapterState = string(newState);
            obj.log("STATE",sprintf("%s -> %s | %s",previous,newState,detail));
        end

        function writeSummary(obj)
            s = obj.status();
            s.closed_at = string(datetime("now","Format","yyyy-MM-dd HH:mm:ss.SSS"));
            fid = fopen(obj.SummaryFile,"w");
            if fid < 0, return; end
            fprintf(fid,"%s",jsonencode(s,"PrettyPrint",true));
            fclose(fid);
        end

        function log(obj,eventName,detail)
            fid = fopen(obj.AdapterLogFile,"a");
            if fid < 0, return; end
            timestamp = string(datetime("now","Format","yyyy-MM-dd HH:mm:ss.SSS"));
            fprintf(fid,"%s | %s | %s\n",timestamp,eventName,string(detail));
            fclose(fid);
        end
    end
end

function q = eulerToQuaternion(euler)
phi = euler(1); theta = euler(2); psi = euler(3);
cr = cos(phi/2); sr = sin(phi/2);
cp = cos(theta/2); sp = sin(theta/2);
cy = cos(psi/2); sy = sin(psi/2);
q = [cr*cp*cy + sr*sp*sy, ...
    sr*cp*cy - cr*sp*sy, ...
    cr*sp*cy + sr*cp*sy, ...
    cr*cp*sy - sr*sp*cy];
q = q/max(norm(q),eps);
end

function Cbn = bodyToNed(euler)
phi=euler(1); theta=euler(2); psi=euler(3);
cPhi=cos(phi); sPhi=sin(phi); cTheta=cos(theta); sTheta=sin(theta);
cPsi=cos(psi); sPsi=sin(psi);
Cnb = [cTheta*cPsi,cTheta*sPsi,-sTheta; ...
    sPhi*sTheta*cPsi-cPhi*sPsi,sPhi*sTheta*sPsi+cPhi*cPsi,sPhi*cTheta; ...
    cPhi*sTheta*cPsi+sPhi*sPsi,cPhi*sTheta*sPsi-sPhi*cPsi,cPhi*cTheta];
Cbn = Cnb';
end
