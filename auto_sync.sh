#!/usr/bin/env bash
set -e

cd /Users/soumyachakraborty/Documents/OpenDots

LOCKFILE="/tmp/aether_sync.lock"
if ! mkdir "$LOCKFILE" 2>/dev/null; then
    echo "[AutoSync] Another sync process is already running. Skipping."
    exit 0
fi
trap 'rm -rf "$LOCKFILE"' EXIT

SYNC_DIR="/tmp/aether_sync_repo"

if [ ! -d "$SYNC_DIR/.git" ]; then
    rm -rf "$SYNC_DIR"
    git clone https://github.com/soumyachk101/AETHER.git "$SYNC_DIR"
fi

cd "$SYNC_DIR"
git fetch origin main
git checkout main
git reset --hard origin/main
git clean -fd

# Exclude build/dist/target directories from git sync
rsync -a --delete \
    --exclude 'target' \
    --exclude 'dist' \
    --exclude 'build' \
    --exclude '.build' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    /Users/soumyachakraborty/Documents/OpenDots/AETHER-rust/ "$SYNC_DIR/AETHER-rust/"

rsync -a --delete \
    --exclude 'target' \
    --exclude 'dist' \
    --exclude 'build' \
    --exclude '.build' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    /Users/soumyachakraborty/Documents/OpenDots/AETHER-swift/ "$SYNC_DIR/AETHER-swift/"

rsync -a --delete \
    --exclude 'node_modules' \
    --exclude 'dist' \
    --exclude 'data' \
    --exclude '.env' \
    --exclude '.env.local' \
    --exclude '.env.*.local' \
    --exclude '.git' \
    --exclude '.DS_Store' \
    /Users/soumyachakraborty/Documents/OpenDots/AETHER-web/ "$SYNC_DIR/AETHER-web/"

if [ -d "/Users/soumyachakraborty/Documents/OpenDots/docs" ]; then
    rsync -a --delete /Users/soumyachakraborty/Documents/OpenDots/docs/ "$SYNC_DIR/docs/"
fi

cp -f /Users/soumyachakraborty/Documents/OpenDots/.gitignore "$SYNC_DIR/.gitignore"
[ -f "/Users/soumyachakraborty/Documents/OpenDots/README.md" ] && cp -f /Users/soumyachakraborty/Documents/OpenDots/README.md "$SYNC_DIR/README.md"
[ -f "/Users/soumyachakraborty/Documents/OpenDots/LICENSE" ] && cp -f /Users/soumyachakraborty/Documents/OpenDots/LICENSE "$SYNC_DIR/LICENSE"

git add -A

if ! git diff --staged --quiet; then
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    BRANCH_NAME="sync/$(date "+%Y%m%d-%H%M%S")"
    
    CHANGES_SUMMARY=$(git diff --staged --stat | head -n 40)
    COUNT_FILES=$(git diff --staged --name-only | wc -l | tr -d ' ')

    echo "[AutoSync] Detected changes in $COUNT_FILES files at $TIMESTAMP."
    
    git checkout -b "$BRANCH_NAME"
    
    COMMIT_MSG="feat/sync: update AETHER modules ($TIMESTAMP)

Files changed: $COUNT_FILES files

Summary:
$CHANGES_SUMMARY"

    git commit -m "$COMMIT_MSG"
    
    echo "[AutoSync] Pushing branch $BRANCH_NAME..."
    git push -u origin "$BRANCH_NAME"
    
    echo "[AutoSync] Creating Pull Request..."
    PR_URL=$(gh pr create \
        --repo soumyachk101/AETHER \
        --base main \
        --head "$BRANCH_NAME" \
        --title "Sync: Update AETHER modules ($TIMESTAMP)" \
        --body "Automated sync for changes in \`AETHER\`.

### Summary ($COUNT_FILES files):
\`\`\`
$CHANGES_SUMMARY
\`\`\`")
    
    echo "[AutoSync] PR created: $PR_URL"
    
    echo "[AutoSync] Merging Pull Request..."
    gh pr merge "$BRANCH_NAME" --repo soumyachk101/AETHER --squash --delete-branch
    
    echo "[AutoSync] Successfully merged $PR_URL to main."
else
    echo "[AutoSync] No changes detected in AETHER modules."
fi
