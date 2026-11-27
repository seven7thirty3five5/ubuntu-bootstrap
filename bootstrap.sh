#!/bin/sh
# Turns a fresh Ubuntu 26.04 VPS into kurtis-ubuntu-vps. Run it as root on the VPS:
#
#   curl -fsSL https://raw.githubusercontent.com/seven7thirty3five5/ubuntu-bootstrap/main/bootstrap.sh | sh
#
# This script does only what has to happen before mise can run, plus the two
# steps whose order matters: Tailscale is signed in before mise turns OpenSSH
# off, and root's SSH key goes last. config.toml declares everything else, and
# `mise bootstrap` applies it. Every step is safe to repeat; a second run
# changes nothing.
#
# Plain POSIX sh, so it runs under dash, Ubuntu's /bin/sh.
set -eu

REPO=seven7thirty3five5/ubuntu-bootstrap
MACHINE=kurtis-ubuntu-vps
MISE_VERSION=v2026.11.14 # the mise release config.toml is built and tested against
MISE=/home/dev/.local/bin/mise
GH_SHIM=/home/dev/.local/share/mise/shims/gh
STEPS=9 # the number of steps in main
STEP=0
SKIPPED='' # sign-ins skipped this run

# Output ----------------------------------------------------------------------

# Colors only on a terminal, and never with NO_COLOR set (https://no-color.org).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
  ESC=$(printf '\033')
  BOLD="${ESC}[1m" DIM="${ESC}[2m" RED="${ESC}[31m" GREEN="${ESC}[32m"
  YELLOW="${ESC}[33m" BLUE="${ESC}[34m" RESET="${ESC}[0m"
else
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi

# Headings are 72 columns wide. The script doesn't ask the terminal for its
# width: run through `curl ... | sudo sh`, sudo-rs stops stty.
WIDTH=72

# A line of $1 box-drawing characters.
hr() {
  hr_line=''
  hr_left=$1
  while [ "$hr_left" -gt 0 ]; do
    hr_line="$hr_line─"
    hr_left=$((hr_left - 1))
  done
  printf '%s' "$hr_line"
}

# A full-width heading in color $1: "── TEXT ─────".
heading() { printf '\n%s%s── %s %s%s\n' "$BOLD" "$1" "$2" "$(hr $((WIDTH - 4 - ${#2})))" "$RESET"; }

step() {
  STEP=$((STEP + 1))
  STEP_TITLE=$1
  heading "$BLUE" "$STEP/$STEPS  $1"
}

ok() { printf '   %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }      # done just now
already() { printf '   %s✓ %s%s\n' "$DIM" "$*" "$RESET"; }   # was done before
doing() { printf '   %s→%s %s\n' "$BLUE" "$RESET" "$*"; }   # starting something slow
ask() { printf '   %s?%s %s%s%s\n' "$YELLOW" "$RESET" "$BOLD" "$*" "$RESET"; } # your turn
warn() { printf '   %s! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die() {
  printf '   %s✗ %s%s\n' "$RED" "$*" "$RESET" >&2
  exit 1
}

# Run a command with its output indented and dimmed under the step. The output
# goes through sed, so the command's exit status comes back on fd 4.
indented() {
  exec 3>&1
  indented_status=$({ {
    indented_rc=0
    "$@" </dev/null 2>&1 3>&- 4>&- || indented_rc=$?
    echo "$indented_rc" >&4
  } | sed "s/^/     $DIM/; s/\$/$RESET/" >&3; } 4>&1)
  exec 3>&-
  return "$indented_status"
}

# On failure or Ctrl-C, say which step stopped. Step 1 only checks, and its
# message says what to do.
on_exit() {
  exit_status=$?
  [ "$exit_status" -ne 0 ] && [ "$STEP" -gt 1 ] || return 0
  case $exit_status in
  130 | 143) next="Run the same command again to carry on" ;;
  *) next="Fix the cause above and run the same command again" ;;
  esac
  printf '\n%s%sStopped at step %s/%s, %s. %s: it skips what is already done.%s\n\n' \
    "$BOLD" "$RED" "$STEP" "$STEPS" "$STEP_TITLE" "$next" "$RESET" >&2
}

