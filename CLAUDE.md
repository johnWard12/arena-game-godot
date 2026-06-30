# Arena Game — Claude Instructions

## Git Workflow
- All work happens on the `dev` branch
- `main` is the stable branch — only updated via PR from `dev`
- At the end of a session (or when the user asks), commit any uncommitted changes to `dev`, push, and open a PR into `main`
- PR title should summarize the session's changes; body should bullet what changed and why

## Project
- Godot 4 project located at `godot_project/`
- Two playable classes: Duelist (melee) and Mage (ranged)
- GitHub repo: https://github.com/johnWard12/arena-game-godot
