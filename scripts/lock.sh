#!/bin/bash

# Configuration
echo "🔒 Project Locker"
echo "================="

# Prompt for password securely
# Keep prompt simple to avoid confusion
while true; do
    read -s -p "Enter Password to Lock: " PASSWORD
    echo ""
    read -s -p "Confirm Password: " PASSWORD_CONFIRM
    echo ""
    if [ "$PASSWORD" = "$PASSWORD_CONFIRM" ]; then
        if [ -z "$PASSWORD" ]; then
            echo "⚠️  Password cannot be empty."
            continue
        fi
        break
    else
        echo "❌ Passwords do not match. Please try again."
    fi
done

ARCHIVE_NAME="GapLess.enc"

# Files and Directories to Encrypt
# Explicitly listing to avoid deleting lock/unlock scripts prematurely if logic fails,
# though we intend to preserve unlock.sh
TARGETS="lib assets web ios android tools pubspec.yaml pubspec.lock firebase.json generate_hazard_data.py optimize_geojson.py patch_sw.py README.md web_demo_launch.sh scripts"

echo "🔒 Starting Project Encryption..."

# 1. Create Encrypted Archive
# We exclude the archive itself and any hidden system files if necessary
# We include 'scripts' so lock.sh is saved for future use
tar -czf - $TARGETS 2>/dev/null | openssl enc -aes-256-cbc -salt -pbkdf2 -out "$ARCHIVE_NAME" -pass pass:"$PASSWORD"

if [ $? -eq 0 ]; then
    echo "✅ Encryption successful: $ARCHIVE_NAME created."
    
    # 2. Secure Deletion (Remove Source Files)
    echo "🗑️  Removing source files..."
    
    # Remove top-level files
    rm pubspec.yaml pubspec.lock firebase.json generate_hazard_data.py optimize_geojson.py patch_sw.py README.md web_demo_launch.sh
    
    # Remove directories
    rm -rf lib assets web ios android tools
    
    # Handle scripts directory: Keep unlock.sh, remove others (including this lock script logic on disk, but it's running in memory)
    # Actually, we backed up 'scripts' entirely. 
    # We want to keep 'scripts/unlock.sh' visible.
    # We can delete 'scripts' and recreate 'scripts/unlock.sh' or just delete contents.
    
    # Let's delete everything in scripts except unlock.sh
    # Find all files in scripts, grep inverted match unlock.sh, and delete
    find scripts -type f ! -name 'unlock.sh' -delete
    
    echo "🔒 Project Locked. Source code is hidden."
    echo "🔑 Password to unlock: $PASSWORD"
    echo "   (Keep this password safe!)"
else
    echo "❌ Encryption failed. No files were deleted."
    exit 1
fi
