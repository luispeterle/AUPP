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

# With the override, these files name private packages: git must not pick them
# up. scripts/export-public.sh regenerates them clean.
generated="pubspec.lock lib/generated_plugin_registrant.dart
  linux/flutter/generated_plugin_registrant.cc linux/flutter/generated_plugins.cmake
  macos/Flutter/GeneratedPluginRegistrant.swift
  windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake"
rm -f pubspec_overrides.yaml
if [ -e private/pubspec_overrides.yaml ]; then
  ln -s private/pubspec_overrides.yaml pubspec_overrides.yaml
  git update-index --skip-worktree $generated 2>/dev/null || true
  git config core.hooksPath .githooks
else
  git update-index --no-skip-worktree $generated 2>/dev/null || true
fi
