#!/usr/bin/env python3
"""Export commit-pinned ArduPlane evidence required by V5.3."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

try:
    from pymavlink import DFReader
except ImportError as exc:  # pragma: no cover - environment diagnostic
    raise SystemExit(
        "pymavlink is missing. Re-run scripts/sitl/setup_wsl_ardupilot.ps1 so the "
        "ArduPilot prerequisites are installed."
    ) from exc


MESSAGE_TYPES = (
    "ATT",
    "RCIN",
    "RCOU",
    "PIDR",
    "PIDP",
    "PIDY",
    "PARM",
    "MODE",
    "CTUN",
    "NTUN",
    "VER",
    "ATRP",
    "MSG",
    "EV",
)


def scalar(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace").rstrip("\x00")
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    return str(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    reader = DFReader.DFReader_binary(str(args.input), zero_time_base=False)
    rows: dict[str, list[dict]] = {name: [] for name in MESSAGE_TYPES}
    while True:
        message = reader.recv_match(type=list(MESSAGE_TYPES))
        if message is None:
            break
        message_type = message.get_type()
        row = {key: scalar(value) for key, value in message.to_dict().items()}
        if "TimeUS" in row:
            row["ap_time_s"] = float(row["TimeUS"]) / 1.0e6
        rows[message_type].append(row)

    counts = {}
    for message_type, message_rows in rows.items():
        if not message_rows:
            continue
        columns = []
        for row in message_rows:
            for key in row:
                if key not in columns:
                    columns.append(key)
        target = args.output / f"internal_{message_type}.csv"
        with target.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=columns, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(message_rows)
        counts[message_type] = len(message_rows)

    parm_rows = rows.get("PARM", [])
    if parm_rows:
        target = args.output / "parameter_readback.csv"
        columns = ["Name", "Value", "Default"]
        with target.open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=columns)
            writer.writeheader()
            for row in parm_rows:
                writer.writerow({key: row.get(key, "") for key in columns})

    summary = {
        "source": str(args.input),
        "message_counts": counts,
        "export_pass": bool(rows.get("ATT") and rows.get("RCIN") and rows.get("RCOU")),
    }
    (args.output / "dataflash_export_summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary))
    return 0 if summary["export_pass"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
