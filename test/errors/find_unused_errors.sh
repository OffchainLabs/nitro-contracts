#!/bin/bash

# Directory containing the Solidity files
DIR="../../src"

# Temporary file to store errors and their corresponding files
ERRORS_FILE=$(mktemp)
UNUSED_ERRORS_FILE=$(mktemp)

# Find all error definitions and store them in a temporary file along with filenames
grep -rHo "error\s\+\w\+\s*(" $DIR | awk -F':' '{print $1 ": " $2}' | awk '{gsub(/error /, ""); gsub(/\(/, ""); print}' | sort -u > $ERRORS_FILE

# Loop through each error to check if it is used
while IFS=: read -r file error; do
    # Normalize file and error output
    error=$(echo $error | xargs)
    file=$(echo $file | xargs)
    file=$(basename $file) # Get only the file name

    # Count occurrences of each error in 'revert' statements
    count=$(grep -roh "revert\s\+$error" $DIR | wc -l)

    # If count is 0, the error is defined but never used
    if [ "$count" -eq 0 ]; then
        echo "$error ($file)" >> $UNUSED_ERRORS_FILE
    fi
done < $ERRORS_FILE

# Print the list of unused errors
if [ -s $UNUSED_ERRORS_FILE ]; then
    echo "These errors are defined, but never used:\n"
    cat $UNUSED_ERRORS_FILE
else
    echo "All defined errors are used."
fi

# Remove the temporary files
rm $ERRORS_FILE
rm $UNUSED_ERRORS_FILE
