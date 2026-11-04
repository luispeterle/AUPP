---
name: deploy-linux
description: Compiles the Linux release of AUPP, installs it (AUPP_INSTALL_DIR in private/build.env, by default ~/.local/opt/aupp) and registers it in the app launcher. Use when the user asks to deploy, compile or update the app on the computer.
---

# Skill: deploy-linux

Run `scripts/deploy-linux.sh` from the repository root, in the background (the build takes a few minutes), and wait for "Instalado em".

- Close the app first if it is running from that folder, and never leave it open alongside a debug session: both use the same database.
- If a folder sync takes the install folder to another computer, it only needs `registrar.sh` from that folder run once, for the launcher and icon.
- Never install into `~/Documents/aupp`: that folder holds the database.
- Report the build result and whether the `.desktop` file was written. Do not open the app or drive the user's screen to check it.
