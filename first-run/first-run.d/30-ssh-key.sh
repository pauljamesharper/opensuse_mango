# Ed25519 key + ~/.ssh/config so the agent picks it up on first use.
set -e
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

if [[ -f $FR_KEY ]]; then
  echo "   key already exists: $FR_KEY (keeping it)"
else
  echo "   Creating $FR_KEY. Choose a passphrase (recommended) — you'll"
  echo "   type it once per login; the agent remembers it after that."
  ssh-keygen -t ed25519 -a 100 -C "$FR_EMAIL" -f "$FR_KEY"
fi

cfg=$HOME/.ssh/config
if ! grep -q 'AddKeysToAgent' "$cfg" 2>/dev/null; then
  cat >> "$cfg" <<EOF
Host *
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
EOF
  chmod 600 "$cfg"
fi

ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$FR_KEY.pub" | awk '{print $2}')" || ssh-add "$FR_KEY"
echo "   $(ssh-keygen -lf "$FR_KEY.pub")"
