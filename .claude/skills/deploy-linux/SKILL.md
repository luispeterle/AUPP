---
name: deploy-linux
description: Compiles the Linux release of AUPP, installs it (AUPP_INSTALL_DIR in private/build.env, by default ~/.local/opt/aupp) and registers it in the app launcher. Use when the user asks to deploy, compile or update the app on the computer.
---

# Skill: deploy-linux

Run `scripts/deploy-linux.sh` from the repository root, in the background (the build takes a few minutes), and wait for "Instalado em".

- The script waits only for the installed app (running from that folder) to close. A debug session running from the repo does not block it: compile and install with the debug open, never stop the debug for this.
- If a folder sync takes the install folder to another computer, it only needs `registrar.sh` from that folder run once, for the launcher and icon.
- Never install into `~/Documents/aupp`: that folder holds the database.
- Report the build result and whether the `.desktop` file was written. Do not open the app or drive the user's screen to check it.
