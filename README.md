# ubuntu-bootstrap

One command turns a fresh Ubuntu 26.04 VPS into `kurtis-ubuntu-vps`, a dev
machine reached over Tailscale.

## Run it

As root on the new VPS, over SSH or in the provider's web console:

```sh
curl -fsSL https://raw.githubusercontent.com/seven7thirty3five5/ubuntu-bootstrap/main/bootstrap.sh | sh
```

The script is plain POSIX `sh`. It numbers its seven steps as it goes, marks
what it did with ✓ (grey when it was already done) and says which step
stopped if something fails.

It stops twice to ask you something:

1. **A password for `dev`.** You use it for remote desktop and the provider's
   web console.
2. **The Tailscale sign-in.** Open the URL it prints, or scan the QR code with
   your iPhone, and approve the machine.

The rest is automatic. When it finishes, OpenSSH is off, the firewall only lets
Tailscale in, and root's SSH key is deleted. The SSH session you ran it from
stays open until you exit it. Running the command again changes nothing.

## What you get

- The hostname `kurtis-ubuntu-vps`, which is also its Tailscale name.
- An account `dev` with passwordless sudo, a password, and mise in
  `~/.local/bin`.
- Tailscale with Tailscale SSH and auto-update. OpenSSH is stopped, disabled
  and masked, and ufw blocks all incoming traffic except over `tailscale0` and
  Tailscale's UDP port 41641.
- Remote desktop: Xfce through xrdp and xorgxrdp, Firefox from Mozilla's APT
  repository, the libraries Electron needs, and Xvfb for headless tests.
- Node LTS and `gh` from mise. build-essential, git, unzip and vim from apt.
- fish 4 from the fish project's PPA, with your config from
  [`dotfiles/.config/fish`](dotfiles/.config/fish): Catppuccin Mocha,
  starship, fzf, zoxide and atuin, all four from mise. `~/.config/fish` links
  to that directory. dev's login shell stays bash; type `fish` to start it.
- Dotfiles from [`dotfiles/`](dotfiles), higher file-watcher limits, Ubuntu's
  unattended security updates.

[`bootstrap.sh`](bootstrap.sh) does what has to happen before mise can run:
the hostname, `dev`, the Tailscale sign-in and installing mise. Then it runs
`mise bootstrap --adopt seven7thirty3five5/ubuntu-bootstrap`, which clones this
repository to `~/.config/mise` as dev's global mise config and applies
[`config.toml`](config.toml). Last, it deletes root's SSH key.

## Connect

From any device in your tailnet:

```sh
ssh dev@kurtis-ubuntu-vps
```

For the desktop, point an RDP client, such as Microsoft's Windows App, at
`kurtis-ubuntu-vps` and log in as `dev` with your password.

Under Tailscale's default policy, SSH runs in check mode: now and then it asks
you to confirm in the browser that it's you.

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
- **Upgrade apt packages and tools:** `mise bootstrap --upgrade`. mise itself
  updates with `mise self-update`.
- **Settings for this machine only** go in `~/.config/mise/config.local.toml`,
  which Git ignores.

To push from the VPS, sign in to GitHub once with `gh auth login`.

## Recovery

- **Tailscale SSH doesn't let you in:** open the provider's web console and log
  in as `dev` with your password. `tailscale status` shows what's wrong, and
  this signs the machine in again:

  ```sh
  sudo tailscale up --ssh --hostname=kurtis-ubuntu-vps --force-reauth
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

- Tailscale's sign-in for this machine expires after 180 days. To keep it
  signed in, disable key expiry for it on the Machines page of the Tailscale
  admin console. Otherwise, sign it in again from the provider's console with
  the command under Recovery.
- Keep the machine untagged. The default tailnet policy lets you SSH to your
  own devices, and a tagged machine no longer counts as yours.
- If an older machine in your tailnet already has the name, Tailscale calls
  this one `kurtis-ubuntu-vps-1`. The script warns you. Remove the old machine
  in the admin console and rename this one.
- Docker publishes container ports past ufw, so a published port is open to the
  internet whatever the firewall says.
- fish's Catppuccin Mocha theme colors the text only. For the background, set
  your terminal app's own Catppuccin Mocha color scheme.
