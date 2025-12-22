# Panda Home Station Repositories

This repository uses Google's repo tool to manage multiple Git projects.

## Initial Setup

1. Install repo tool (if not already installed):
   ```
   curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.local/bin/repo
   chmod a+x ~/.local/bin/repo
   ```

2. Initialize the repo:
   ```
   git clone http://gitlab.pandamicro.com/panda-home-station/phs.git
   cd phs
   repo init . -m repos/default.xml
   ```

3. Sync all repositories:
   ```
   repo sync
   ```

## Common Commands

- Sync latest changes: `repo sync`
- Start a new branch: `repo start <branch_name> --all`
- Upload changes: `repo upload`