#!/usr/bin/env python3
"""State-driven SITL gate with V5.4.1 official AUTOTUNE completion."""

from __future__ import annotations

import argparse
import csv
import json
import math
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

from pymavlink import mavutil


PLANE_MODES = {"FBWA": 5, "AUTOTUNE": 8}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2), encoding="utf-8")
    temporary.replace(path)


def read_recent_rows(path: Path, count: int) -> list[dict[str, str]]:
    rows: deque[dict[str, str]] = deque(maxlen=count)
    try:
        with path.open("r", newline="", encoding="utf-8") as stream:
            for row in csv.DictReader(stream):
                rows.append(row)
    except (OSError, UnicodeError, csv.Error):
        return []
    return list(rows)


def numbers(row: dict[str, str], fields: list[str]) -> list[float] | None:
    try:
        values = [float(row[field]) for field in fields]
    except (KeyError, TypeError, ValueError):
        return None
    return values if all(math.isfinite(value) for value in values) else None


def latest_simulation_time(trace_file: Path) -> float | None:
    rows = read_recent_rows(trace_file, 1)
    if not rows:
        return None
    values = numbers(rows[-1], ["sim_time_s"])
    return None if values is None else values[0]


def latest_truth_attitude(feedback_file: Path) -> tuple[float, float, float] | None:
    rows = read_recent_rows(feedback_file, 1)
    if not rows:
        return None
    values = numbers(rows[-1], ["roll_rad", "pitch_rad", "yaw_rad"])
    return None if values is None else (values[0], values[1], values[2])


def wrapped_angle_error(a: float, b: float) -> float:
    return abs(math.atan2(math.sin(a - b), math.cos(a - b)))


def fdm_readiness(trace_file: Path, feedback_file: Path,
                  required_count: int) -> dict:
    packet_rows = read_recent_rows(trace_file, required_count)
    state_rows = read_recent_rows(feedback_file, required_count)
    result = {
        "pass": False,
        "required_consecutive_frames": required_count,
        "packet_rows_observed": len(packet_rows),
        "state_rows_observed": len(state_rows),
    }
    if len(packet_rows) < required_count or len(state_rows) < required_count:
        result["detail"] = "INSUFFICIENT_CONSECUTIVE_FDM_OR_STATE_FRAMES"
        return result

    packet_fields = [
        "sim_time_s", "packet_timestamp_s", "frame_count", "frame_rate_hz",
        "tx_packets", "rx_packets", "dropped_packets", "invalid_packets",
    ]
    state_fields = [
        "sim_time_s", "json_timestamp_s", "gyro_x_rad_s", "gyro_y_rad_s",
        "gyro_z_rad_s", "accel_x_m_s2", "accel_y_m_s2", "accel_z_m_s2",
        "position_n_m", "position_e_m", "position_d_m", "roll_rad",
        "pitch_rad", "yaw_rad", "velocity_n_m_s", "velocity_e_m_s",
        "velocity_d_m_s", "airspeed_m_s",
    ]
    packet_values = [numbers(row, packet_fields) for row in packet_rows]
    state_values = [numbers(row, state_fields) for row in state_rows]
    if any(value is None for value in packet_values + state_values):
        result["detail"] = "NONFINITE_OR_MISSING_FDM_STATE_FIELD"
        return result

    packet_values = [value for value in packet_values if value is not None]
    state_values = [value for value in state_values if value is not None]
    sim_times = [value[0] for value in packet_values]
    packet_times = [value[1] for value in packet_values]
    frames = [int(value[2]) for value in packet_values]
    state_times = [value[0] for value in state_values]
    json_times = [value[1] for value in state_values]
    monotonic = (
        all(b > a for a, b in zip(sim_times, sim_times[1:]))
        and all(b > a for a, b in zip(packet_times, packet_times[1:]))
        and all(b > a for a, b in zip(state_times, state_times[1:]))
        and all(b > a for a, b in zip(json_times, json_times[1:]))
    )
    continuous = all(b - a == 1 for a, b in zip(frames, frames[1:]))
    clean = all(value[6] == 0 and value[7] == 0 for value in packet_values)
    reasonable = all(
        0 < value[17] < 200
        and abs(value[11]) <= 1.1 * math.pi
        and abs(value[12]) <= 1.1 * math.pi
        and max(abs(item) for item in value[2:8]) < 500
        and max(abs(item) for item in value[8:11]) < 1.0e6
        for value in state_values
    )
    result.update({
        "timestamp_monotonic": monotonic,
        "frame_continuity": continuous,
        "no_dropped_or_invalid_frames": clean,
        "state_reasonable": reasonable,
        "observed_simulation_s": sim_times[-1],
        "observed_frame_start": frames[0],
        "observed_frame_end": frames[-1],
        "sensor_state_sources": [
            "IMU_GYRO", "IMU_ACCEL", "ATTITUDE", "AIRSPEED",
            "POSITION", "VELOCITY",
        ],
    })
    result["pass"] = bool(monotonic and continuous and clean and reasonable)
    result["detail"] = "FDM_AND_SENSOR_STATE_STABLE" if result["pass"] else (
        "FDM_OR_SENSOR_STATE_VALIDATION_FAILED"
    )
    return result


