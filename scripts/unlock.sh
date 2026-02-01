#!/bin/bash

ARCHIVE_NAME="GapLess.enc"

echo "🔓 Project Unlocker"
echo "==================="

if [ ! -f "$ARCHIVE_NAME" ]; then
    echo "❌ Error: $ARCHIVE_NAME not found."
    exit 1
fi

# Prompt for password securely
read -s -p "Enter Password to Decrypt: " INPUT_PASSWORD
echo ""

# Decrypt and Extract
# openssl return code will verify password correctness
openssl enc -d -aes-256-cbc -pbkdf2 -in "$ARCHIVE_NAME" -pass pass:"$INPUT_PASSWORD" 2>/dev/null | tar xzf -

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "✅ Decryption successful. Project restored."
    # Clean up the encrypted file? 
    # User might want to keep it, but usually unlock implies going back to work.
    # We'll keep it for now or user can delete it. 
    # Let's verify files exist
    if [ -d "lib" ]; then
        echo "📂 'lib' directory restored."
    fi
else
    echo "❌ Decryption failed. Wrong password or corrupted file."
    exit 1
fi