# Steps -----------------------------------------------------------------------

# Run a command as dev, from dev's home (dev can't read root's working directory).
# stdin is the script itself, so anything interactive reads the terminal instead.
as_dev() { (cd /home/dev && exec </dev/tty && sudo -u dev -H -- "$@"); }

# Run one of the tools config.toml installs, as dev.
dev_tool() { as_dev "$MISE" exec -- "$@"; }

# sign_in NAME CHECK HOW COMMAND...: unless the CHECK function says dev is
# signed in to NAME, explain HOW and run COMMAND as dev, then check again.
# Ctrl-C skips one sign-in instead of stopping the bootstrap. Skipped sign-ins
# are listed at the end, and the next run asks again.
sign_in() {
  sign_in_name=$1 sign_in_check=$2 sign_in_how=$3
  shift 3
  if "$sign_in_check"; then
    already "Signed in to $sign_in_name"
    return 0
  fi
  ask "$sign_in_how Ctrl-C skips it."
  trap : INT
  dev_tool "$@" || true
  trap 'exit 130' INT
  if "$sign_in_check"; then
    ok "Signed in to $sign_in_name"
  else
    printf '\n' # a skipped sign-in can leave the cursor after its prompt
    warn "Not signed in to $sign_in_name. The next run asks again."
    SKIPPED="${SKIPPED:+$SKIPPED, }$sign_in_name"
    return 1
  fi
}

signed_in_github() { dev_tool gh auth status --hostname github.com >/dev/null 2>&1; }
signed_in_claude() { dev_tool claude auth status >/dev/null 2>&1; }
signed_in_codex() { dev_tool codex login status >/dev/null 2>&1; }
signed_in_antigravity() { dev_tool agy models >/dev/null 2>&1; }
signed_in_pi() { dev_tool jq -e 'length > 0' /home/dev/.pi/agent/auth.json >/dev/null 2>&1; }

check() {
  step "Check this machine"
  [ "$(id -u)" -eq 0 ] || die "Run this as root."
  # os-release sets NAME, VERSION and more, so read it in a subshell.
  # shellcheck source=/dev/null
  release=$(. /etc/os-release && [ "$ID" = ubuntu ] && dpkg --compare-versions "$VERSION_ID" ge 26.04 && printf '%s' "$PRETTY_NAME") ||
    die "This needs Ubuntu 26.04 or newer."
  (exec </dev/tty) 2>/dev/null || die "This needs a terminal. Connect with 'ssh -t', or use the provider's console."
  ok "Root on $release, with a terminal for the prompts"
}

set_hostname() {
  step "Hostname"
  if [ "$(hostnamectl --static hostname)" = "$MACHINE" ]; then
    already "The hostname is $MACHINE"
  else
    hostnamectl set-hostname "$MACHINE"
    ok "Set the hostname to $MACHINE"
  fi
  # Otherwise cloud-init sets the provider's hostname again at the next boot.
  cfg=/etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
  if [ ! -d /etc/cloud/cloud.cfg.d ]; then
    return 0
  elif [ -e "$cfg" ]; then
    already "cloud-init keeps the hostname"
  else
    printf '%s\n' "# Written by bootstrap.sh: keep the hostname $MACHINE." "preserve_hostname: true" >"$cfg"
    ok "Told cloud-init to keep the hostname"
  fi
}