def parameter_id(message) -> str:
    value = message.param_id
    if isinstance(value, (bytes, bytearray)):
        return bytes(value).decode("ascii", errors="ignore").rstrip("\x00")
    return str(value).rstrip("\x00")


def status_text(message) -> str:
    value = message.text
    if isinstance(value, (bytes, bytearray)):
        return bytes(value).decode("utf-8", errors="ignore").rstrip("\x00")
    return str(value).rstrip("\x00")


def signal_abort(path: Path, reason: str, simulation_time: float | None,
                 detail: str, observed_mode: int | None = None) -> dict:
    evidence = {
        "failure_reason": reason,
        "detail": detail,
        "detected_timestamp_utc": utc_now(),
        "simulation_time_s": simulation_time,
        "rc_command_action": "NEUTRAL",
    }
    if observed_mode is not None:
        evidence["observed_mode_number"] = observed_mode
    write_json(path, evidence)
    return evidence


def wait_sitl_ready(connection, args: argparse.Namespace) -> tuple[dict, int, int]:
    deadline = time.monotonic() + args.startup_timeout_wall_seconds
    heartbeat_count = 0
    last_heartbeat_wall: float | None = None
    target_system = 0
    target_component = 0
    query_sent_wall: float | None = None
    query_result: dict | None = None
    query_attempts = 0
    parameter_list_requested = False
    observed_parameter_ids: list[str] = []
    latest_fdm: dict = {"pass": False, "detail": "FDM_NOT_OBSERVED"}
    attitude_request_wall: float | None = None
    attitude_alignment_count = 0
    attitude_alignment: dict = {
        "pass": False,
        "detail": "ATTITUDE_ALIGNMENT_NOT_OBSERVED",
    }

    while time.monotonic() < deadline:
        simulation_time = latest_simulation_time(args.trace_file)
        latest_fdm = fdm_readiness(
            args.trace_file, args.feedback_file, args.fdm_required_count
        )
        while True:
            message = connection.recv_match(blocking=False)
            if message is None:
                break
            if message.get_type() == "HEARTBEAT" and message.get_srcSystem() != 0:
                target_system = message.get_srcSystem()
                target_component = message.get_srcComponent()
                if simulation_time is not None and simulation_time > 0:
                    heartbeat_count += 1
                    last_heartbeat_wall = time.monotonic()
            elif message.get_type() == "PARAM_VALUE":
                received_name = parameter_id(message)
                if received_name not in observed_parameter_ids:
                    observed_parameter_ids.append(received_name)
                if received_name == args.parameter_query_name:
                    query_result = {
                        "pass": True,
                        "parameter": received_name,
                        "value": float(message.param_value),
                        "readback_timestamp_utc": utc_now(),
                    }
            elif message.get_type() == "ATTITUDE" and target_system != 0:
                truth = latest_truth_attitude(args.feedback_file)
                if truth is not None:
                    estimate = (float(message.roll), float(message.pitch), float(message.yaw))
                    errors_deg = [
                        math.degrees(wrapped_angle_error(estimate[k], truth[k]))
                        for k in range(3)
                    ]
                    aligned = (
                        errors_deg[0] <= args.attitude_alignment_roll_pitch_tolerance_deg
                        and errors_deg[1] <= args.attitude_alignment_roll_pitch_tolerance_deg
                        and errors_deg[2] <= args.attitude_alignment_yaw_tolerance_deg
                    )
                    attitude_alignment_count = (
                        attitude_alignment_count + 1 if aligned else 0
                    )
                    attitude_alignment = {
                        "pass": attitude_alignment_count
                        >= args.attitude_alignment_required_count,
                        "required_consecutive_messages":
                            args.attitude_alignment_required_count,
                        "observed_consecutive_messages": attitude_alignment_count,
                        "roll_error_deg": errors_deg[0],
                        "pitch_error_deg": errors_deg[1],
                        "yaw_error_deg": errors_deg[2],
                        "roll_pitch_tolerance_deg":
                            args.attitude_alignment_roll_pitch_tolerance_deg,
                        "yaw_tolerance_deg": args.attitude_alignment_yaw_tolerance_deg,
                        "detail": (
                            "FIRMWARE_ATTITUDE_ALIGNED_TO_TRUTH"
                            if attitude_alignment_count
                            >= args.attitude_alignment_required_count
                            else "FIRMWARE_ATTITUDE_NOT_YET_ALIGNED"
                        ),
                    }

        if target_system != 0 and (
            attitude_request_wall is None
            or time.monotonic() - attitude_request_wall >= 2.0
        ):
            connection.mav.command_long_send(
                target_system,
                target_component,
                mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL,
                0,
                mavutil.mavlink.MAVLINK_MSG_ID_ATTITUDE,
                100000,
                0,
                0,
                0,
                0,
                0,
            )
            attitude_request_wall = time.monotonic()

        if (
            last_heartbeat_wall is not None
            and time.monotonic() - last_heartbeat_wall
            > args.mode_heartbeat_timeout_wall_seconds
        ):
            heartbeat_count = 0
            last_heartbeat_wall = None

        guard_pass = (
            simulation_time is not None
            and simulation_time >= args.minimum_startup_guard_seconds
        )
        heartbeat_pass = heartbeat_count >= args.heartbeat_required_count
        communication_base_ready = (
            guard_pass and heartbeat_pass and latest_fdm.get("pass", False)
            and attitude_alignment.get("pass", False) and target_system != 0
        )
        if communication_base_ready and query_result is None:
            if query_sent_wall is None or time.monotonic() - query_sent_wall >= 2.0:
                query_component = target_component if query_attempts % 2 == 0 else 0
                connection.mav.param_request_read_send(
                    target_system,
                    query_component,
                    args.parameter_query_name.encode("ascii"),
                    -1,
                )
                query_sent_wall = time.monotonic()
                query_attempts += 1
                if query_attempts >= 2 and not parameter_list_requested:
                    connection.mav.param_request_list_send(target_system, 0)
                    parameter_list_requested = True

        if communication_base_ready and query_result is not None:
            ready = {
                "pass": True,
                "state": "SITL_READY",
                "ready_timestamp_utc": utc_now(),
                "ready_simulation_s": simulation_time,
                "minimum_startup_guard_s": args.minimum_startup_guard_seconds,
                "heartbeat": {
                    "pass": True,
                    "required_count": args.heartbeat_required_count,
                    "observed_count": heartbeat_count,
                },
                "fdm": latest_fdm,
                "sensor_state": {
                    "pass": True,
                    "sources": latest_fdm["sensor_state_sources"],
                    "detail": "CONTINUOUS_FINITE_STATE_UPDATES",
                },
                "attitude_alignment": attitude_alignment,
                "parameter_query": query_result,
            }
            write_json(args.sitl_ready_output, ready)
            return ready, target_system, target_component

        if (
            simulation_time is not None
            and simulation_time >= args.scoring_start_sim_seconds
        ):
            break
        time.sleep(0.05)

    simulation_time = latest_simulation_time(args.trace_file)
    failed = {
        "pass": False,
        "state": "WAIT_FOR_SITL_READY",
        "failure_reason": "STARTUP_TIMEOUT",
        "detail": "SITL_READY_NOT_REACHED_BEFORE_TIMEOUT_OR_SCORING_WINDOW",
        "observed_simulation_s": simulation_time,
        "heartbeat_observed_count": heartbeat_count,
        "heartbeat_required_count": args.heartbeat_required_count,
        "fdm": latest_fdm,
        "attitude_alignment": attitude_alignment,
        "parameter_query_pass": query_result is not None,
        "parameter_query_attempts": query_attempts,
        "parameter_list_fallback_requested": parameter_list_requested,
        "observed_parameter_ids": observed_parameter_ids[:20],
    }
    write_json(args.sitl_ready_output, failed)
    signal_abort(
        args.mode_dropout_output,
        "STARTUP_TIMEOUT",
        simulation_time,
        failed["detail"],
    )
    return failed, target_system, target_component


