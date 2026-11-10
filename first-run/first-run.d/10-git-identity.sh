# Git identity (Omarchy: install/config/git.sh)
git config --global user.name  "$FR_NAME"
git config --global user.email "$FR_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase true
git config --global push.autoSetupRemote true
echo "   $(git config --global user.name) <$(git config --global user.email)>"
