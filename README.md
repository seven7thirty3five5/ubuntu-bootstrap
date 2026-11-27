# ubuntu-bootstrap

One command turns a fresh Ubuntu 26.04 VPS into `kurtis-ubuntu-vps`, a dev
machine reached over Tailscale.

## First, once: the tailnet policy

The VPS is the hub of your tailnet. It joins as `tag:hub`, and
[`tailnet/policy.hujson`](tailnet/policy.hujson) sets up hub and spoke: your
devices can reach the hub on every port and Tailscale SSH in as `dev`, the hub
can't reach your devices, and your devices can't reach each other.

Before the first run, open the **Access controls** page of the Tailscale admin
console and replace the policy there with the contents of
`tailnet/policy.hujson`. You do this once: it is tailnet setup, not VPS setup,
and only an admin can change the policy, so nothing on the VPS can do it.
Until the policy is in place, Tailscale refuses `tag:hub`, and the bootstrap
stops at its Tailscale step and tells you to paste it, before it changes
OpenSSH.

## Run it

As root on the new VPS, over SSH or in the provider's web console:

```sh
curl -fsSL https://raw.githubusercontent.com/seven7thirty3five5/ubuntu-bootstrap/main/bootstrap.sh | sh
```

The script is plain POSIX `sh`. It numbers its nine steps as it goes, marks
what it did with ✓ (grey when it was already done) and says which step
stopped if something fails.

It stops to ask you for these:

1. **A password for `dev`.** You use it for remote desktop and the provider's
   web console.
2. **The Tailscale sign-in.** Open the URL it prints, or scan the QR code with
   your iPhone, and approve the machine. It joins as `tag:hub`.
3. **The GitHub sign-in.** Press Enter, then open `github.com/login/device` on
   any device and enter the code. git pushes over HTTPS with that sign-in, so
   the VPS needs no SSH key for GitHub.
4. **The coding agents' sign-ins,** one after another, each with its own
   instructions on screen: Claude Code (a URL, then paste the code back),
   Codex (a device code), Antigravity (Google OAuth, then paste the code back)
   and Pi (`/login` in its own window).

Ctrl-C skips a GitHub or agent sign-in without stopping the run. The end of
the run lists what you skipped, and running the command again asks only for
those. When it finishes, OpenSSH is off, the firewall only lets Tailscale in,
and root's SSH key is deleted. The SSH session you ran it from stays open
until you exit it. Once everything is signed in, running the command again
changes nothing.

## What you get

- The hostname `kurtis-ubuntu-vps`, which is also its Tailscale name.
- An account `dev` with passwordless sudo, a password, fish as its login shell,
  and mise in `~/.local/bin`. root keeps bash.
- Tailscale as `tag:hub`, with Tailscale SSH and auto-update. Being tagged, its
  key doesn't expire, and the policy's SSH rule is `accept`, so SSH never stops
  to ask for a browser re-approval. OpenSSH is stopped, disabled and masked,
  and ufw blocks all incoming traffic except over `tailscale0` and Tailscale's
  UDP port 41641.
- Remote desktop: Xfce through xrdp and xorgxrdp, Firefox from Mozilla's APT
  repository, the libraries Electron needs, and Xvfb for headless tests.
- Your CLI tools from mise: atuin, bat, btop, duf, dust, eza, fd, fzf, gh
  (with the gh-dash and gh-stack extensions), jq, lazydocker, lazygit, Node
  LTS, ripgrep, starship, yazi, yq and zoxide, plus the
  [fresh](https://github.com/sinelaw/fresh) editor as `EDITOR`.
  build-essential, git and unzip come from apt.
- The coding agents, also from mise: Claude Code (`claude`), Codex (`codex`),
  the Antigravity CLI (`agy`) and Pi (`pi`). mise updates them with the other
  tools, so their own auto-updaters are off.
- fish 4 from the fish project's PPA, with your config from
  [`dotfiles/.config/fish`](dotfiles/.config/fish): Catppuccin Mocha,
  starship, fzf, atuin and zoxide. `~/.config/fish` links to that directory.
- Dotfiles from [`dotfiles/`](dotfiles), higher file-watcher limits, Ubuntu's
  unattended security updates.

[`bootstrap.sh`](bootstrap.sh) does what has to happen before mise can run:
the hostname, `dev`, the Tailscale sign-in and installing mise. Then it runs
`mise bootstrap --adopt seven7thirty3five5/ubuntu-bootstrap`, which clones this
repository to `~/.config/mise` as dev's global mise config and applies
[`config.toml`](config.toml). After that come the sign-ins that need the
installed tools: GitHub and the coding agents. Last, it deletes root's SSH key.

## Connect

From any device in your tailnet:

```sh
ssh dev@kurtis-ubuntu-vps
```

For the desktop, point an RDP client, such as Microsoft's Windows App, at
`kurtis-ubuntu-vps` and log in as `dev` with your password.

## Day to day

`~/.config/mise` is a Git checkout of this repository.

- **Apply changes you pushed from elsewhere:** `mise bootstrap --update`.
- **Change the machine:** edit `~/.config/mise/config.toml`, run
  `mise bootstrap`, then commit and push from `~/.config/mise`.
- **Add a dotfile:** `mise dot add ~/.tmux.conf` moves the file into
  `dotfiles/`, links it back and adds it to `config.toml`. Commit and push.
- **Edit a dotfile:** `~/.bash_aliases` and `~/.config/fish` link into
  `dotfiles/`, so an edit there is already a change in the repository. Commit
  and push it.
- **Upgrade apt packages, tools and coding agents:** `mise bootstrap --upgrade`.
  mise itself updates with `mise self-update`, and the gh extensions with
  `gh extension upgrade --all`.
- **Settings for this machine only** go in `~/.config/mise/config.local.toml`,
  which Git ignores.
- **Sign in again** without the whole bootstrap: `gh auth login --web`,
  `claude auth login`, `codex login --device-auth`, `agy` (it asks when signed
  out) or `/login` in `pi`.

## Recovery

- **Tailscale SSH doesn't let you in:** open the provider's web console and log
  in as `dev` with your password. `tailscale status` shows what's wrong, and
  this signs the machine in again:

  ```sh
  sudo tailscale up --ssh --hostname=kurtis-ubuntu-vps --advertise-tags=tag:hub --force-reauth
  ```

- **Run the bootstrap again:** as root in the console with the command above,
  or as `dev` with `sudo`:

  ```sh
  sudo sh -c "$(curl -fsSL https://raw.githubusercontent.com/seven7thirty3five5/ubuntu-bootstrap/main/bootstrap.sh)"
  ```

  Not `curl … | sudo sh`: when sudo's input is a pipe, Ubuntu's sudo-rs stops
  programs that change terminal settings, so a password prompt would hang.

  If a run fails partway, fix the cause and run it again. Each step checks what
  is already done.

## Notes

- If an older machine in your tailnet already has the name, Tailscale calls
  this one `kurtis-ubuntu-vps-1`. The script warns you. Remove the old machine
  in the admin console and rename this one.
- Docker publishes container ports past ufw, so a published port is open to the
  internet whatever the firewall says.
- fish's Catppuccin Mocha theme colors the text only. For the background, set
  your terminal app's own Catppuccin Mocha color scheme.
- Codex's device code sign-in is off until you turn it on in ChatGPT's
  security settings.
- The Antigravity CLI keeps its Google sign-in in a desktop keyring. If it
  doesn't stay signed in over SSH, its docs offer a Gemini API key or a Google
  Cloud project instead.