def request_mode(connection, mode: str, target_system: int,
                 target_component: int, timeout: float) -> dict:
    requested_number = PLANE_MODES[mode]
    result = {
        "requested_mode": mode,
        "requested_mode_number": requested_number,
        "request_timestamp_utc": utc_now(),
        "ack_received": False,
        "ack_result": None,
        "readback_mode_number": None,
        "readback_pass": False,
        "pass": False,
        "failure_reason": "MODE_CHANGE_FAIL",
    }
    connection.mav.command_long_send(
        target_system,
        target_component,
        mavutil.mavlink.MAV_CMD_DO_SET_MODE,
        0,
        mavutil.mavlink.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED,
        requested_number,
        0,
        0,
        0,
        0,
        0,
    )
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        message = connection.recv_match(blocking=True, timeout=0.5)
        if message is None:
            continue
        if message.get_type() == "COMMAND_ACK" and int(message.command) == int(
            mavutil.mavlink.MAV_CMD_DO_SET_MODE
        ):
            result["ack_received"] = True
            result["ack_result"] = int(message.result)
            result["ack_timestamp_utc"] = utc_now()
        elif (
            message.get_type() == "HEARTBEAT"
            and message.get_srcSystem() == target_system
        ):
            result["readback_mode_number"] = int(message.custom_mode)
            if int(message.custom_mode) == requested_number:
                result["readback_pass"] = True
                result["readback_timestamp_utc"] = utc_now()
        accepted = int(mavutil.mavlink.MAV_RESULT_ACCEPTED)
        if (
            result["ack_received"]
            and result["ack_result"] == accepted
            and result["readback_pass"]
        ):
            result["pass"] = True
            result["failure_reason"] = ""
            result["detail"] = "MODE_CHANGE_ACK_AND_READBACK_PASS"
            return result
    result["detail"] = "ACK_OR_HEARTBEAT_READBACK_FAILED"
    return result


