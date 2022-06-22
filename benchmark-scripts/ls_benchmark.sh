#!/bin/bash

BUCKET=test_bucket
REMOTE_DIRECTORY=test_directory
REMOTE_PREFIX=s3://
LOCAL_DIRECTORY=local_test
TEST_OUTPUT=test_results.txt
REPEATS=2

cleanup() {
    rm -rf "$LOCAL_DIRECTORY/src"
    rm -rf "$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src"
}
create_source_directories() {
    mkdir -p $LOCAL_DIRECTORY/src
}

clear_cache() {
    sudo sync; sudo sh -c "/usr/bin/echo 3 > /proc/sys/vm/drop_caches"
}

setup_source_files() {
    echo "    -- Preparing local" | tee -a $TEST_OUTPUT
    for i in {0..10000}
    do
        random_string=$(cat /proc/sys/kernel/random/uuid | sed 's/[-]//g' | head -c 20; echo;)
        dd if=/dev/urandom of="$LOCAL_DIRECTORY/src/$random_string" count=1024 bs=1
    done
    echo "    -- Uploading to cloud" | tee -a $TEST_OUTPUT
    cp -r $LOCAL_DIRECTORY/src $REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src
}

ls_remote() {
    ls $REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src
}


echo "-- Cleaning up test directory --" | tee -a $TEST_OUTPUT
cleanup 

echo "-- Creating test directories --" | tee -a $TEST_OUTPUT
create_source_directories

echo "-- Setup test files --" | tee -a $TEST_OUTPUT
setup_source_files

echo "-- Run Cloud Tests --" | tee -a $TEST_OUTPUT
echo "---------------------------LARGE FILES LOCAL TO REMOTE--------------------------------" | tee -a $TEST_OUTPUT
i=0
sum=0
while [[ "${i}" -lt "${REPEATS}" ]]; do
    clear_cache
    start=$(date +%s.%N)
    ls_remote
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration"  | tee -a $TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${duration}" | bc -l | awk '{printf("%.5f",$1)}')
done
average_time=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
echo "Results - Average (Gbps): $average_time"  | tee -a $TEST_OUTPUT
echo "------------------------------------------------------------------------------------" | tee -a $TEST_OUTPUT