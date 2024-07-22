#!/bin/bash

# Directory containing the Solidity files
DIR="../../src"

# Temporary file to store errors and their corresponding files
ERRORS_FILE=$(mktemp)

# Find all error definitions and store them in a temporary file along with filenames
grep -rho "error\s\+\w\+\s*(" $DIR | awk '{gsub(/error /, ""); gsub(/\(/, ""); print FILENAME ": " $0}' | sort -u > $ERRORS_FILE

# Loop through each error to check if it is used
while IFS=: read -r file error; do
    # Normalize file and error output
    error=$(echo $error | xargs)
    file=$(echo $file | xargs)

    # Count occurrences of each error in 'revert' statements
    count=$(grep -roh "revert\s\+$error" $DIR | wc -l)

    # If count is 0, the error is defined but never used
    if [ "$count" -eq 0 ]; then
        echo "Error '$error' is defined but never used in file $file"
    fi
done < $ERRORS_FILE

# Remove the temporary file
rm $ERRORS_FILE
