#!/bin/bash

# BETA SCRIPT
# This script cannot guarantee that CloudWatch will correctly capture the requests made. Therefore, multiple runs of this script may be necessary to get numbers. We also cannot guarantee that at the end of this script all requests have been counted and are being returned by CloudWatch.

# Parameters for benchmark-scripts/cloudwatch_capture_s3_requests.sh
CLOUDWATCH_BUCKET_NAME=petaplay       #required
CLOUDWATCH_REGION=eu-west-2       #required
CLOUDWATCH_BUCKET_DIRECTORY=abdullah-benchmark       #required
CLOUDWATCH_METRIC_FILTER_NAME=cuno-small-copy-new       #required, max char limit 64
CLOUDWATCH_S3_TASK_COMMAND="cuno run cp /cloudstore/100.MiB s3://petaplay/abdullah-benchmark/100.MiB"        #required, e.g. "cuno run ls -R s3://bucket/directory" (with quotes)
CLOUDWATCH_NUM_FULL_RETRIES=2 # required. Sometimes CloudWatch fails to capture the requests made, so try again if 0 requests get reported. 

# All Bucket metrics configurations can be found at https://s3.console.aws.amazon.com/s3/bucket/<bucket>/metrics/bucket_metrics/filters (subbing in the bucket) 

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>/dev/null && pwd)
source ${SCRIPT_DIR}/../parameters.sh || die "Failed to source `${SCRIPT_DIR}/../parameters.sh`. Please ensure that the file is in the original directory and that the user '`whoami`' has sufficient privileges."

[[ -z "$CLOUDWATCH_BUCKET_NAME" ]] && echo "The CLOUDWATCH_BUCKET_NAME env variable must be set to the AWS S3 Bucket" && exit 1
[[ -z "$CLOUDWATCH_REGION" ]] && echo "The CLOUDWATCH_REGION env variable must be set to the same region as the AWS S3 Bucket" && exit 1
[[ -z "$CLOUDWATCH_BUCKET_DIRECTORY" ]] && echo "The CLOUDWATCH_BUCKET_DIRECTORY must be set to a path on the bucket at or parent to the path the CLOUDWATCH_S3_TASK_COMMAND is run on (acts as a filter)" && exit 1
[[ -z "$CLOUDWATCH_METRIC_FILTER_NAME" ]] && echo "The CLOUDWATCH_METRIC_FILTER_NAME env variable should be set to a descriptive name for the cloudwatch metric we will add. (Viewable on the S3 console: navigate to the bucket, switch to \"Metrics\" tab, click \"View additional charts\", Switch to the \"Request metrics\" tab.)"
[[ -z "$CLOUDWATCH_S3_TASK_COMMAND" ]] && echo "The CLOUDWATCH_S3_TASK_COMMAND env variable needs to be set to a command for which the S3 requests should be measured." && exit 1 
[[ -z "$CLOUDWATCH_NUM_FULL_RETRIES" || $CLOUDWATCH_NUM_FULL_RETRIES -lt 1 ]] && echo "The CLOUDWATCH_NUM_FULL_RETRIES env variable needs to be set to >= 1 otherwise the task won't be run at all." && exit 1

# Internal only: count up with CLOUDWATCH_TRIES
CLOUDWATCH_TRIES_MADE="${CLOUDWATCH_TRIES_MADE:-1}"

echo "Try: $CLOUDWATCH_TRIES_MADE/$CLOUDWATCH_NUM_FULL_RETRIES"

# Exit handler from https://unix.stackexchange.com/a/322213
cleanup() {
    err=$?

    # Delete the created configuration
    set -x 
    aws s3api delete-bucket-metrics-configuration --bucket "$CLOUDWATCH_BUCKET_NAME" --id "$CLOUDWATCH_METRIC_FILTER_NAME"
    set +x

    trap '' EXIT INT TERM
    exit $err 
}
sig_cleanup() {
    trap '' EXIT # some shells will call EXIT after the INT handler
    false # sets $?
    cleanup
}
trap cleanup EXIT
trap sig_cleanup INT QUIT TERM

# Will parse the outputs of a series of aws cloudwatch --metric-name ... calls, and spit them out as rows appropriate for a CSV table with columns Metric,Statistic,Value,Unit
# Arg 1: the json output/s of a aws cloudwatch call, splittable by line
parse_cloudwatch_json_api_outputs_into_csv() {
    while IFS= read -r line; do
        if [[ "$line" == *"Label"* ]]; then 
            # after :, then in between the first and second " 
            current_label=$(echo "$line" | awk -F':' '{print $2}' | awk -F'"' '{print $2}' | tr -d '[:blank:]')
        elif [[ "$line" == *"Sum"* ]]; then 
            current_statistic="Sum"
            # after the :, then before the ,
            current_value=$(echo "$line" | awk -F':' '{print $2}' | awk -F',' '{print $1}' | tr -d '[:blank:]')
        elif [[ "$line" == *"Average"* ]]; then 
            current_statistic="Average"
            # after the :, then before the ,
            current_value=$(echo "$line" | awk -F':' '{print $2}' | awk -F',' '{print $1}' | tr -d '[:blank:]')
        elif [[ "$line" == *"Unit"* ]]; then
            # after the :, then in between the first and second " 
            current_unit=$(echo "$line" | awk -F':' '{print $2}' | awk -F'"' '{print $2}' | tr -d '[:blank:]')
            # Unit is last, so spit it out
            echo "$current_label,$current_statistic,$current_value,$current_unit"
        elif [[ "$line" == *"\"Datapoints\": []"* ]]; then
            echo "$current_label,,0,"
        fi
    done <<< "$1"
}

