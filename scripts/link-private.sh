#!/bin/sh
# Plugs private/ (ignored by git; a folder or a symlink to one) into this
# checkout. Without it this does nothing and the app builds as the public
# version. Run once after creating private/ here, and again whenever its
# contents change names.
#   private/pubspec_overrides.yaml  replaces packages/private_extensions
# Android signing reads private/android/key.properties directly.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [ -e private/vscode/launch.json ]; then
  mkdir -p .vscode
  ln -sfn ../private/vscode/launch.json .vscode/launch.json
fi

# With the override, pubspec.lock and the Linux plugin registrants name private
# packages; .gitignore keeps them out of git.
rm -f pubspec_overrides.yaml
if [ -e private/pubspec_overrides.yaml ]; then
  ln -s private/pubspec_overrides.yaml pubspec_overrides.yaml
  git config core.hooksPath .githooks
fi
