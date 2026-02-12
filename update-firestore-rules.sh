#!/bin/bash

# ============================================================================
# Firestore Rules Auto-Update Script
# ============================================================================
# This script ensures that all Firestore rule changes are automatically
# applied to the correct rules file: AMENAPP/firestore 18.rules
#
# Usage:
#   ./update-firestore-rules.sh [source-file]
#
# If no source file is provided, it will use AMENAPP/firestore 18.rules
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project paths
PROJECT_ROOT="/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
MASTER_RULES_FILE="$PROJECT_ROOT/AMENAPP/firestore 18.rules"
BACKUP_DIR="$PROJECT_ROOT/AMENAPP/firestore-rules-backups"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create backup
create_backup() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/firestore_18_rules_backup_$timestamp.rules"

    if [ -f "$MASTER_RULES_FILE" ]; then
        cp "$MASTER_RULES_FILE" "$backup_file"
        print_success "Backup created: $backup_file"

        # Keep only last 10 backups
        cd "$BACKUP_DIR"
        ls -t firestore_18_rules_backup_*.rules | tail -n +11 | xargs -I {} rm -- {}
    else
        print_warning "Master rules file not found, skipping backup"
    fi
}

# Function to validate rules file
validate_rules() {
    local file=$1

    print_info "Validating rules file..."

    # Check if file exists
    if [ ! -f "$file" ]; then
        print_error "Rules file does not exist: $file"
        return 1
    fi

    # Check if file has content
    if [ ! -s "$file" ]; then
        print_error "Rules file is empty: $file"
        return 1
    fi

    # Check for basic Firestore rules structure
    if ! grep -q "rules_version = '2';" "$file"; then
        print_error "Rules file missing rules_version declaration"
        return 1
    fi

    if ! grep -q "service cloud.firestore" "$file"; then
        print_error "Rules file missing service declaration"
        return 1
    fi

    print_success "Rules file validation passed"
    return 0
}

# Function to update master rules file
update_master_rules() {
    local source_file=${1:-"$MASTER_RULES_FILE"}

    print_info "Starting Firestore rules update process..."
    print_info "Master rules file: $MASTER_RULES_FILE"

    # Create backup before updating
    create_backup

    # Validate source file if different from master
    if [ "$source_file" != "$MASTER_RULES_FILE" ]; then
        if validate_rules "$source_file"; then
            print_info "Copying rules from $source_file to master..."
            cp "$source_file" "$MASTER_RULES_FILE"
            print_success "Master rules file updated"
        else
            print_error "Source file validation failed, aborting update"
            return 1
        fi
    fi

    # Validate final master file
    if validate_rules "$MASTER_RULES_FILE"; then
        print_success "✓ Firestore rules are ready for deployment"
        print_info "To deploy: firebase deploy --only firestore:rules"
        return 0
    else
        print_error "Master rules file validation failed"
        return 1
    fi
}

# Main execution
main() {
    echo ""
    print_info "═══════════════════════════════════════════════════════"
    print_info "  Firestore Rules Auto-Update System"
    print_info "═══════════════════════════════════════════════════════"
    echo ""

    if [ $# -eq 0 ]; then
        print_info "No source file provided, validating master rules file..."
        update_master_rules
    else
        print_info "Source file: $1"
        update_master_rules "$1"
    fi

    echo ""
    print_info "═══════════════════════════════════════════════════════"
    print_success "Update process complete!"
    print_info "═══════════════════════════════════════════════════════"
    echo ""
}

# Run main function
main "$@"
