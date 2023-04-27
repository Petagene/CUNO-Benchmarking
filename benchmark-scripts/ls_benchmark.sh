#!/bin/bash

warn() {
   echo -e "$*" | tee -a $LS_TEST_OUTPUT
}

die() {
   warn "$*"
   exit 1
}

awk --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'awk'."
bc --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'bc'."
tee --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'tee'."

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>/dev/null && pwd)
source ${SCRIPT_DIR}/../parameters.sh || die "Failed to source `${SCRIPT_DIR}/../parameters.sh`. Please ensure that the file is "

warn "-- STARTING LS BENCHMARK --"
warn "PARAMETERS:\n  - LS_BUCKET: ${LS_BUCKET}\n  LS_REMOTE_DIRECTORY: ${LS_REMOTE_DIRECTORY}\n  - LS_REMOTE_PREFIX: ${LS_REMOTE_PREFIX}\n  - LS_LOCAL_DIRECTORY: ${LS_LOCAL_DIRECTORY}\n  - LS_TEST_OUTPUT: ${LS_TEST_OUTPUT}\n  - LS_REPEATS: ${LS_REPEATS}"

cleanup() {
    rm -rf "$LS_LOCAL_DIRECTORY/src" || die "Failed to delete '$LS_LOCAL_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$LS_REMOTE_PREFIX$LS_BUCKET/$LS_REMOTE_DIRECTORY/dst" || die "Failed to delete '$LS_REMOTE_PREFIX$LS_BUCKET/$LS_REMOTE_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
}

cleanup_trap() {
   warn "-- Post-test cleanup --"
   cleanup
   warn "-- FINISHED LS BENCHMARK --"
}
trap cleanup_trap EXIT 2 6 15

create_source_directories() {
    mkdir -p $LS_LOCAL_DIRECTORY/src || die "Failed to create local '$LS_LOCAL_DIRECTORY/src'. Please ensure that the user '`whoami`' has sufficient privileges."
}

clear_cache() {
    sudo sh -c "rm -rf /dev/shm/cuno* 2>/dev/null" || warn "WARNING: Failed to automatically clear local cuno cache." "You can manually clear this cache by running 'rm -rf /dev/shm/cuno*' with administrative privileges."
    sudo sh -c "echo 3 > /proc/sys/vm/drop_caches 2>/dev/null" || warn "WARNING: Failed to automatically clear the kernel cache." "You can manually clear the cache by running 'echo 3 >/proc/sys/vm/drop_caches' with administrative privileges."
}

setup_source_files() {
    warn "    -- Preparing local"
    for i in {0..10000}
    do
        random_string=$(cat /proc/sys/kernel/random/uuid | sed 's/[-]//g' | head -c 20; echo;)
        dd if=/dev/urandom of="$LS_LOCAL_DIRECTORY/src/$random_string" count=1024 bs=1 >/dev/null 2>/dev/null || die "Failed to create '$LS_LOCAL_DIRECTORY/src/$random_string'."
    done
    warn "    -- Uploading to cloud"
    cp -r $LS_LOCAL_DIRECTORY/src $LS_REMOTE_PREFIX$LS_BUCKET/$LS_REMOTE_DIRECTORY/src || dir "Failed to write to '$LS_REMOTE_PREFIX$LS_BUCKET/$LS_REMOTE_DIRECTORY/src'."
}

ls_remote() {
    ls $LS_REMOTE_PREFIX$LS_BUCKET/$LS_REMOTE_DIRECTORY/src || die "Failed to ls '$LS_REMOTE_PREFIX$LS_BUCKET/$LS_REMOTE_DIRECTORY/src'."
}


warn "-- Cleaning up test directory --"
cleanup 

warn "-- Creating test directories --"
create_source_directories

warn "-- Setup test files --"
setup_source_files

warn "-- Run Cloud Tests --"
warn "---------------------------LARGE FILES LOCAL TO REMOTE--------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${LS_REPEATS}" ]]; do
    clear_cache
    start=$(date +%s.%N)
    ls_remote
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration"  | tee -a $LS_TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${duration}" | bc -l | awk '{printf("%.5f",$1)}')
done
average_time=$(echo "scale=5;${sum}/${LS_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_time"
warn "------------------------------------------------------------------------------------"
