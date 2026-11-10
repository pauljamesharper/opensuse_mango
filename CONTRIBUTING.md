# Contributing

**To this openSUSE port:** open an issue or a pull request at
https://github.com/pauljamesharper/opensuse_mango.

**To the setup itself** (the bar, the configs, the scripts): those are
Drew's, and changes that aren't openSUSE-specific belong upstream at
https://justaguy.dev/butter/mango. His instructions:
https://justaguy.dev/drew/.profile/src/branch/main/CONTRIBUTING.md

Quick version for upstream (sign in with Codeberg or GitHub, add an SSH key, then):

    git clone ssh://forgejo@justaguy.dev/butter/mango.git
    cd mango
    git switch -c my-change
    # make your change, commit it
    git push origin HEAD:refs/for/main -o topic=my-change -o title="Short description"

Push again with the same topic to update the pull request.