create_dev() {
  step "The dev account"
  if id dev >/dev/null 2>&1; then
    already "dev exists"
  else
    useradd --create-home --shell /bin/bash dev
    ok "Created dev"
  fi

  # On Ubuntu 26.04 the sudo command comes from the sudo-rs package, not the
  # sudo package, so check for the command.
  if ! command -v sudo >/dev/null; then
    doing "Installing sudo-rs"
    indented apt-get update -q
    indented env DEBIAN_FRONTEND=noninteractive apt-get install -y -q sudo-rs
    ok "Installed sudo-rs"
  fi

  sudo_rule="dev ALL=(ALL:ALL) NOPASSWD: ALL"
  if [ "$(cat /etc/sudoers.d/dev 2>/dev/null)" = "$sudo_rule" ]; then
    already "dev has passwordless sudo"
  else
    tmp=$(mktemp)
    printf '%s\n' "$sudo_rule" >"$tmp"
    visudo -c -f "$tmp" >/dev/null || die "visudo rejected the sudoers rule for dev."
    install -m 0440 "$tmp" /etc/sudoers.d/dev
    rm -f "$tmp"
    ok "Gave dev passwordless sudo"
  fi

  if [ "$(passwd -S dev | awk '{print $2}')" = P ]; then
    already "dev has a password"
  else
    ask "Choose a password for dev. You need it for remote desktop and the provider's console."
    until passwd dev </dev/tty; do warn "That didn't work. Try again."; done
    ok "Set dev's password"
  fi
}

setup_tailscale() {
  step "Tailscale"
  if command -v tailscale >/dev/null; then
    already "Tailscale is installed"
  else
    doing "Installing Tailscale with its official installer"
    tmp=$(mktemp)
    curl -fsSL -o "$tmp" https://tailscale.com/install.sh || die "Couldn't download Tailscale's installer."
    indented sh "$tmp"
    rm -f "$tmp"
    command -v tailscale >/dev/null || die "Tailscale's installer didn't install tailscale."
    ok "Installed Tailscale"
  fi

  if tailscale status >/dev/null 2>&1; then
    already "Signed in to Tailscale"
    settings_line=already
  else
    ask "Sign in to Tailscale: open the URL below or scan the QR code with your phone, then approve this machine."
    tailscale up --ssh --hostname="$MACHINE" --qr </dev/tty
    ok "Signed in to Tailscale"
    settings_line=ok
  fi
  # Also keeps Tailscale SSH on when the machine was already signed in, since
  # mise is about to turn OpenSSH off.
  tailscale set --ssh --auto-update
  tailscale status >/dev/null 2>&1 || die "Tailscale is not connected. Check 'tailscale status', then run this again."
  "$settings_line" "Tailscale SSH and auto-update are on"

  # Tailscale adds a suffix when an older machine in the tailnet has the name.
  TAILSCALE_NAME=$(tailscale status --json --peers=false | sed -n 's/^ *"DNSName": "\([^."]*\).*/\1/p' | head -n 1)
  if [ -n "$TAILSCALE_NAME" ] && [ "$TAILSCALE_NAME" != "$MACHINE" ]; then
    warn "Tailscale named this machine '$TAILSCALE_NAME' because another machine in your tailnet is already called '$MACHINE'. Remove that one in the Tailscale admin console and rename this one to '$MACHINE'. Until then, connect to '$TAILSCALE_NAME'."
  fi
}

install_mise() {
  step "mise"
  if [ -x "$MISE" ]; then
    already "mise is installed for dev"
  else
    doing "Installing mise $MISE_VERSION for dev"
    # No activation hint: config.toml sets up activation.
    indented as_dev sh -c "curl -fsSL https://mise.run | MISE_VERSION=$MISE_VERSION MISE_INSTALL_HELP=0 sh"
    [ -x "$MISE" ] || die "The mise installer failed."
    ok "Installed mise $MISE_VERSION in /home/dev/.local/bin"
  fi
}

apply_config() {
  step "Apply config.toml"
  # The first run clones this repository to ~/.config/mise as dev's global
  # config; later runs use that checkout as it is. Then mise applies config.toml.
  doing "Running mise bootstrap: packages, services, firewall, dotfiles and tools. This takes a while."
  as_dev "$MISE" bootstrap --adopt "$REPO" --yes
  ok "Applied config.toml"
}

