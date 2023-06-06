#!/bin/bash

warn() {
   echo -e "$*" | tee -a $FS_TEST_OUTPUT
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

test_size=1.21072

warn "-- STARTING FILESYSTEM SMALL FILE BENCHMARK --"
warn "PARAMETERS:\n  - FS_REMOTE_DIRECTORY: ${FS_REMOTE_DIRECTORY}\n  - FS_LOCAL_DIRECTORY: ${FS_LOCAL_DIRECTORY}\n  - FS_TEST_OUTPUT: ${FS_TEST_OUTPUT}\n  - FS_REPEATS: ${FS_REPEATS}"

cleanup_trap() {
   warn "-- Post-test cleanup --"
   cleanup
   warn "-- FINISHED FILESYSTEM SMALL FILE BENCHMARK --"
}
trap cleanup_trap EXIT 2 6 15

cleanup() {
    rm -rf "$FS_LOCAL_DIRECTORY/src" || die "Failed to delete '$FS_LOCAL_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$FS_LOCAL_DIRECTORY/dst" || die "Failed to delete '$FS_LOCAL_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$FS_REMOTE_DIRECTORY/dst" || die "Failed to delete '$FS_REMOTE_DIRECTORY/dst'. Please ensure the current user '`whoami`' has sufficient permissions."
    rm -rf "$FS_REMOTE_DIRECTORY/src" || die "Failed to delete '$FS_REMOTE_DIRECTORY/src'. Please ensure the current user '`whoami`' has sufficient permissions."
}

test_setup() {
   [[ -z "$FS_REMOTE_DIRECTORY" ]] && die "Please specify the mountpoint of the filesystem you want to test in './parameters.sh' with the 'FS_REMOTE_DIRECTORY=<mount_path>' parameter."

   mkdir -p "$FS_REMOTE_DIRECTORY" || die "Failed to create '$FS_REMOTE_DIRECTORY/test_setup'."
   touch "$FS_REMOTE_DIRECTORY/test_setup" || die "Failed to create a new file '$FS_REMOTE_DIRECTORY/test_setup'."
   rm -f "$FS_REMOTE_DIRECTORY/test_setup" || die "Failed to remove '$FS_REMOTE_DIRECTORY/test_setup'."
}

create_source_directories() {
    mkdir -p $FS_LOCAL_DIRECTORY/src || die "Failed to create the local directory '$FS_LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $FS_LOCAL_DIRECTORY/dst || die "Failed to create the local directory '$FS_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $FS_REMOTE_DIRECTORY/dst || die "Failed to create new directory '$FS_REMOTE_DIRECTORY/dst'. Make sure that your user '`whoami`' has sufficient permissions."
    mkdir -p $FS_REMOTE_DIRECTORY/src || die "Failed to create new directory '$FS_REMOTE_DIRECTORY/src'. Make sure that your user '`whoami`' has sufficient permissions."
}

clear_dest_remote() {
    rm -rf "$FS_REMOTE_DIRECTORY/dst" | tee -a $FS_TEST_OUTPUT || die "Failed to delete remote directory '$FS_REMOTE_DIRECTORY/dst'. If this error persists, contact CUNO support."
}

clear_dest_local() {
    rm -rf $FS_LOCAL_DIRECTORY/dst | tee -a $FS_TEST_OUTPUT || die "Failed to clear local directory '$FS_LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
}

clear_cache() {
    sudo sh -c "echo 3 >/proc/sys/vm/drop_caches 2>/dev/null" || warn "WARNING: Failed to automatically clear the kernel cache." "You can manually clear the cache by running 'echo 3 >/proc/sys/vm/drop_caches' with administrative privileges."
}

setup_source_files() {
    warn "    -- Fetching linux source files"
    wget -q "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.2.tar.xz" -P $FS_LOCAL_DIRECTORY || die "Failed to download 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.2.tar.xz' locally."
    warn "    -- Preparing local"
    tar -xf $FS_LOCAL_DIRECTORY/linux-5.17.2.tar.xz --directory $FS_LOCAL_DIRECTORY/src 2>/dev/null || die "Failed to untar '$FS_LOCAL_DIRECTORY/linux-5.17.2.tar.xz'."
    rm $FS_LOCAL_DIRECTORY/linux-5.17.2.tar.xz || die "Failed to delete local file '$FS_LOCAL_DIRECTORY/linux-5.17.2.tar.xz'. Please ensure that the user '`whoami`' have sufficent permissions."
    warn "    -- Uploading to cloud"
    cp -L -r "$FS_LOCAL_DIRECTORY/src/linux-5.17.2" "$FS_REMOTE_DIRECTORY/src/" || die "Failed to copy linux source to remote directory '$FS_REMOTE_DIRECTORY/src'. Please ensure that the user '`whoami`' has sufficient privileges, that CUNO is active and that you have access to the bucket."
    rm -rf $FS_LOCAL_DIRECTORY/linux-5.17.2 || die "Failed to delete '$FS_LOCAL_DIRECTORY/linux-5.17.2'. Please ensure that the user '`whoami`' has sufficient permissions."
}

copy_large_local_remote() {
    cp -L -r $FS_LOCAL_DIRECTORY/src $FS_REMOTE_DIRECTORY/dst | tee -a $FS_TEST_OUTPUT || die "Error during remote write to '$FS_REMOTE_DIRECTORY/dst', aborting benchmark. If the error persists, please contact CUNO support."
}

copy_large_remote_local() {
    cp -L -r $FS_REMOTE_DIRECTORY/src $FS_LOCAL_DIRECTORY/dst | tee -a $FS_TEST_OUTPUT || die "Error during remote read from '$FS_REMOTE_DIRECTORY/src', aborting benchmark. If the error persists, please contact CUNO support."
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
while [[ "${i}" -lt "${FS_REPEATS}" ]]; do
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
average_speed=$(echo "scale=5;${sum}/${FS_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"

warn "---------------------------SMALL FILES (74999) (WRITE) --------------------------------"
i=0
sum=0
while [[ "${i}" -lt "${FS_REPEATS}" ]]; do
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

average_speed=$(echo "scale=5;${sum}/${FS_REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
warn "Results - Average (Gbps): $average_speed"
warn "------------------------------------------------------------------------------------"