# Sets up a bucket metrics configuration filtered on the bucket, to the prefix.
set -x
aws s3api put-bucket-metrics-configuration --bucket "$CLOUDWATCH_BUCKET_NAME" --id "$CLOUDWATCH_METRIC_FILTER_NAME" --metrics-configuration "{\"Id\":\"$CLOUDWATCH_METRIC_FILTER_NAME\", \"Filter\":{\"Prefix\":\"$CLOUDWATCH_BUCKET_DIRECTORY\"}}"
set +x

# Sleep so that cloudwatch has a chance to register our new filter 
sleep 3m

# You can also choose a start time in the past like this:
# --start-time "$(date --utc -d "1 hour ago" '+%Y-%m-%dT%H:%M:%S')"
start_time="$(date '+%Y-%m-%dT%H:%M:%S')"
START_SECONDS=$SECONDS

# Do the task we want to measure the number of requests 
set -x
bash -c "$CLOUDWATCH_S3_TASK_COMMAND"
set +x

# Each loop takes 1 minute, so how many minutes do you want to wait before giving up?
# Results don't always show up on Cloudwatch. In those cases, we have a retry mechanism (see CLOUDWATCH_NUM_FULL_RETRIES). 15 minutes should be enough for them to show up and converge
MAX_LOOPS=15
loop_index=0
# This will contain the latest returned API result for the sum of  "AllRequests" metric. This is expected to be non-zero for the command run. Otherwise the loop will loop until MAX_LOOPS
output=""
# The output value from the previous loop. This helps test for convergence.
previous_output=""
# This will contain output for metrics that may be expected to be empty for the task so can't be conditioned upon.
all_other_metrics=""

# Loop until the output == previous_output or we hit max loops
# Set the "period" to the whole time between starting the task and now otherwise we don't get results consistently
while [[ $loop_index -lt $MAX_LOOPS ]] && [[ -z $output || "$output" == *"\"Datapoints\": []"* || "$output" != "$previous_output" ]] ; do 
    # Sleep for 1 second to always ensure end_time > start_time (for very short commands) and thus avoid errors 
    sleep 1s
    end_time="$(date '+%Y-%m-%dT%H:%M:%S')"
    duration_seconds=$((SECONDS - START_SECONDS))
    # Periods can only be a multiple of 60 once big enough
    duration_as_period=$((60 *  (duration_seconds/60) + 60)); 

    # The request metrics are all detailed here https://github.com/awsdocs/amazon-s3-developer-guide/blob/master/doc_source/cloudwatch-monitoring.md
    # Get "AllRequests" value for the period that it took to run
    previous_output=$output
    set -x 
    output="$(for REQUEST_NAME in AllRequests ; do aws --region $CLOUDWATCH_REGION cloudwatch  get-metric-statistics --namespace AWS/S3 --metric-name $REQUEST_NAME --start-time "$start_time" --end-time "$end_time" --period "$duration_as_period" --dimensions "Name=BucketName,Value=$CLOUDWATCH_BUCKET_NAME" "Name=FilterId,Value=$CLOUDWATCH_METRIC_FILTER_NAME" --statistics Sum ; printf "\n" ; done)"
    set +x
    all_other_metrics="$(for REQUEST_NAME in GetRequests PutRequests DeleteRequests HeadRequests PostRequests SelectRequests  ListRequests  4xxErrors 5xxErrors ; do aws --region $CLOUDWATCH_REGION cloudwatch  get-metric-statistics --namespace AWS/S3 --metric-name $REQUEST_NAME --start-time "$start_time" --end-time "$end_time" --period "$duration_as_period" --dimensions "Name=BucketName,Value=$CLOUDWATCH_BUCKET_NAME" "Name=FilterId,Value=$CLOUDWATCH_METRIC_FILTER_NAME" --statistics Sum ; printf "\n" ; done ; for REQUEST_NAME in FirstByteLatency TotalRequestLatency SelectScannedBytes SelectReturnedBytes BytesDownloaded BytesUploaded ; do aws --region $CLOUDWATCH_REGION cloudwatch  get-metric-statistics --namespace AWS/S3 --metric-name $REQUEST_NAME --start-time "$start_time" --end-time "$end_time" --period "$duration_as_period" --dimensions "Name=BucketName,Value=$CLOUDWATCH_BUCKET_NAME" "Name=FilterId,Value=$CLOUDWATCH_METRIC_FILTER_NAME" --statistics Average ; printf "\n" ; done )"
    
    sleep 1m
    loop_index=$((loop_index + 1))
done 

# If we got to the end of the waiting for results and still nothing, then decrement the retry allowance and retry the whole script
if [[ $loop_index -ge $MAX_LOOPS && "$output" == *"\"Datapoints\": []"* ]] ; then 
    export CLOUDWATCH_TRIES_MADE=$((CLOUDWATCH_TRIES_MADE + 1))
    [[ $CLOUDWATCH_TRIES_MADE -ge $CLOUDWATCH_NUM_FULL_RETRIES ]] && echo "Out of tries. Sorry, CloudWatch capture of S3 requests is not guaranteed." && exit 1
    exec "$SCRIPT_DIR/$(basename "$0")" "$@"
else
    echo "==========================="
    echo "Metric,Statistic,Value,Unit"
    parse_cloudwatch_json_api_outputs_into_csv "$output"
    parse_cloudwatch_json_api_outputs_into_csv "$all_other_metrics"
    echo "==========================="
fi
