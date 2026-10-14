# Codex VDI relay

The GTS profile runs a user service, `codex-vdi-proxy.service`, that exposes an
HTTP proxy at `127.0.0.1:18181` and forwards through the reverse SOCKS tunnel at
`127.0.0.1:18080`. The managed adapter uses a different port from the original
manual GOST process, so enabling it does not interrupt that process or its Codex
sessions. No global shell or Codex proxy configuration is changed.

## Windows setup

On `jedmonstone-vdi.striketechnologies.com`, run this in PowerShell and leave
the terminal open. If the original SSH tunnel is still running, keep using it
or close it before starting this command; both use port `18080` on Linux.

```powershell
ssh -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 127.0.0.1:18080 jedmonstone@jedmonstone-dev.striketechnologies.com
```

No Windows service, scheduled task, script installation, password storage, or
administrator access is needed. The command uses your existing SSH
authentication and known host key. A quiet terminal means the tunnel is running.
Press Ctrl+C to stop it. If the connection drops, rerun the command.

The VDI must remain awake, online, and logged on, with this terminal running.

## Linux use

Apply the GTS Home Manager configuration. The adapter starts with the user
service manager, and the launcher also starts it if needed. No root service or
user lingering is required.

GOST and curl are installed by the GTS profile. No `nix run` is needed. Until
the new configuration files are tracked in Git, rebuild using the filesystem
flake so Nix includes them:

```sh
nh home switch "path:$HOME/nix-config"
```

```sh
codex-vdi
codex-vdi resume
codex-vdi resume <session-id>
systemctl --user status codex-vdi-proxy.service
journalctl --user -u codex-vdi-proxy.service -n 30
```

New `engine-ticket` tmux sessions launch `codex-vdi` in their Codex window.
Existing sessions are reattached unchanged; exit their old Codex process and
run `codex-vdi resume` to move them to the relay.

The launcher checks an HTTPS connection through the relay without sending
account credentials. A public ChatGPT page may return a Cloudflare challenge;
that is not treated as a dead tunnel. Codex performs its own authenticated
requests afterwards. A missing tunnel, failed CONNECT, or TLS error stops the
launcher with a diagnostic instead of silently falling back to direct access.

Proxy variables apply to this Codex process and its children, not your shell.
The launcher uses `--no-daemon` so an existing unproxied background server is
not reused. Its shell-environment filters remove proxy variables from ordinary
commands launched by Codex. Localhost and company hostnames bypass the proxy;
existing `NO_PROXY` entries are preserved, but a global `*` is rejected.
The filters follow the
[official Codex shell-environment configuration](https://learn.chatgpt.com/docs/config-file/config-advanced#shell-environment-policy).

Plain `codex` remains unchanged, including the existing shared-daemon behavior.
This launcher does not promise shared-daemon features. MCP servers have their
own environment/transport settings; the shell-command filters are not an
isolation boundary for every plugin or subprocess.

Once the Windows tunnel and `codex-vdi` work, the old manual Linux GOST terminal
can be closed. Existing Codex sessions using its port `18081` should first be
closed or relaunched with `codex-vdi`.

## Security boundary

Use this relay only where company policy permits it. TLS verification and SSH
host-key checking remain enabled. Neither listener is exposed on a non-loopback
interface, but TCP localhost ports are **not private to a user on a shared Linux
host**: other local users may connect to the unauthenticated relay. It does not
expose your Codex credentials, but it does expose a network route through your
VDI. If that is unacceptable under your organization's policy, do not enable the
Windows tunnel; use an IT-managed proxy or a properly user-isolated alternative.
