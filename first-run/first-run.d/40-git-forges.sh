# Add the public key to Codeberg, GitHub and GitLab, then verify over SSH.
# The key goes on the clipboard and the forge's "add key" page opens in the
# browser; paste, save, come back and press Enter. Already-working forges
# are skipped, so re-running only does what's missing.
pub=$(cat "$FR_KEY.pub") || exit 1
title="${FR_HOST:-$(hostname)}-$(date +%Y-%m-%d)"

forges=(
  "Codeberg|codeberg.org|https://codeberg.org/user/settings/keys"
  "GitHub|github.com|https://github.com/settings/ssh/new"
  "GitLab|gitlab.com|https://gitlab.com/-/user_settings/ssh_keys"
)

check() {
  ssh -T -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
      "git@$1" 2>&1 </dev/null | grep -Eiq 'successfully authenticated|welcome to gitlab'
}

rc=0
for f in "${forges[@]}"; do
  IFS='|' read -r name host url <<<"$f"
  if check "$host"; then echo "   $name: already set up ✓"; continue; fi

  printf '%s' "$pub" | wl-copy
  echo "   $name: key copied to clipboard — opening $url"
  echo "          paste it as the key, title: $title"
  xdg-open "$url" >/dev/null 2>&1 &
  while :; do
    read -rp "          press Enter once saved (s = skip) " ans
    [[ $ans == s ]] && { echo "          skipped"; rc=1; break; }
    if check "$host"; then echo "   $name: authenticated ✓"; break; fi
    echo "          not authenticating yet — check it saved, then Enter again"
  done
done
wl-copy --clear 2>/dev/null
exit $rc
