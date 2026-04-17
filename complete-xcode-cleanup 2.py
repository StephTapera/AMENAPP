#!/usr/bin/env python3
"""
Complete Xcode Bundle Cleanup Script
Automatically removes non-runtime files from Copy Bundle Resources phase
"""

import os
import re
import shutil
from datetime import datetime

PROJECT_DIR = "/Users/stephtapera/Desktop/AMEN/AMENAPP copy"
PBXPROJ_PATH = f"{PROJECT_DIR}/AMENAPP.xcodeproj/project.pbxproj"

def backup_pbxproj():
    """Backup the project.pbxproj file"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = f"{PBXPROJ_PATH}.backup_{timestamp}"
    shutil.copy2(PBXPROJ_PATH, backup_path)
    print(f"✅ Backed up project.pbxproj to: {backup_path}")
    return backup_path

def read_pbxproj():
    """Read the project.pbxproj file"""
    with open(PBXPROJ_PATH, 'r', encoding='utf-8') as f:
        return f.read()

def write_pbxproj(content):
    """Write the project.pbxproj file"""
    with open(PBXPROJ_PATH, 'w', encoding='utf-8') as f:
        f.write(content)

def find_resources_phase_section(content):
    """Find the PBXResourcesBuildPhase section"""
    # Find the section that contains "Copy Bundle Resources"
    pattern = r'(/\* Resources \*/ = \{[^}]+isa = PBXResourcesBuildPhase;[^}]+files = \([^)]+\);[^}]+\};)'
    matches = re.findall(pattern, content, re.DOTALL)
    return matches

def get_file_references(content):
    """Extract all file references from PBXFileReference section"""
    file_refs = {}

    # Pattern to match file references
    pattern = r'([A-F0-9]{24}) /\* ([^*]+) \*/ = \{[^}]*path = ([^;]+);[^}]*\};'

    for match in re.finditer(pattern, content, re.DOTALL):
        ref_id = match.group(1)
        name = match.group(2).strip()
        path = match.group(3).strip().strip('"')
        file_refs[ref_id] = {'name': name, 'path': path}

    return file_refs

def should_remove_file(filename):
    """Determine if a file should be removed from bundle resources"""
    # File extensions to remove
    bad_extensions = [
        '.md', '.js', '.json', '.rules', '.sh', '.bak',
        '.txt', '.log', '.rtf', '.pdf', '.docx', '.xlsx'
    ]

    # Files to keep
    keep_files = [
        'Contents.json',  # Asset catalog metadata
        'GoogleService-Info.plist',
        'Info.plist'
    ]

    # Check if it's in the keep list
    if any(filename.endswith(keep) for keep in keep_files):
        return False

    # Check if it should be removed
    if any(filename.endswith(ext) for ext in bad_extensions):
        return True

    # Remove if it's in a backup or config directory
    bad_patterns = [
        'firestore-rules-backups',
        'Backend/',
        'functions/',
        'genkit'
    ]

    return any(pattern in filename for pattern in bad_patterns)

def clean_resources_phase(content):
    """Remove unwanted files from Copy Bundle Resources phase"""
    print("\n🔍 Analyzing project.pbxproj...")

    file_refs = get_file_references(content)
    print(f"📋 Found {len(file_refs)} file references")

    # Find all resource file references in the build phase
    # Pattern: UUID /* filename in Resources */
    resource_pattern = r'([A-F0-9]{24}) /\* ([^*]+) in Resources \*/'

    removed_count = 0
    lines_to_remove = []

    for match in re.finditer(resource_pattern, content):
        file_id = match.group(1)
        filename = match.group(2).strip()

        if should_remove_file(filename):
            # Mark this entire line for removal
            line_start = content.rfind('\n', 0, match.start()) + 1
            line_end = content.find('\n', match.end())
            if line_end == -1:
                line_end = len(content)

            line = content[line_start:line_end]
            lines_to_remove.append(line)
            removed_count += 1
            print(f"   ❌ Marking for removal: {filename}")

    # Remove the lines
    for line in lines_to_remove:
        content = content.replace(line + '\n', '')
        content = content.replace(line + ',\n', '')

    print(f"\n✅ Marked {removed_count} files for removal from Copy Bundle Resources")
    return content

def main():
    print("🧹 Starting Complete Xcode Bundle Cleanup")
    print("=" * 50)

    # Step 1: Backup
    backup_path = backup_pbxproj()

    # Step 2: Read project file
    print("\n📖 Reading project.pbxproj...")
    content = read_pbxproj()
    original_size = len(content)

    # Step 3: Clean resources phase
    cleaned_content = clean_resources_phase(content)

    # Step 4: Write back
    if cleaned_content != content:
        print("\n💾 Writing cleaned project.pbxproj...")
        write_pbxproj(cleaned_content)
        new_size = len(cleaned_content)
        saved_bytes = original_size - new_size
        print(f"✅ Saved {saved_bytes} bytes from project file")
    else:
        print("\n✅ No changes needed - project file is clean!")

    print("\n" + "=" * 50)
    print("🎉 Cleanup Complete!")
    print("\n📋 Next Steps:")
    print("   1. Open Xcode: open AMENAPP.xcodeproj")
    print("   2. Clean Build Folder: Product → Clean Build Folder (⌘⇧K)")
    print("   3. Archive: Product → Archive")
    print("   4. Verify size reduction in Archives")
    print("\n💾 Backup saved at:")
    print(f"   {backup_path}")

if __name__ == "__main__":
    main()
