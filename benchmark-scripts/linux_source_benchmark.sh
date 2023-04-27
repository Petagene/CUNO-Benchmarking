#!/bin/bash

warn() {
   echo -e "$*" | tee -a $SB_TEST_OUTPUT
}

die() {
   warn "$*"
   exit 1
}

wget --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'wget'."
awk --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'awk'."
bc --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'bc'."
tar --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'tar'."
tee --version >/dev/null 2>/dev/null || die "This benchmark requires the program 'tee'."

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>/dev/null && pwd)
source ${SCRIPT_DIR}/../parameters.sh || die "Failed to source `${SCRIPT_DIR}/../parameters.sh`. Please ensure that the file is in the original directory and that the user '`whoami`' has sufficient privileges."

warn "-- STARTING CUNO SMALL FILE BENCHMARK --"
warn "PARAMETERS:\n  - SB_BUCKET: ${SB_BUCKET}\n  - SB_REMOTE_DIRECTORY: ${SB_REMOTE_DIRECTORY}\n  - SB_REMOTE_PREFIX: ${SB_REMOTE_PREFIX}\n  - SB_LOCAL_DIRECTORY: ${SB_LOCAL_DIRECTORY}\n  - SB_TEST_OUTPUT: ${SB_TEST_OUTPUT}\n  - SB_REPEATS: ${SB_REPEATS}"

cleanup_trap() {
   warn "-- Post-test cleanup --"
   cleanup
   warn "-- FINISHED CUNO SMALL FILE BENCHMARK --"
}
trap cleanup_trap EXIT 2 6 15

cleanup() {
    rm -rf "$SB_LOCAL_DIRECTORY/src" || die "Failed to delete '$SB_LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    rm -rf "$SB_LOCAL_DIRECTORY/dst" || die "Failed to delete '$SB_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    rm -rf "$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/dst" || die "Failed to delete '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
    rm -rf "$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/src" || die "Failed to delete '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
}

create_source_directories() {
    mkdir -p $SB_LOCAL_DIRECTORY/src || die "Failed to create the local directory '$SB_LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $SB_LOCAL_DIRECTORY/dst || die "Failed to create the local directory '$SB_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/dst || die "Failed to create new directory '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/dst'. Please ensure that your user '`whoami`' has sufficient permissions."
    mkdir -p $SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/src || die "Failed to create new directory '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/src'. Please ensure that your user '`whoami`' has sufficient permissions."
}

test_setup() {
   [[ -z "$SB_BUCKET" ]] && die "Please specify the bucket to be used in the 'SB_BUCKET=<bucket_name>' parameter."

   [[ -z "$CUNO_LOADED" ]] && die "This benchmark requires CUNO to be loaded to run."
   warn "Using `cuno -V`"

   mount -l | awk '$5 == "tmpfs" {if (match('\"$PWD/$SB_LOCAL_DIRECTORY\"', $3)) print $3}' | grep '.*' >/dev/null || warn "WARNING: The directory '$PWD/$SB_LOCAL_DIRECTORY' isn't located in a ramdisk, which means that the performance will be bottlenecked by the local disk. You can create a ramdisk with the 'sudo mount -t tmpfs -o size=150G tmpfs </path/to/dir>' (ensure that you have sufficient RAM)."

   mkdir -p "$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY" || die "Failed to create '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/test_setup', please ensure that the bucket '$SB_BUCKET' and the prefix '$SB_REMOTE_PREFIX' are accessible."
   touch "$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/test_setup" || die "Failed to create a new file '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/test_setup', please ensure that the bucket '$SB_BUCKET' and the prefix '$SB_REMOTE_PREFIX' are correct."
}

test_size=1.21072

clear_dest_remote() {
    rm -rf "$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/dst" | tee -a $SB_TEST_OUTPUT || die "Failed to delete remote directory '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/dst'. Is this error persists, contact CUNO support."
}

clear_dest_local() {
    rm -rf $SB_LOCAL_DIRECTORY/dst | tee -a $SB_TEST_OUTPUT || die "Failed to clear local directory '$SB_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`'" || die "Failed to delete local directory '$SB_LOCAL_DIRECTORY/dst'. Is this error persists, contact CUNO support."
}

clear_cache() {
    sudo sh -c "rm -rf /dev/shm/cuno* 2>/dev/null" || warn "NOTE: Failed to automatically clear local cuno cache." "You can manually clear this cache by running 'rm -rf /dev/shm/cuno*' with administrative privileges."
    sudo sh -c "echo 3 >/proc/sys/vm/drop_caches 2>/dev/null" || warn "NOTE: Failed to automatically clear the kernel cache." "You can manually clear the cache by running 'echo 3 >/proc/sys/vm/drop_caches' with administrative privileges."
}

setup_source_files() {
    warn "    -- Fetching linux source files"
    wget -q "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.2.tar.xz" -P $SB_LOCAL_DIRECTORY || die "Failed to download 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.2.tar.xz' locally."
    warn "    -- Preparing local"
    tar -xf $SB_LOCAL_DIRECTORY/linux-5.17.2.tar.xz --directory $SB_LOCAL_DIRECTORY/src || die "Failed to untar '$SB_LOCAL_DIRECTORY/linux-5.17.2.tar.xz'."
    rm $SB_LOCAL_DIRECTORY/linux-5.17.2.tar.xz || die "Failed to delete local file '$SB_LOCAL_DIRECTORY/linux-5.17.2.tar.xz'. Please ensure that the user '`whoami`' have sufficent permissions."
    warn "    -- Uploading to cloud"
    cp -L -r "$SB_LOCAL_DIRECTORY/src/linux-5.17.2" "$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/src/" || die "Failed to copy linux source to remote directory '$SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/src'. Please ensure that you have sufficient privileges, that CUNO is active and that you have access to the bucket."
    rm -rf $SB_LOCAL_DIRECTORY/linux-5.17.2 || die "Failed to delete '$SB_LOCAL_DIRECTORY/linux-5.17.2'. Please ensure that the user '`whoami`' has sufficient permissions."
}

copy_large_local_remote() {
    cp -L -r $SB_LOCAL_DIRECTORY/src $SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/dst | tee -a $SB_TEST_OUTPUT || die "Error during remote write, aborting benchmark. If the error persists, please contact CUNO support."
}

copy_large_remote_local() {
    cp -L -r $SB_REMOTE_PREFIX$SB_BUCKET/$SB_REMOTE_DIRECTORY/src $SB_LOCAL_DIRECTORY/dst | tee -a $SB_TEST_OUTPUT || die "Error during remote read, aborting benchmark. If the error persists, please contact CUNO support."
}

test_setup

warn "-- Cleaning up test directory --"
cleanup 

warn "-- Creating test directories --"
create_source_directories

warn "-- Setup test files --"
setup_source_files

warn "-- Run Cloud Tests --"
warn "--------------------------SMALL FILES (74999) (READ) -------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${SB_REPEATS}" ]]; do
    clear_dest_local
    clear_cache
    start=$(date +%s.%N)
    copy_large_remote_local
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;${test_size}/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    warn "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${SB_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"

warn "---------------------------SMALL FILES (74999) (WRITE) --------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${SB_REPEATS}" ]]; do
    clear_dest_remote
    clear_cache
    start=$(date +%s.%N)
    copy_large_local_remote
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;${test_size}/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    warn "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done

average_speed=$(echo "scale=5;${sum}/${SB_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"
