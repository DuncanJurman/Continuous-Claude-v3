  Step-by-step commands

  # 1. Fetch latest from upstream
  git fetch upstream

  # 2. Merge upstream into your current branch
  git merge upstream/main

  # 3. (Optional) Push the merged changes to your fork
  git push origin main

  # 4. Run the OPC update wizard to sync files to ~/.claude
  cd ~/tools/continuous-claude-v3/opc && uv run python -m scripts.setup.update

  Note: The update script runs git pull --ff-only which pulls from origin (your fork). Since you want to pull from upstream first, do steps 1-2 manually, then run step 4.

  If you have local uncommitted changes, you may need to commit or stash them first:
  git stash          # save local changes
  git fetch upstream
  git merge upstream/main
  git stash pop      # restore local changes