def confirm_mode(connection, expected_mode: str, target_system: int,
                 args: argparse.Namespace, initial_count: int = 0) -> dict:
    expected_number = PLANE_MODES[expected_mode]
    count = initial_count
    first_simulation_time = latest_simulation_time(args.trace_file)
    deadline = time.monotonic() + args.command_timeout
    unexpected_modes: list[int] = []
    while time.monotonic() < deadline:
        simulation_time = latest_simulation_time(args.trace_file)
        message = connection.recv_match(type="HEARTBEAT", blocking=True, timeout=0.5)
        if message is not None and message.get_srcSystem() == target_system:
            observed = int(message.custom_mode)
            if observed == expected_number:
                if count == 0:
                    first_simulation_time = simulation_time
                count += 1
            else:
                unexpected_modes.append(observed)
                count = 0
                first_simulation_time = None
        stable_window = 0.0
        if simulation_time is not None and first_simulation_time is not None:
            stable_window = simulation_time - first_simulation_time
        if (
            count >= args.mode_required_count
            and stable_window >= args.mode_stable_sim_seconds
        ):
            return {
                "pass": True,
                "expected_mode": expected_mode,
                "expected_mode_number": expected_number,
                "required_heartbeat_count": args.mode_required_count,
                "observed_consecutive_heartbeat_count": count,
                "required_stable_simulation_s": args.mode_stable_sim_seconds,
                "observed_stable_simulation_s": stable_window,
                "ready_simulation_s": simulation_time,
                "confirmation_timestamp_utc": utc_now(),
            }
    return {
        "pass": False,
        "failure_reason": "MODE_CHANGE_FAIL",
        "detail": "CONSECUTIVE_MODE_HEARTBEAT_CONFIRMATION_FAILED",
        "expected_mode": expected_mode,
        "observed_consecutive_heartbeat_count": count,
        "unexpected_modes": unexpected_modes,
        "observed_simulation_s": latest_simulation_time(args.trace_file),
    }


