#!/usr/bin/env bash
# Turns a fresh Ubuntu 26.04 VPS into kurtis-ubuntu-vps. Run it as root on the VPS:
#
#   curl -fsSL https://raw.githubusercontent.com/seven7thirty3five5/ubuntu-bootstrap/main/bootstrap.sh | bash
#
# This script does only what has to happen before mise can run, plus the two
# steps whose order matters: Tailscale is signed in before mise turns OpenSSH
# off, and root's SSH key goes last. config.toml declares everything else, and
# `mise bootstrap` applies it. Every step is safe to repeat; a second run
# changes nothing.
set -euo pipefail

REPO=seven7thirty3five5/ubuntu-bootstrap
MACHINE=kurtis-ubuntu-vps
MISE_VERSION=v2026.11.14 # the mise release config.toml is built and tested against
MISE=/home/dev/.local/bin/mise

say() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

# Run a command as dev, from dev's home (dev can't read root's working directory).
# stdin is the curl pipe, so anything interactive reads the terminal instead.
as_dev() { (cd /home/dev && exec </dev/tty && sudo -u dev -H -- "$@"); }

check() {
  [ "$(id -u)" -eq 0 ] || die "Run this as root."
  # os-release sets NAME, VERSION and more, so read it in a subshell.
  # shellcheck source=/dev/null
  if ! (. /etc/os-release && [ "$ID" = ubuntu ] && dpkg --compare-versions "$VERSION_ID" ge 26.04); then
    die "This needs Ubuntu 26.04 or newer."
  fi
  { : </dev/tty; } 2>/dev/null || die "This needs a terminal. Connect with 'ssh -t', or use the provider's console."
}

set_hostname() {
  if [ "$(hostnamectl --static hostname)" != "$MACHINE" ]; then
    hostnamectl set-hostname "$MACHINE"
    say "Hostname is now $MACHINE"
  fi
  # Otherwise cloud-init sets the provider's hostname again at the next boot.
  local cfg=/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
  if [ -d /etc/cloud/cloud.cfg.d ] && [ ! -e "$cfg" ]; then
    printf '%s\n' "# Written by bootstrap.sh: keep the hostname $MACHINE." "preserve_hostname: true" >"$cfg"
    say "Told cloud-init to keep the hostname"
  fi
}

create_dev() {
  if ! id dev >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash dev
    say "Created the dev account"
  fi

  # On Ubuntu 26.04 the sudo command comes from the sudo-rs package, not the
  # sudo package, so check for the command.
  if ! command -v sudo >/dev/null; then
    say "Installing sudo-rs"
    apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q sudo-rs
  fi

  local rule tmp
  rule="dev ALL=(ALL:ALL) NOPASSWD: ALL"
  if [ "$(cat /etc/sudoers.d/dev 2>/dev/null)" != "$rule" ]; then
    tmp=$(mktemp)
    printf '%s\n' "$rule" >"$tmp"
    visudo -c -f "$tmp" >/dev/null || die "visudo rejected the sudoers rule for dev."
    install -m 0440 "$tmp" /etc/sudoers.d/dev
    rm -f "$tmp"
    say "Gave dev passwordless sudo"
  fi

  if [ "$(passwd -S dev | awk '{print $2}')" != P ]; then
    say "Choose a password for dev. You need it for remote desktop and the provider's console."
    until passwd dev </dev/tty; do echo "Try again."; done
  fi
}

setup_tailscale() {
  if ! command -v tailscale >/dev/null; then
    say "Installing Tailscale"
    curl -fsSL https://tailscale.com/install.sh | sh
  fi

  if ! tailscale status >/dev/null 2>&1; then
    say "Sign in to Tailscale: open the URL or scan the QR code with your phone, then approve this machine."
    tailscale up --ssh --hostname="$MACHINE" --qr </dev/tty
  fi
  # Also keeps Tailscale SSH on when the machine was already signed in, since
  # mise is about to turn OpenSSH off.
  tailscale set --ssh --auto-update
  tailscale status >/dev/null 2>&1 || die "Tailscale is not connected. Check 'tailscale status', then run this again."

  # Tailscale adds a suffix when an older machine in the tailnet has the name.
  TAILSCALE_NAME=$(tailscale status --json --peers=false | sed -n 's/^ *"DNSName": "\([^."]*\).*/\1/p')
  if [ "$TAILSCALE_NAME" != "$MACHINE" ]; then
    warn "Tailscale named this machine '$TAILSCALE_NAME' because another machine in your tailnet is already called '$MACHINE'. Remove that one in the Tailscale admin console and rename this one to '$MACHINE'. Until then, connect to '$TAILSCALE_NAME'."
  fi
}

install_mise() {
  if [ ! -x "$MISE" ]; then
    say "Installing mise $MISE_VERSION for dev"
    # No activation hint: config.toml sets up activation.
    as_dev sh -c "curl -fsSL https://mise.run | MISE_VERSION=$MISE_VERSION MISE_INSTALL_HELP=0 sh"
    [ -x "$MISE" ] || die "The mise installer failed."
  fi
}

apply_config() {
  # The first run clones this repository to ~/.config/mise as dev's global
  # config; later runs use that checkout as it is. Then mise applies config.toml.
  say "Applying config.toml with mise bootstrap. This takes a while."
  as_dev "$MISE" bootstrap --adopt "$REPO" --yes
}

remove_root_key() {
  if [ -e /root/.ssh/authorized_keys ]; then
    rm -f /root/.ssh/authorized_keys
    say "Deleted /root/.ssh/authorized_keys"
  fi
}

finish() {
  local name=${TAILSCALE_NAME:-$MACHINE}
  cat <<EOF

==> Done. This machine is $MACHINE.

From now on, connect over Tailscale:
  ssh dev@$name
  Remote desktop (RDP): $name, user dev, with the password you chose

OpenSSH is off and root's SSH key is gone. This SSH session stays open until
you exit it. If Tailscale ever locks you out, log in as dev on the provider's
web console.
EOF
}

main() {
  check
  set_hostname
  create_dev
  setup_tailscale
  install_mise
  apply_config
  remove_root_key
  finish
}

# Everything above only defines functions, so bash has the whole script before
# anything runs, even though it arrives through a pipe.
main "$@"
