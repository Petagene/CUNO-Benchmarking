#!/bin/bash

BUCKET=test_bucket
REMOTE_DIRECTORY=test_directory
REMOTE_PREFIX=s3://
LOCAL_DIRECTORY=benchmark
TEST_OUTPUT=test_results.txt
REPEATS=2
TEST_FILE_SIZE_GiB=16



######################

warn() {
   echo -e "$*" | tee -a $TEST_OUTPUT
}

die() {
   warn "$*"
   exit 1
}

cleanup() {
    rm -rf "$LOCAL_DIRECTORY/src" || die "Failed to delete '$LOCAL_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$LOCAL_DIRECTORY/dst" || die "Failed to delete '$LOCAL_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst" || die "Failed to delete '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
    rm -rf "$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src" || die "Failed to delete '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
}

create_source_directories() {
    mkdir -p $LOCAL_DIRECTORY/src || die "Failed to create the local directory '$LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $LOCAL_DIRECTORY/dst || die "Failed to create the local directory '$LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst || die "Failed to create new directory '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst'. Make sure that your user '`whoami`' has sufficient permissions."
    mkdir -p $REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src || die "Failed to create new directory '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src'. Make sure that your user '`whoami`' has sufficient permissions."
}

test_setup() {
   [[ -z "$CUNO_LOADED" ]] && die "This benchmark requires CUNO to be loaded to run."
   echo "Using `cuno -V`"

   mount -l | awk '$5 == "tmpfs" {if (match('\"$PWD/$LOCAL_DIRECTORY\"', $3)) print $3}' | grep '.*' >/dev/null || die "The directory '$PWD/$LOCAL_DIRECTORY' isn't located in a ramdisk, which means that the performance will be bottlenecked by the local disk. You can create a ramdisk with the 'sudo mount -t tmpfs -o size=150G tmpfs </path/to/dir>' (ensure that you have usfficient RAM)."

   mkdir -p "$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY" || die "Failed to create '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/test_setup', make sure the bucket '$BUCKET' and the prefix '$REMOTE_PREFIX' are accessible."
   touch "$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/test_setup" || die "Failed to create a new file '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/test_setup', make sure the bucket '$BUCKET' and the prefix '$REMOTE_PREFIX' are correct."

   echo "-- Cleaning up test directory --" | tee -a $TEST_OUTPUT
   cleanup 

   echo "-- Creating test directories --" | tee -a $TEST_OUTPUT
   create_source_directories
}

clear_cache() {
    sudo sh -c "rm -rf /dev/shm/cuno* 2>/dev/null" || warn "NOTE: Failed to automatically clear local cuno cache." "You can manually clear this cache by running 'rm -rf /dev/shm/cuno*' with administrative privileges."
    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches 2>/dev/null" || warn "NOTE: Failed to automatically clear the kernel cache." "You can manually clear the cache by running 'echo 3 > /proc/sys/vm/drop_caches' with administrative privileges."
}

setup_source_files() {
    echo "    -- Preparing local" | tee -a $TEST_OUTPUT
    dd if=/dev/urandom of=$LOCAL_DIRECTORY/src/gen_file count=1048576 bs=$((1024*$TEST_FILE_SIZE_GiB)) || die "Failed to generate random file '$LOCAL_DIRECTORY/src/gen_file'. Please ensure that you have"
    mv $LOCAL_DIRECTORY/src/gen_file $LOCAL_DIRECTORY/src/test_file1 || die "Error moving file to '$LOCAL_DIRECTORY/src/test_file1'."
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file2 || die "Error copying file to '$LOCAL_DIRECTORY/src/test_file2'."
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file3 || die "Error copying file to '$LOCAL_DIRECTORY/src/test_file3'."
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file4 || die "Error copying file to '$LOCAL_DIRECTORY/src/test_file4'."
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file5 || die "Error copying file to '$LOCAL_DIRECTORY/src/test_file5'."
    echo "    -- Uploading to cloud" | tee -a $TEST_OUTPUT
    cp -r $LOCAL_DIRECTORY/src/* $REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src/. || die "Error uploading directory to '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTOry/src/'. Please ensure that you have access to the bucket '$BUCKET'. If this issue persists, contact CUNO support."
}

clear_dest_remote() {
    rm -rf "$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst" | tee -a $TEST_OUTPUT || die "Failed to delete remote directory '$REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst'. Is this error persists, contact CUNO support."
}

clear_dest_local() {
    rm -rf $LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT || die "Failed to clear local directory '$LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`'" || die "Failed to delete local directory '$LOCAL_DIRECTORY/dst'. Is this error persists, contact CUNO support."
}

copy_large_local_remote() {
    cp -r $LOCAL_DIRECTORY/src $REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT || die "Error during remote copy, aborting benchmark. If the error persists, please contact CUNO support."
}

copy_large_remote_local() {
    cp -r $REMOTE_PREFIX$BUCKET/$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src $LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT || die "Error during remote copy, aborting benchmark. If the error persists, please contact CUNO support."
}

test_setup

echo "-- Setup test files --" | tee -a $TEST_OUTPUT
setup_source_files

echo "-- Run Cloud Tests --" | tee -a $TEST_OUTPUT
echo "---------------------------LARGE FILES LOCAL TO REMOTE (WRITE) --------------------------------" | tee -a $TEST_OUTPUT
i=0
sum=0
while [[ "${i}" -lt "${REPEATS}" ]]; do
    clear_dest_remote
    clear_cache
    start=$(date +%s.%N)
    copy_large_local_remote
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;(${TEST_FILE_SIZE_GiB}*5)/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
echo "Results - Average (Gbps): $average_speed"  | tee -a $TEST_OUTPUT
echo "------------------------------------------------------------------------------------" | tee -a $TEST_OUTPUT

echo "--------------- Clear local src -----------------------"
rm -rf "$LOCAL_DIRECTORY/src"

echo "--------------------------LARGE FILES REMOTE TO LOCAL (READ) -------------------------------" | tee -a $TEST_OUTPUT
i=0
sum=0
while [[ "${i}" -lt "${REPEATS}" ]]; do
    clear_dest_local
    clear_cache
    start=$(date +%s.%N)
    copy_large_remote_local
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;(${TEST_FILE_SIZE_GiB}*5)/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
echo "Results - Average (Gbps): $average_speed" | tee -a $TEST_OUTPUT
echo "------------------------------------------------------------------------------------" | tee -a $TEST_OUTPUT
