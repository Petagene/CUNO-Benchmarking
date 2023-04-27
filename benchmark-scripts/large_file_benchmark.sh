#!/bin/bash

warn() {
   echo -e "$*" | tee -a $FB_TEST_OUTPUT
}

die() {
   warn "$*"
   exit 1
}

dd --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'dd'."
awk --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'awk'."
bc --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'bc'."
tee --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'tee'."

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>/dev/null && pwd)
source ${SCRIPT_DIR}/../parameters.sh || die "Failed to source `${SCRIPT_DIR}/../parameters.sh`. Please ensure that the file is in the original directory and that the user '`whoami`' has sufficient privileges."

warn "-- STARTING CUNO LARGE FILE BENCHMARK --"
warn "PARAMETERS:\n  - FB_BUCKET: ${FB_BUCKET}\n  - FB_REMOTE_DIRECTORY: ${FB_REMOTE_DIRECTORY}\n  - FB_REMOTE_PREFIX: ${FB_REMOTE_PREFIX}\n  - FB_LOCAL_DIRECTORY: ${FB_LOCAL_DIRECTORY}\n  - FB_TEST_OUTPUT: ${FB_TEST_OUTPUT}\n  - FB_REPEATS: ${FB_REPEATS}\n  - FB_TEST_FILE_SIZE_GiB: ${FB_TEST_FILE_SIZE_GiB}\n  - FB_NB_TEST_FILES: ${FB_NB_TEST_FILES}"

cleanup_trap() {
   warn "-- Post-test cleanup --"
   cleanup
   warn "-- FINISHED CUNO LARGE FILE BENCHMARK --"
}
trap cleanup_trap EXIT 2 6 15

cleanup() {
    rm -rf "$FB_LOCAL_DIRECTORY/src" || die "Failed to delete '$FB_LOCAL_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$FB_LOCAL_DIRECTORY/dst" || die "Failed to delete '$FB_LOCAL_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/dst" || die "Failed to delete '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
    rm -rf "$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/src" || die "Failed to delete '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
}

create_source_directories() {
    mkdir -p $FB_LOCAL_DIRECTORY/src || die "Failed to create the local directory '$FB_LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $FB_LOCAL_DIRECTORY/dst || die "Failed to create the local directory '$FB_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/dst || die "Failed to create new directory '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/dst'. Make sure that your user '`whoami`' has sufficient permissions."
    mkdir -p $FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/src || die "Failed to create new directory '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/src'. Make sure that your user '`whoami`' has sufficient permissions."
}

test_setup() {
   [[ -z "$FB_BUCKET" ]] && die "Please specify the bucket to be used in './parameters.sh' with the 'FB_BUCKET=<bucket_name>' parameter."

   [[ -z "$CUNO_LOADED" ]] && die "This benchmark requires CUNO to be loaded to run."
   warn "Using `cuno -V`"

   mount -l | awk '$5 == "tmpfs" {if (match('\"$PWD/$FB_LOCAL_DIRECTORY\"', $3)) print $3}' | grep '.*' >/dev/null || warn "WARNING: The directory '$PWD/$FB_LOCAL_DIRECTORY' isn't located in a ramdisk, which means that the performance will be bottlenecked by the local disk. You can create a ramdisk with the 'sudo mount -t tmpfs -o size=150G tmpfs </path/to/dir>' (ensure that you have sufficient RAM)."

   mkdir -p "$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY" || die "Failed to create '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/test_setup', please ensure that the bucket '$FB_BUCKET' and the prefix '$FB_REMOTE_PREFIX' are correct."
   touch "$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/test_setup" || die "Failed to create a new file '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/test_setup', please ensure that the bucket '$FB_BUCKET' and the prefix '$FB_REMOTE_PREFIX' are correct."
   rm -f "$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/test_setup" || die "Failed to remove '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/test_setup', please ensure that the bucket '$FB_BUCKET' and the prefix '$FB_REMOTE_PREFIX' are correct."

   warn "-- Cleaning up test directory --"
   cleanup 

   warn "-- Creating test directories --"
   create_source_directories
}

clear_cache() {
    sudo sh -c "rm -rf /dev/shm/cuno* 2>/dev/null" || warn "NOTE: Failed to automatically clear local cuno cache." "You can manually clear this cache by running 'rm -rf /dev/shm/cuno*' with administrative privileges."
    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches 2>/dev/null" || warn "NOTE: Failed to automatically clear the kernel cache." "You can manually clear the cache by running 'echo 3 > /proc/sys/vm/drop_caches' with administrative privileges."
}

setup_source_files() {
    warn "    -- Preparing local"
    dd if=/dev/urandom of=$FB_LOCAL_DIRECTORY/src/test_file1 count=1048576 bs=$((1024*$FB_TEST_FILE_SIZE_GiB)) || die "Failed to generate random file '$FB_LOCAL_DIRECTORY/src/test_file1'. Please ensure that you have sufficient permissions."
    j=2
    while test $j -le $FB_NB_TEST_FILES ; do
        cp $FB_LOCAL_DIRECTORY/src/test_file1 $FB_LOCAL_DIRECTORY/src/test_file$j || die "Error copying file to local '$FB_LOCAL_DIRECTORY/src/test_file$j'."
        j=$((j+1))
    done
    warn "    -- Uploading to cloud"
    cp -r $FB_LOCAL_DIRECTORY/src/* $FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/src/. || die "Error uploading directory to remote '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/$FB_LOCAL_DIRECTORY/src/'. Please ensure that you have access to the bucket '$FB_BUCKET'. If this issue persists, contact CUNO support."
}

clear_dest_remote() {
    rm -rf "$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/dst" | tee -a $FB_TEST_OUTPUT || die "Failed to delete remote '$FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/dst'. Is this error persists, contact CUNO support."
}

clear_dest_local() {
    rm -rf $FB_LOCAL_DIRECTORY/dst | tee -a $FB_TEST_OUTPUT || die "Failed to clear local directory '$FB_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`'" || die "Failed to delete local directory '$FB_LOCAL_DIRECTORY/dst'. Is this error persists, contact CUNO support."
}

copy_large_local_remote() {
    cp -r $FB_LOCAL_DIRECTORY/src $FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/dst | tee -a $FB_TEST_OUTPUT || die "Error during remote write, aborting benchmark. If the error persists, please contact CUNO support."
}

copy_large_remote_local() {
    cp -r $FB_REMOTE_PREFIX$FB_BUCKET/$FB_REMOTE_DIRECTORY/src $FB_LOCAL_DIRECTORY/dst | tee -a $FB_TEST_OUTPUT || die "Error during remote read, aborting benchmark. If the error persists, please contact CUNO support."
}

test_setup

warn "-- Setup test files --"
setup_source_files

warn "-- Run Cloud Tests --"
warn "---------------------------LARGE FILES LOCAL TO REMOTE (WRITE) --------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${FB_REPEATS}" ]]; do
    clear_dest_remote
    clear_cache
    start=$(date +%s.%N)
    copy_large_local_remote
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;(${FB_TEST_FILE_SIZE_GiB}*${FB_NB_TEST_FILES})/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $FB_TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${FB_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"

warn "-- Clearing local src --"
rm -rf "$FB_LOCAL_DIRECTORY/src" #TODO

warn "--------------------------LARGE FILES REMOTE TO LOCAL (READ) -------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${FB_REPEATS}" ]]; do
    clear_dest_local
    clear_cache
    start=$(date +%s.%N)
    copy_large_remote_local
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;(${FB_TEST_FILE_SIZE_GiB}*${FB_NB_TEST_FILES})/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $FB_TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${FB_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"
