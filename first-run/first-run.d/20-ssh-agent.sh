# ssh-agent as a systemd user service (~/.config/systemd/user/ssh-agent.service),
# socket at $XDG_RUNTIME_DIR/ssh-agent.socket, exported to mango and to shells.
set -e
systemctl --user daemon-reload
systemctl --user enable --now ssh-agent.service >/dev/null

line='SSH_AUTH_SOCK=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket'
env=$HOME/.config/mango/env
if ! grep -q '^SSH_AUTH_SOCK=' "$env"; then
  printf '\n# ssh-agent user service (added by mango-first-run)\n%s\n' "$line" >> "$env"
fi
if ! grep -q 'ssh-agent.socket' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# ssh-agent user service (added by mango-first-run)\nexport %s\n' "$line" >> "$HOME/.bashrc"
fi

for _ in 1 2 3 4 5; do [[ -S $SSH_AUTH_SOCK ]] && break; sleep 0.3; done
[[ -S $SSH_AUTH_SOCK ]] || { echo "   agent socket missing: $SSH_AUTH_SOCK"; exit 1; }
echo "   agent running at $SSH_AUTH_SOCK"
