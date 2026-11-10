# Hostname (asked for at the start). Runs before the SSH key step because
# the key's title on each forge includes it.
cur=$(hostnamectl --static 2>/dev/null)
if [[ $cur == "$FR_HOST" ]]; then
  echo "   hostname is already $FR_HOST"
  exit 0
fi
echo "   renaming ${cur:-(unset)} → $FR_HOST (sudo will ask for your password)"
sudo hostnamectl set-hostname "$FR_HOST" || exit 1
echo "   now: $(hostnamectl --static)"
