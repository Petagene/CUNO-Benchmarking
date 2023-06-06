#!/bin/bash

warn() {
   echo -e "$*" | tee -a $FF_TEST_OUTPUT
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

warn "-- STARTING FILESYSTEM LARGE FILE BENCHMARK --"
warn "PARAMETERS:\n  - FF_REMOTE_DIRECTORY: ${FF_REMOTE_DIRECTORY}\n  - FF_LOCAL_DIRECTORY: ${FF_LOCAL_DIRECTORY}\n  - FF_TEST_OUTPUT: ${FF_TEST_OUTPUT}\n  - FF_REPEATS: ${FF_REPEATS}"

cleanup_trap() {
   warn "-- Post-test cleanup --"
   cleanup
   warn "-- FINISHED FILESYSTEM LARGE FILE BENCHMARK --"
}
trap cleanup_trap EXIT 2 6 15


cleanup() {
    rm -rf "$FF_LOCAL_DIRECTORY/src" || die "Failed to delete '$FF_LOCAL_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$FF_LOCAL_DIRECTORY/dst" || die "Failed to delete '$FF_LOCAL_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$FF_REMOTE_DIRECTORY/dst" || die "Failed to delete '$FF_REMOTE_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
    rm -rf "$FF_REMOTE_DIRECTORY/src" || die "Failed to delete '$FF_REMOTE_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
}

test_setup() {
   [[ -z "$FF_REMOTE_DIRECTORY" ]] && die "Please specify the mountpoint of the filesystem you want to test in './parameters.sh' with the 'FF_REMOTE_DIRECTORY=<mount_path>' parameter."


   # mount -l | awk '$5 == "tmpfs" {if (match('\"$PWD/$FF_LOCAL_DIRECTORY\"', $3)) print $3}' | grep '.*' >/dev/null || warn "WARNING: The directory '$PWD/$FF_LOCAL_DIRECTORY' isn't located in a ramdisk, which means that the performance will be bottlenecked by the local disk. You can create a ramdisk with the 'sudo mount -t tmpfs -o size=150G tmpfs </path/to/dir>' (ensure that you have usfficient RAM)."

   mkdir -p "$FF_REMOTE_DIRECTORY" || die "Failed to create '$FF_REMOTE_DIRECTORY/test_setup'."
   touch "$FF_REMOTE_DIRECTORY/test_setup" || die "Failed to create a new file '$FF_REMOTE_DIRECTORY/test_setup'."
   rm -f "$FF_REMOTE_DIRECTORY/test_setup" || die "Failed to delete '$FF_REMOTE_DIRECTORY/test_setup'."
}

create_source_directories() {
    mkdir -p $FF_LOCAL_DIRECTORY/src || die "Failed to create the local directory '$FF_LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $FF_LOCAL_DIRECTORY/dst || die "Failed to create the local directory '$FF_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $FF_REMOTE_DIRECTORY/src || die "Failed to create new directory '$FF_REMOTE_DIRECTORY/src'. Make sure that your user '`whoami`' has sufficient permissions."
    mkdir -p $FF_REMOTE_DIRECTORY/dst || die "Failed to create new directory '$FF_REMOTE_DIRECTORY/dst'. Make sure that your user '`whoami`' has sufficient permissions."
}

clear_cache() {
    sudo sh -c "echo 3 >/proc/sys/vm/drop_caches 2>/dev/null" || warn "NOTE: Failed to automatically clear the kernel cache." "You can manually clear the cache by running 'echo 3 >/proc/sys/vm/drop_caches' with administrative privileges."
}

setup_source_files() {
    warn "    -- Preparing local"
    dd if=/dev/urandom of=$FF_LOCAL_DIRECTORY/src/test_file1 count=1048576 bs=$((1024*$FF_TEST_FILE_SIZE_GiB)) >/dev/null || die "Failed to generate random file '$FF_LOCAL_DIRECTORY/src/test_file1'. Please ensure that the user '`whoami`' has sufficient permissions."
    j=2
    while test $j -le $FF_NB_TEST_FILES ; do
        cp $FF_LOCAL_DIRECTORY/src/test_file1 "$FF_LOCAL_DIRECTORY/src/test_file$j" || die "Error copying file to '$FF_LOCAL_DIRECTORY/src/test_file$j'."
        j=$((j+1))
    done
    warn "    -- Uploading to cloud"
    cp -r $FF_LOCAL_DIRECTORY/src/* $FF_REMOTE_DIRECTORY/src/ || die "Faield to upload files to '$FF_REMOTE_DIRECTORY/src'."
}

clear_dest_remote() {
    rm -rf $FF_REMOTE_DIRECTORY/dst | tee -a $FF_TEST_OUTPUT || die "Faield to delete remote '$FF_REMOTE_DIRECTORY/dst'."
}

clear_dest_local() {
    rm -rf $FF_LOCAL_DIRECTORY/dst | tee -a $FF_TEST_OUTPUT || die "Failed to delete local '$FF_LOCAL_DIRECTORY/dst'."
}

copy_large_local_remote() {
    CUNO_CP_SPEEDUP=0 cp -r $FF_LOCAL_DIRECTORY/src $FF_REMOTE_DIRECTORY/dst | tee -a $FF_TEST_OUTPUT || die "Failed to write to remote '$FF_REMOTE_DIRECTORY/dst'."
}

copy_large_remote_local() {
    CUNO_CP_SPEEDUP=0 cp -r $FF_REMOTE_DIRECTORY/src $FF_LOCAL_DIRECTORY/dst | tee -a $FF_TEST_OUTPUT || die "Failed to read from remote '$FF_REMOTE_DIRECTORY/src'."
}

test_setup

warn "-- Cleaning up test directory --"
cleanup 

warn "-- Creating test directories --"
create_source_directories

warn "-- Setup test files --"
setup_source_files

warn "-- Run FS Tests --"
warn "---------------------------LARGE FILES (WRITE) --------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${FF_REPEATS}" ]]; do
    clear_dest_remote
    clear_cache
    start=$(date +%s.%N)
    copy_large_local_remote
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;(${FF_TEST_FILE_SIZE_GiB}*${FF_NB_TEST_FILES})/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $FF_TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${FF_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"

warn "--------------- Clear local src -----------------------"
rm -rf "$FF_LOCAL_DIRECTORY/src" || die "Failed to clea local src '$FF_LOCAL_DIRECTORY/src'."

warn "--------------------------LARGE FILES (READ)-------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${FF_REPEATS}" ]]; do
    clear_dest_local
    clear_cache
    start=$(date +%s.%N)
    copy_large_remote_local
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;(${FF_TEST_FILE_SIZE_GiB}*${FF_NB_TEST_FILES})/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $FF_TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${FF_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"