def enter_stable_mode(connection, mode: str, target_system: int,
                      target_component: int, args: argparse.Namespace) -> dict:
    request = request_mode(
        connection, mode, target_system, target_component, args.command_timeout
    )
    confirmation = confirm_mode(
        connection,
        mode,
        target_system,
        args,
        initial_count=1 if request["readback_pass"] else 0,
    )
    result = dict(request)
    result["stable_confirmation"] = confirmation
    result["pass"] = bool(request["pass"] and confirmation["pass"])
    result["failure_reason"] = "" if result["pass"] else "MODE_CHANGE_FAIL"
    result["detail"] = (
        "ACK_READBACK_AND_STABLE_HEARTBEATS_PASS"
        if result["pass"]
        else "MODE_REQUEST_OR_STABLE_CONFIRMATION_FAILED"
    )
    if confirmation.get("ready_simulation_s") is not None:
        result["ready_simulation_s"] = confirmation["ready_simulation_s"]
    return result


def monitor_mode(connection, expected_mode: str, target_system: int,
                 args: argparse.Namespace) -> dict:
    expected_number = PLANE_MODES[expected_mode]
    deadline = time.monotonic() + args.session_timeout
    last_heartbeat_wall = time.monotonic()
    total_scoring_heartbeats = 0
    expected_scoring_heartbeats = 0
    manual_scoring_heartbeats = 0
    other_scoring_heartbeats = 0
    first_scoring_heartbeat_sim: float | None = None
    last_scoring_heartbeat_sim: float | None = None

    while time.monotonic() < deadline:
        simulation_time = latest_simulation_time(args.trace_file)
        if args.abort_file.exists():
            result = {
                "pass": False,
                "failure_reason": "ENVELOPE_VIOLATION",
                "completion_class": "ABORTED_SAFETY",
                "safety_abort": True,
                "observed_simulation_s": simulation_time,
            }
            write_json(args.live_audit_output, result)
            return result

        while True:
            message = connection.recv_match(blocking=False)
            if message is None:
                break
            if message.get_srcSystem() != target_system:
                continue
            if (
                expected_mode == "AUTOTUNE"
                and args.autotune_axis
                and message.get_type() == "STATUSTEXT"
            ):
                text = status_text(message).strip()
                expected_text = f"{args.autotune_axis.capitalize()}: Finished"
                if text.casefold() == expected_text.casefold():
                    evidence = {
                        "pass": True,
                        "completion_class": "COMPLETE_OFFICIAL_FINISHED",
                        "finished_axis": args.autotune_axis,
                        "finished_text": text,
                        "first_finished_simulation_s": simulation_time,
                        "first_finished_timestamp_utc": utc_now(),
                        "excitation_action": "NEUTRAL_IMMEDIATELY",
                        "next_mode": "FBWA",
                    }
                    write_json(args.official_finished_output, evidence)
                    write_json(args.live_audit_output, evidence)
                    return evidence
            if message.get_type() != "HEARTBEAT":
                continue
            last_heartbeat_wall = time.monotonic()
            observed_mode = int(message.custom_mode)
            if (
                simulation_time is not None
                and args.scoring_start_sim_seconds <= simulation_time
                <= args.scoring_end_sim_seconds
            ):
                total_scoring_heartbeats += 1
                if first_scoring_heartbeat_sim is None:
                    first_scoring_heartbeat_sim = simulation_time
                last_scoring_heartbeat_sim = simulation_time
                if observed_mode == expected_number:
                    expected_scoring_heartbeats += 1
                elif observed_mode == 0:
                    manual_scoring_heartbeats += 1
                else:
                    other_scoring_heartbeats += 1
            if observed_mode != expected_number:
                dropout = signal_abort(
                    args.mode_dropout_output,
                    "MODE_DROPOUT",
                    simulation_time,
                    f"EXPECTED_{expected_mode}_OBSERVED_MODE_{observed_mode}",
                    observed_mode,
                )
                dropout.update({
                    "pass": False,
                    "completion_class": "FAILED_COMMUNICATION",
                    "expected_mode": expected_mode,
                    "expected_mode_number": expected_number,
                })
                write_json(args.live_audit_output, dropout)
                return dropout

        if (
            time.monotonic() - last_heartbeat_wall
            > args.mode_heartbeat_timeout_wall_seconds
        ):
            dropout = signal_abort(
                args.mode_dropout_output,
                "MODE_DROPOUT",
                simulation_time,
                "HEARTBEAT_LOST_DURING_MODE_PERSISTENCE_MONITOR",
            )
            dropout["pass"] = False
            dropout["completion_class"] = "FAILED_COMMUNICATION"
            write_json(args.live_audit_output, dropout)
            return dropout

        if (
            simulation_time is not None
            and simulation_time >= args.exit_after_sim_seconds
        ):
            coverage = (
                expected_scoring_heartbeats / total_scoring_heartbeats
                if total_scoring_heartbeats else 0.0
            )
            pass_result = (
                simulation_time >= args.scoring_end_sim_seconds
                and total_scoring_heartbeats > 0
                and expected_scoring_heartbeats == total_scoring_heartbeats
            )
            if expected_mode == "AUTOTUNE" and args.autotune_axis:
                result = {
                    "pass": False,
                    "failure_reason": "INCOMPLETE_TIMEOUT",
                    "completion_class": "INCOMPLETE_TIMEOUT",
                    "finished_axis": args.autotune_axis,
                    "finished_text": "",
                    "observed_end_simulation_s": simulation_time,
                    "excitation_action": "NEUTRAL_AT_TIMEOUT",
                }
                write_json(args.live_audit_output, result)
                return result
            result = {
                "pass": pass_result,
                "failure_reason": "" if pass_result else "MODE_DROPOUT",
                "expected_mode": expected_mode,
                "expected_mode_number": expected_number,
                "scoring_start_simulation_s": args.scoring_start_sim_seconds,
                "scoring_end_simulation_s": args.scoring_end_sim_seconds,
                "observed_end_simulation_s": simulation_time,
                "scoring_heartbeat_count": total_scoring_heartbeats,
                "expected_mode_heartbeat_count": expected_scoring_heartbeats,
                "manual_heartbeat_count": manual_scoring_heartbeats,
                "other_mode_heartbeat_count": other_scoring_heartbeats,
                "expected_mode_heartbeat_coverage": coverage,
                "first_scoring_heartbeat_simulation_s": first_scoring_heartbeat_sim,
                "last_scoring_heartbeat_simulation_s": last_scoring_heartbeat_sim,
                "detail": (
                    "LIVE_MODE_PERSISTENCE_PASS"
                    if pass_result else "LIVE_SCORING_WINDOW_MODE_COVERAGE_FAILED"
                ),
            }
            if not pass_result:
                signal_abort(
                    args.mode_dropout_output,
                    "MODE_DROPOUT",
                    simulation_time,
                    result["detail"],
                )
            write_json(args.live_audit_output, result)
            return result
        time.sleep(0.05)

    result = {
        "pass": False,
        "failure_reason": "MODE_DROPOUT",
        "completion_class": "FAILED_COMMUNICATION",
        "detail": "MODE_MONITOR_WALL_TIMEOUT",
        "observed_simulation_s": latest_simulation_time(args.trace_file),
    }
    signal_abort(
        args.mode_dropout_output,
        "MODE_DROPOUT",
        result["observed_simulation_s"],
        result["detail"],
    )
    write_json(args.live_audit_output, result)
    return result


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=14552)
    parser.add_argument("--entry-mode", choices=sorted(PLANE_MODES), required=True)
    parser.add_argument("--entry-output", required=True, type=Path)
    parser.add_argument("--precondition-output", required=True, type=Path)
    parser.add_argument("--exit-output", required=True, type=Path)
    parser.add_argument("--session-output", required=True, type=Path)
    parser.add_argument("--trace-file", required=True, type=Path)
    parser.add_argument("--feedback-file", required=True, type=Path)
    parser.add_argument("--abort-file", required=True, type=Path)
    parser.add_argument("--sitl-ready-output", required=True, type=Path)
    parser.add_argument("--fbwa-ready-output", required=True, type=Path)
    parser.add_argument("--mode-ready-output", required=True, type=Path)
    parser.add_argument("--mode-dropout-output", required=True, type=Path)
    parser.add_argument("--live-audit-output", required=True, type=Path)
    parser.add_argument("--official-finished-output", required=True, type=Path)
    parser.add_argument("--autotune-axis", default="")
    parser.add_argument("--exit-after-sim-seconds", required=True, type=float)
    parser.add_argument("--scoring-start-sim-seconds", required=True, type=float)
    parser.add_argument("--scoring-end-sim-seconds", required=True, type=float)
    parser.add_argument("--minimum-startup-guard-seconds", required=True, type=float)
    parser.add_argument("--startup-timeout-wall-seconds", required=True, type=float)
    parser.add_argument("--heartbeat-required-count", required=True, type=int)
    parser.add_argument("--fdm-required-count", required=True, type=int)
    parser.add_argument(
        "--attitude-alignment-required-count", required=True, type=int
    )
    parser.add_argument(
        "--attitude-alignment-roll-pitch-tolerance-deg", required=True, type=float
    )
    parser.add_argument(
        "--attitude-alignment-yaw-tolerance-deg", required=True, type=float
    )
    parser.add_argument("--mode-required-count", required=True, type=int)
    parser.add_argument("--mode-stable-sim-seconds", required=True, type=float)
    parser.add_argument(
        "--mode-heartbeat-timeout-wall-seconds", required=True, type=float
    )
    parser.add_argument("--parameter-query-name", required=True)
    parser.add_argument("--command-timeout", type=float, default=45.0)
    parser.add_argument("--session-timeout", type=float, default=1800.0)
    args = parser.parse_args()
    if args.autotune_axis not in ("", "roll", "pitch", "yaw"):
        parser.error("--autotune-axis must be roll, pitch, yaw, or empty")
    return args


