#!/bin/bash

# BETA SCRIPT
# This script is not used by the benchmarks.

# Check if both arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <file to read from> <duration in seconds>"
    exit 1
fi

# Set file path e.g. s3://mybucket/1_GB_FILE
file_path="$1"
# Set the duration to read for, in hours
duration_hours="$2"


# Set the duration for which the script should run (in seconds)
duration_seconds=$((duration_hours*60*60))

# Calculate the relevant times (SECONDS gives the number of seconds since the start of this bash session)
start_time=$SECONDS
end_time=$((SECONDS + duration_seconds))

# Run the loop until the specified duration_seconds has passed
while [[ $SECONDS -lt $end_time ]]; do
    time_running_seconds=$((SECONDS - start_time))
    remaining_seconds=$((end_time - SECONDS))
    
    echo -ne "Reading from $file_path... Time since start: $(date -d@$time_running_seconds -u +%H:%M:%S), Time remaining: $(date -d@$remaining_seconds -u +%H:%M:%S)\r"
    
    # Call the function to read from the local file
    dd if="$file_path" of=/dev/null bs=1M &> /dev/null
done

echo "Script completed."

