#!/bin/bash

TARGET_PATH="$GITHUB_WORKSPACE/users-api/users"

if [ -d "$TARGET_PATH" ]; then
    echo "Success: The required folder exists at '$TARGET_PATH'."
else
    echo "Error: Required folder '$TARGET_PATH' is missing!"
    exit 1 
fi