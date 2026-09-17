---
name: menubar-shell
description: Package, launch, authenticate, monitor, and stop the Phoenix release from the tray-only shell.
---

# Menubar Shell

- Shell owns: free port, bootstrap token (fd or 0600 file, never argv), child launch, READY parsing, tray menu (Cuckoding, About, Settings, Quit), status polling, login item, updates, termination ladder.
- Shell never contains workflow, provider, secret, or knowledge logic.
- Opening the UI uses single-use `/open` tokens; browser sessions are separate cookies.
- Quit hibernates or stops runs per policy before terminating the child.

Before completion: test crash before/after READY, token replay, unauthorized browser request, quit with running stages, and a clean-machine launch.