sign_in_github() {
  step "GitHub"
  # git pushes and pulls over HTTPS with gh's sign-in, so the VPS needs no SSH
  # key for GitHub. These are the lines `gh auth setup-git` writes, but through
  # mise's shim, which keeps working when mise updates gh. Set before the
  # sign-in, they also keep `gh auth login` from asking about them.
  helper="!$GH_SHIM auth git-credential"
  if [ "$(as_dev git config --global --get-all credential.https://github.com.helper)" = "$(printf '\n%s' "$helper")" ] &&
    [ "$(as_dev git config --global --get-all credential.https://gist.github.com.helper)" = "$(printf '\n%s' "$helper")" ]; then
    already "git uses gh's sign-in for GitHub"
  else
    for host in github.com gist.github.com; do
      as_dev git config --global --replace-all "credential.https://$host.helper" ''
      as_dev git config --global --add "credential.https://$host.helper" "$helper"
    done
    ok "git uses gh's sign-in for GitHub, so no SSH key is needed"
  fi

  # No desktop keyring over SSH, so gh keeps its token in ~/.config/gh/hosts.yml.
  # GH_PATH lets gh recognize the helper above as its own; there is no browser.
  sign_in GitHub signed_in_github \
    "Sign in to GitHub: press Enter, then open the link on any device and enter the code." \
    env GH_PATH="$GH_SHIM" GH_BROWSER=true gh auth login --hostname github.com \
    --git-protocol https --web --scopes workflow --insecure-storage || true
}

sign_in_agents() {
  step "Coding agents"
  sign_in "Claude Code" signed_in_claude \
    "Sign in to Claude Code: open the URL below, sign in, and paste the code back here." \
    claude auth login || true
  sign_in Codex signed_in_codex \
    "Sign in to Codex: open the link below and enter the code. Device code sign-in has to be on in ChatGPT's security settings." \
    codex login --device-auth || true
  sign_in Antigravity signed_in_antigravity \
    "Sign in to Antigravity: choose Google OAuth, open the URL, paste the code back, then type /exit." \
    agy || true
  sign_in Pi signed_in_pi \
    "Sign in to Pi: type /login, pick a provider and sign in, then press Ctrl-D to quit." \
    pi || true
}

remove_root_key() {
  step "Root's SSH key"
  if [ -e /root/.ssh/authorized_keys ]; then
    rm -f /root/.ssh/authorized_keys
    ok "Deleted /root/.ssh/authorized_keys"
  else
    already "Root has no SSH key"
  fi
}

finish() {
  name=${TAILSCALE_NAME:-$MACHINE}
  secs=$(($(date +%s) - START))
  heading "$GREEN" "Done in $((secs / 60))m $((secs % 60))s"
  cat <<EOF

   This machine is $BOLD$MACHINE$RESET. From now on, connect over Tailscale:

     ${BOLD}ssh dev@$name$RESET
     Remote desktop (RDP): ${BOLD}$name$RESET, user dev, with the password you chose

   OpenSSH is off and root's SSH key is gone. This SSH session stays open
   until you exit it. If Tailscale ever locks you out, log in as dev on the
   provider's web console.

EOF
  if [ -n "$SKIPPED" ]; then
    warn "Not signed in yet: $SKIPPED. Run the same command again to sign in."
    printf '\n'
  fi
}

main() {
  trap on_exit EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  START=$(date +%s)
  printf '\n%s%s%s %s· bootstrap from github.com/%s%s\n' "$BOLD" "$MACHINE" "$RESET" "$DIM" "$REPO" "$RESET"
  printf '%sIt stops for a password for dev, then for sign-ins: Tailscale, GitHub and the coding agents.%s\n' "$DIM" "$RESET"

  check
  set_hostname
  create_dev
  setup_tailscale
  install_mise
  apply_config
  sign_in_github
  sign_in_agents
  remove_root_key
  finish
}

# Nothing above changes the machine, and sh has read the whole script by the
# time main runs, even though the script arrives through a pipe.
main "$@"
