#!/bin/bash
# App Bundle Cleanup Script
# Removes unnecessary files that should not ship in production

set -e

PROJECT_DIR="/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
cd "$PROJECT_DIR"

echo "🧹 Starting app bundle cleanup..."
echo ""

# Create backup directory
BACKUP_DIR="$PROJECT_DIR/bundle-cleanup-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo "📦 Backup directory: $BACKUP_DIR"
echo ""

# Function to safely remove files
safe_remove() {
    local pattern="$1"
    local description="$2"

    echo "🔍 Finding: $description"
    files=$(find AMENAPP -type f -name "$pattern" 2>/dev/null || true)

    if [ -z "$files" ]; then
        echo "   ✅ No files found"
    else
        count=$(echo "$files" | wc -l | tr -d ' ')
        echo "   📋 Found $count files"

        # Backup files
        while IFS= read -r file; do
            if [ -f "$file" ]; then
                backup_path="$BACKUP_DIR/$(dirname "$file")"
                mkdir -p "$backup_path"
                cp "$file" "$backup_path/"
                rm "$file"
                echo "   ❌ Removed: $file"
            fi
        done <<< "$files"
    fi
    echo ""
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 1: Remove non-runtime files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Remove markdown documentation
safe_remove "*.md" "Markdown documentation files"

# Remove JavaScript files
safe_remove "*.js" "JavaScript files"

# Remove Firebase rules files
safe_remove "*.rules" "Firebase security rules"

# Remove JSON config files (except asset catalogs)
echo "🔍 Finding: JSON config files (excluding asset catalogs)"
json_files=$(find AMENAPP -type f -name "*.json" ! -path "*/Assets.xcassets/*" ! -path "*/AppIcon.appiconset/*" 2>/dev/null || true)
if [ -z "$json_files" ]; then
    echo "   ✅ No config JSON files found"
else
    count=$(echo "$json_files" | wc -l | tr -d ' ')
    echo "   📋 Found $count files"
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            backup_path="$BACKUP_DIR/$(dirname "$file")"
            mkdir -p "$backup_path"
            cp "$file" "$backup_path/"
            rm "$file"
            echo "   ❌ Removed: $file"
        fi
    done <<< "$json_files"
fi
echo ""

# Remove backup files
safe_remove "*.bak" "Backup files"
safe_remove "*.swift.bak" "Swift backup files"

# Remove shell scripts
safe_remove "*.sh" "Shell scripts"

# Remove Dockerfiles
safe_remove "Dockerfile*" "Docker files"

# Remove TypeScript config
safe_remove "tsconfig.json" "TypeScript config"

# Remove ESLint config
safe_remove ".eslintrc*" "ESLint config"

# Remove package.json files
safe_remove "package.json" "NPM package files"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 2: Remove backup directories"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Remove firestore-rules-backups directory
if [ -d "AMENAPP/firestore-rules-backups" ]; then
    echo "📁 Backing up and removing: firestore-rules-backups/"
    cp -R "AMENAPP/firestore-rules-backups" "$BACKUP_DIR/"
    rm -rf "AMENAPP/firestore-rules-backups"
    echo "   ❌ Removed directory"
else
    echo "   ✅ Directory not found"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "PHASE 3: Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Calculate backup size
backup_size=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
echo "✅ Cleanup complete!"
echo "📦 Backup created: $BACKUP_DIR"
echo "💾 Backup size: $backup_size"
echo ""
echo "⚠️  NEXT STEPS IN XCODE:"
echo "   1. Open AMENAPP.xcodeproj in Xcode"
echo "   2. Select AMENAPP target → Build Phases"
echo "   3. Expand 'Copy Bundle Resources'"
echo "   4. Remove any remaining non-asset files"
echo "   5. Clean Build Folder (Cmd+Shift+K)"
echo "   6. Archive the app"
echo ""
echo "🔍 Files that should remain in Copy Bundle Resources:"
echo "   ✅ Assets.xcassets (asset catalog)"
echo "   ✅ GoogleService-Info.plist"
echo "   ✅ Any localization .strings files"
echo "   ✅ Required runtime plists"
echo ""
echo "❌ Files to remove from Copy Bundle Resources:"
echo "   ❌ Any .md, .js, .json, .rules, .sh files"
echo "   ❌ Any source code or documentation"
echo "   ❌ Any backup files"
echo ""
