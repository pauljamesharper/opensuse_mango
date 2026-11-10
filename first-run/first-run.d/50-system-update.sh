# Full Tumbleweed update. Interactive on purpose: zypper dup can ask about
# package conflicts, and you're sitting at the terminal anyway.
set -e
echo "   sudo zypper dup (sudo may ask for your password)"
sudo zypper refresh
sudo zypper dup

if ! zypper needs-rebooting >/dev/null 2>&1; then
  echo "   the update touched the kernel or core libraries — reboot when you're done"
  notify-send -u critical "Reboot needed" "zypper dup updated core packages; reboot to finish."
fi