def main() -> int:
    args = parse_arguments()
    session = {
        "connection": f"udpin:127.0.0.1:{args.port}",
        "entry_mode": args.entry_mode,
        "started_timestamp_utc": utc_now(),
        "pass": False,
        "failure_reason": "MODE_CHANGE_FAIL",
        "state": "WAIT_FOR_SITL_READY",
    }
    connection = mavutil.mavlink_connection(
        session["connection"], source_system=250, source_component=190
    )

    sitl_ready, target_system, target_component = wait_sitl_ready(connection, args)
    session["sitl_ready"] = sitl_ready
    if not sitl_ready["pass"]:
        session["failure_reason"] = "STARTUP_TIMEOUT"
        session["detail"] = sitl_ready["detail"]
        write_json(args.session_output, session)
        return 2

    session["target_system"] = target_system
    session["target_component"] = target_component
    session["state"] = "REQUEST_FBWA"
    precondition = enter_stable_mode(
        connection, "FBWA", target_system, target_component, args
    )
    write_json(args.precondition_output, precondition)
    session["precondition"] = precondition
    if not precondition["pass"]:
        signal_abort(
            args.mode_dropout_output,
            "MODE_CHANGE_FAIL",
            latest_simulation_time(args.trace_file),
            "FBWA_READY_CONFIRMATION_FAILED",
        )
        session["detail"] = "FBWA_PRECONDITION_FAILED"
        write_json(args.session_output, session)
        return 3

    fbwa_ready = {
        "pass": True,
        "state": "FBWA_READY",
        "ready_simulation_s": precondition["ready_simulation_s"],
        "ready_timestamp_utc": utc_now(),
        "mode_evidence": precondition,
    }
    write_json(args.fbwa_ready_output, fbwa_ready)
    session["fbwa_ready"] = fbwa_ready

    if args.entry_mode == "AUTOTUNE":
        session["state"] = "REQUEST_AUTOTUNE"
        entry = enter_stable_mode(
            connection, "AUTOTUNE", target_system, target_component, args
        )
    else:
        entry = dict(precondition)
    write_json(args.entry_output, entry)
    session["entry"] = entry
    if not entry["pass"]:
        signal_abort(
            args.mode_dropout_output,
            "MODE_CHANGE_FAIL",
            latest_simulation_time(args.trace_file),
            "ENTRY_MODE_STABLE_CONFIRMATION_FAILED",
        )
        session["detail"] = "ENTRY_MODE_FAILED"
        write_json(args.session_output, session)
        return 4

    ready_simulation_time = float(entry["ready_simulation_s"])
    if ready_simulation_time >= args.scoring_start_sim_seconds:
        signal_abort(
            args.mode_dropout_output,
            "STARTUP_TIMEOUT",
            ready_simulation_time,
            "FBWA_READY_NOT_REACHED_BEFORE_SCORING_WINDOW",
        )
        session["failure_reason"] = "STARTUP_TIMEOUT"
        session["detail"] = "FBWA_READY_NOT_REACHED_BEFORE_SCORING_WINDOW"
        write_json(args.session_output, session)
        return 5

    mode_ready = {
        "pass": True,
        "state": f"{args.entry_mode}_READY",
        "ready_simulation_s": ready_simulation_time,
        "ready_timestamp_utc": utc_now(),
        "scoring_start_simulation_s": args.scoring_start_sim_seconds,
        "scoring_end_simulation_s": args.scoring_end_sim_seconds,
    }
    write_json(args.mode_ready_output, mode_ready)
    session["mode_ready"] = mode_ready
    session["state"] = "MONITOR_MODE_PERSISTENCE"

    live_monitor = monitor_mode(connection, args.entry_mode, target_system, args)
    session["live_mode_monitor"] = live_monitor
    exit_result = request_mode(
        connection, "FBWA", target_system, target_component, args.command_timeout
    )
    write_json(args.exit_output, exit_result)
    session["exit"] = exit_result
    session["pass"] = bool(
        sitl_ready["pass"]
        and precondition["pass"]
        and entry["pass"]
        and live_monitor["pass"]
        and exit_result["pass"]
    )
    session["failure_reason"] = "" if session["pass"] else live_monitor.get(
        "failure_reason", "MODE_CHANGE_FAIL"
    )
    session["detail"] = (
        "SITL_READY_FBWA_READY_AND_MODE_PERSISTENCE_PASS"
        if session["pass"]
        else "MODE_GATE_SESSION_FAILED"
    )
    session["state"] = "COMPLETE" if session["pass"] else "FAILED"
    session["completed_timestamp_utc"] = utc_now()
    write_json(args.session_output, session)
    return 0 if session["pass"] else 6


if __name__ == "__main__":
    raise SystemExit(main())
