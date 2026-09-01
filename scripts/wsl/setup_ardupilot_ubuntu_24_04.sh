#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"

if [[ "$mode" == "system" ]]; then
    target_user="${2:?Target non-root user is required}"
    if [[ "$EUID" -ne 0 ]]; then
        echo "The system phase must run as WSL root." >&2
        exit 2
    fi

    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
        echo "Expected Ubuntu 24.04, found ${PRETTY_NAME:-unknown}." >&2
        exit 3
    fi
    if [[ "$(awk -F= '/^Prompt=/{print $2}' /etc/update-manager/release-upgrades)" != "never" ]]; then
        echo "Ubuntu release upgrades must remain disabled." >&2
        exit 4
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install --assume-yes --no-install-recommends \
        astyle build-essential ccache g++ gawk git libffi-dev libssl-dev \
        libtool-bin libxml2-dev libxslt1-dev make pkg-config ppp \
        python3-dev python3-pexpect python3-pip python3-setuptools \
        python3.12-venv rsync screen valgrind wget zlib1g-dev
    usermod -a -G dialout "$target_user"
    printf 'ARDUPILOT_SYSTEM_ENV_PASS ubuntu=%s python=%s user=%s\n' \
        "$PRETTY_NAME" "$(python3 --version 2>&1)" "$target_user"
    exit 0
fi

if [[ "$mode" == "user" ]]; then
    repo="${2:?ArduPilot repository path is required}"
    expected_commit="${3:?Expected ArduPilot commit is required}"
    if [[ "$EUID" -eq 0 ]]; then
        echo "The Python environment phase must run as the normal WSL user." >&2
        exit 5
    fi
    actual_commit="$(git -C "$repo" rev-parse HEAD)"
    if [[ "$actual_commit" != "$expected_commit" ]]; then
        echo "ArduPilot commit mismatch: $actual_commit" >&2
        exit 6
    fi

    venv="$HOME/venv-ardupilot"
    if [[ ! -x "$venv/bin/python" ]]; then
        python3 -m venv --system-site-packages "$venv"
    fi
    # shellcheck disable=SC1091
    source "$venv/bin/activate"
    python -m pip install --upgrade pip packaging setuptools wheel
    python -m pip install --upgrade attrdict3
    python -m pip install --upgrade \
        future lxml pymavlink pyserial MAVProxy geocoder 'empy==3.3.4' \
        pexpect ptyprocess dronecan flake8 junitparser wsproto tabulate \
        pygame intelhex numpy pyparsing psutil pyyaml

    python - <<'PY'
import importlib.metadata as metadata
import pymavlink
import MAVProxy
import em

print("ARDUPILOT_PYTHON_ENV_PASS")
for package in ("pymavlink", "MAVProxy", "empy", "numpy"):
    print(f"{package}={metadata.version(package)}")
PY
    printf 'venv=%s\ncommit=%s\n' "$venv" "$actual_commit"
    exit 0
fi

echo "Usage: $0 system [user] | user <repo> <expected-commit>" >&2
exit 64
