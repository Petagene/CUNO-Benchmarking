#!/bin/bash

# BETA SCRIPT
# This script is not currently used by the benchmarks. 

# Set your EFS file system ID
efs_file_system_id="$1"

# Function to check EFS burst credit balance
check_burst_credits() {
    # Use AWS CLI to describe the file system
    result=$(aws --region us-east-2 --output json  cloudwatch get-metric-statistics --namespace AWS/EFS --metric-name BurstCreditBalance --statistics Minimum --period 3600 --dimensions Name=FileSystemId,Value=$efs_file_system_id --start-time "$(date --utc -d "1 hour ago" '+%Y-%m-%dT%H:%M:%S')" --end-time "$(date '+%Y-%m-%dT%H:%M:%S')")

    # Extract the burst credit balance from the JSON output
    burst_credit_balance=$(echo "$result" | jq -r '.Datapoints[0].Minimum')

    # Print the burst credit balance
    echo "EFS Burst Credit Balance: $burst_credit_balance"
}

# Call the function to check burst credit balance
check_burst_credits
