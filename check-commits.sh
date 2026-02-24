#!/bin/bash
# Crypto Watch - Check for new commits on tracked repos

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/state.json"
REPOS_FILE="$SCRIPT_DIR/repos.json"

# Initialize state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "{}" > "$STATE_FILE"
fi

# Read current state
STATE=$(cat "$STATE_FILE")

# Track updates
UPDATES=""

# Process each repo
while IFS= read -r repo; do
    NAME=$(echo "$repo" | jq -r '.name')
    OWNER=$(echo "$repo" | jq -r '.owner')
    REPO=$(echo "$repo" | jq -r '.repo')
    BRANCH=$(echo "$repo" | jq -r '.branch')
    
    # Get latest commit from GitHub API (follow redirects)
    RESPONSE=$(curl -sL "https://api.github.com/repos/$OWNER/$REPO/commits/$BRANCH")
    
    LATEST_SHA=$(echo "$RESPONSE" | jq -r '.sha // empty')
    COMMIT_MSG=$(echo "$RESPONSE" | jq -r '.commit.message // empty' | head -1 | cut -c1-80)
    COMMIT_DATE=$(echo "$RESPONSE" | jq -r '.commit.committer.date // empty')
    AUTHOR=$(echo "$RESPONSE" | jq -r '.commit.author.name // empty')
    
    if [ -z "$LATEST_SHA" ]; then
        echo "Failed to fetch $NAME ($OWNER/$REPO)"
        continue
    fi
    
    # Get stored SHA
    STORED_SHA=$(echo "$STATE" | jq -r ".[\"$OWNER/$REPO\"] // empty")
    
    if [ "$STORED_SHA" != "$LATEST_SHA" ]; then
        if [ -n "$STORED_SHA" ]; then
            # There's a new commit (not first run)
            UPDATES="$UPDATES\n🔔 **$NAME** ($OWNER/$REPO)\n   └ \`${LATEST_SHA:0:7}\` $COMMIT_MSG\n   └ by $AUTHOR at $COMMIT_DATE\n"
        fi
        # Update state
        STATE=$(echo "$STATE" | jq ". + {\"$OWNER/$REPO\": \"$LATEST_SHA\"}")
    fi
    
    # Rate limit - be nice to GitHub
    sleep 1
done < <(jq -c '.repos[]' "$REPOS_FILE")

# Save updated state
echo "$STATE" > "$STATE_FILE"

# Notify if there are updates
if [ -n "$UPDATES" ]; then
    MESSAGE="📦 **Crypto Watch - New Commits Detected**"$'\n'"$UPDATES"
    echo -e "$MESSAGE"
    # Send directly to Discord channel
    clawdbot message send --channel discord --to "channel:1465329866357608707" --message "$MESSAGE" 2>/dev/null || \
    clawdbot system event --text "$MESSAGE" --mode now
else
    echo "No new commits detected."
fi
