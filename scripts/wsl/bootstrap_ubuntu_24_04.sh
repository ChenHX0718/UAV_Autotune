#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
    echo "bootstrap_ubuntu_24_04.sh must run as root." >&2
    exit 2
fi

target_user="${1:?Usage: bootstrap_ubuntu_24_04.sh <non-root-user>}"
if [[ "$target_user" == "root" || ! "$target_user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "A valid non-root Linux user name is required." >&2
    exit 3
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    sudo ca-certificates curl wget git git-lfs \
    python3 python3-dev python3-pip python3-venv python3-setuptools \
    gcc g++ make pkg-config lsb-release locales rsync unzip xz-utils \
    build-essential ccache ninja-build

if ! id -u "$target_user" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --groups sudo "$target_user"
else
    usermod --append --groups sudo "$target_user"
fi

install -m 0644 "$script_dir/config/wsl.conf" /etc/wsl.conf
printf '\n[user]\ndefault=%s\n' "$target_user" >> /etc/wsl.conf
install -d -m 0755 /etc/update-manager
install -m 0644 "$script_dir/config/release-upgrades" /etc/update-manager/release-upgrades

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

printf 'UBUNTU_BOOTSTRAP_PASS\n'
printf 'ubuntu=%s\n' "$(. /etc/os-release && printf '%s' "$PRETTY_NAME")"
printf 'python=%s\n' "$(python3 --version 2>&1)"
printf 'gcc=%s\n' "$(gcc --version | head -n1)"
printf 'git=%s\n' "$(git --version)"
printf 'default_user=%s\n' "$target_user"
printf 'sudo_policy=interactive_only; automation uses explicit wsl -u root for package installation\n'
printf 'release_upgrade=%s\n' "$(awk -F= '/^Prompt=/{print $2}' /etc/update-manager/release-upgrades)"
