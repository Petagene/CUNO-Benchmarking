#!/bin/bash
# This script downloads the Linux kernel to the current working directory, runs "write" benchmarks by uploading this to the remote destination specified in parameters.sh, then copies it back from the remote destination to the current working directory.
#
# First argument: CUNO or FILESYSTEM
# Env variables:
#   DONT_CLEAN_UP - if you don't want files created/uploaded files deleted when this script exits.
#   DONT_RUN_WRITE - don't run the write benchmarks. If you still want to read, then your files need to already have been uploaded.
#   DONT_RUN_READ - don't run the read benchmarks.
# 
warn() {
   echo -e "$*" | tee -a $TEST_OUTPUT
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

[ -z "$1" ] && die "The first argument is necessary:\n  ${SCRIPT_DIR}/large_file_benchmark.sh [CUNO/FILESYSTEM]\nAlternatively, use one of the parent scripts:\n  ${SCRIPT_DIR}/run_cuno_large_file_benchmark.sh\n  ${SCRIPT_DIR}/run_filesystem_large_file_benchmark.sh"

[[ ! "$1" = "CUNO" ]] && [[ ! "$1" = "FILESYSTEM" ]] && die "First argument must be one of 'CUNO' or 'FILESYSTEM'"


# Handle special cases 
if [[ "$1" = "CUNO" ]]; then
    [ -z "$CUNO_SF_BUCKET" ] && die "CUNO_SF_BUCKET in parameters.sh needs to be defined and non-empty. Please specify it as the bucket you wish to test in."
    REMOTE_DIRECTORY=$CUNO_SF_REMOTE_PREFIX$CUNO_SF_BUCKET/$CUNO_SF_REMOTE_DIRECTORY
    CUNO_RUN_COMMAND="cuno run"
    
    [[ -n "$CUNO_LOADED" ]] && die "This benchmark requires that cunoFS is not already active on this shell. Please exit your cunoFS-activated shell and try again." 
    
    warn "Using $(cuno -V)"
else
    [ -z "$FILESYSTEM_SF_REMOTE_DIRECTORY" ] && die "FILESYSTEM_SF_REMOTE_DIRECTORY in parameters.sh needs to be defined and non-empty. Please specify it as the mountpoint (or a directory within the mount) of the filesystem"
    REMOTE_DIRECTORY=$FILESYSTEM_SF_REMOTE_DIRECTORY
fi
# Define generic parameters to use in this script by using $1 as the PREFIX_ for parameters in parameters.sh
eval LOCAL_DIRECTORY='$'"${1}"_SF_LOCAL_DIRECTORY
eval TEST_OUTPUT='$'"${1}"_SF_TEST_OUTPUT
eval REPEATS='$'"${1}"_SF_REPEATS
# Time to sleep between runs, to allow for server-side caches to time out.
eval SLEEP_TIME_SECONDS='$'"${1}"_SF_SLEEP_TIME_SECONDS
test_size=1.21072
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
eval WARM_UP_REPEATS='$'"${1}"_SF_WARM_UP_REPEATS

warn "-- STARTING $1 SMALL FILE BENCHMARK --"
warn "PARAMETERS:"
warn "  - REMOTE_DIRECTORY: ${REMOTE_DIRECTORY}"
warn "  - LOCAL_DIRECTORY: $(realpath "${LOCAL_DIRECTORY}")"
warn "  - TEST_OUTPUT: ${TEST_OUTPUT}"
warn "  - REPEATS: ${REPEATS}"
warn "  - SLEEP_TIME_SECONDS: ${SLEEP_TIME_SECONDS}"
warn "  - WARM_UP_REPEATS: ${WARM_UP_REPEATS}"

cleanup_trap() {
    trap - EXIT 2 6 15
    warn "-- Post-test cleanup --"
    [ -z "$DONT_CLEAN_UP" ] && cleanup
    warn "-- FINISHED SMALL FILE BENCHMARK --"
}
trap cleanup_trap EXIT 2 6 15

cleanup() {
    # Sync first otherwise files/dirs that are staged but not pushed onto S3 using Mounpoint will fail the delete
    clear_cache
    rm -rf "$LOCAL_DIRECTORY/src" || warn "Failed to delete '$LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    rm -rf "$LOCAL_DIRECTORY/dst" || warn "Failed to delete '$LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    $CUNO_RUN_COMMAND find "$REMOTE_DIRECTORY/dst" -delete || warn "Failed to delete '$REMOTE_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
    $CUNO_RUN_COMMAND find "$REMOTE_DIRECTORY/src" -delete || warn "Failed to delete '$REMOTE_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions, and that you have access to the bucket."
}

create_source_directories() {
    mkdir -p $LOCAL_DIRECTORY/src || die "Failed to create the local directory '$LOCAL_DIRECTORY/src'. Please ensure that the current user '`whoami`' has sufficient permissions."
    mkdir -p $LOCAL_DIRECTORY/dst || die "Failed to create the local directory '$LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`' has sufficient permissions."
    $CUNO_RUN_COMMAND mkdir -p $REMOTE_DIRECTORY/dst || die "Failed to create new directory '$REMOTE_DIRECTORY/dst'. Please ensure that your user '`whoami`' has sufficient permissions."
    $CUNO_RUN_COMMAND mkdir -p $REMOTE_DIRECTORY/src || die "Failed to create new directory '$REMOTE_DIRECTORY/src'. Please ensure that your user '`whoami`' has sufficient permissions."
}

test_setup() {
    mount -l | awk '$5 == "tmpfs" {if (match('\"$PWD/$LOCAL_DIRECTORY\"', $3)) print $3}' | grep '.*' >/dev/null || warn "WARNING: The directory '$PWD/$LOCAL_DIRECTORY' isn't located in a ramdisk, which means that the performance will be bottlenecked by the local disk. You can create a ramdisk with the 'sudo mount -t tmpfs -o size=8G tmpfs </path/to/dir>' (please ensure that you have sufficient RAM)."
    $CUNO_RUN_COMMAND mkdir -p "$REMOTE_DIRECTORY" || die "Failed to create '$REMOTE_DIRECTORY/test_setup'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have write access."
    # S3 Mountpoint doesn't support touch a file on S3, so we need to do it locally and copy across to test for write access
    touch ./tmp_file_to_test_setup
    # S3 Mountpoint never allows overwriting a file, so delete it first if it exists
    $CUNO_RUN_COMMAND rm "$REMOTE_DIRECTORY/test_setup" || true
    $CUNO_RUN_COMMAND cp tmp_file_to_test_setup "$REMOTE_DIRECTORY/test_setup" || die "Failed to create a new file '$REMOTE_DIRECTORY/test_setup'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have write access."
    rm ./tmp_file_to_test_setup
    # S3 Mountpoint has async writes, so add this line or rm will fail
    clear_cache
    $CUNO_RUN_COMMAND rm -f "$REMOTE_DIRECTORY/test_setup" || die "Failed to remove '$REMOTE_DIRECTORY/test_setup'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have write access."
}

clear_dest_remote() {
    $CUNO_RUN_COMMAND find "$REMOTE_DIRECTORY/dst" -delete | tee -a $TEST_OUTPUT || die "Failed to delete remote directory '$REMOTE_DIRECTORY/dst'. Is this error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
}

clear_dest_local() {
    rm -rf $LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT || die "Failed to clear local directory '$LOCAL_DIRECTORY/dst'. Please ensure that the current user '`whoami`'" || die "Failed to delete local directory '$LOCAL_DIRECTORY/dst'. Is this error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
}

clear_cache() {
    # We sync first, to prompt writing of the cache. This should be included in benchmark timings. Ideally we would only sync on the filesystem we care about, but so long as the system is not running other I/O heavy tasks (an requirement for benchmarking) this should not be an issue.
    sync
    # We "drop" caches, meaning memory is freed up for new processes. This is useful if we are expecting to do this before a test run to try and get more consistent numbers. 
    sudo sh -c "echo 3 >/proc/sys/vm/drop_caches 2>/dev/null" || warn "NOTE: Failed to automatically clear the kernel cache." "You can manually clear the cache by running 'echo 3 >/proc/sys/vm/drop_caches' as root, or as non root run 'sudo sh -c \"/usr/bin/echo 3 > /proc/sys/vm/drop_caches\"'."
    # We clear cunoFS cache, so that we can start from fresh. 
    sh -c "rm -rf /dev/shm/cuno*$UID.$UID 2>/dev/null" || warn "NOTE: Failed to automatically clear local cuno cache. You can manually clear this cache by running 'rm -rf /dev/shm/cuno*$UID.$UID'. If you're not testing cunoFS (Direct Interception, a cunoFS Mount, or a FlexMount) then this has not effect."
}

setup_source_files() {
    warn "    -- Fetching linux source files"
    wget -q "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.2.tar.xz" -P $LOCAL_DIRECTORY || die "Failed to download 'https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.2.tar.xz' locally."
    warn "    -- Preparing local"
    tar -xf $LOCAL_DIRECTORY/linux-5.17.2.tar.xz --directory $LOCAL_DIRECTORY/src || die "Failed to untar '$LOCAL_DIRECTORY/linux-5.17.2.tar.xz' to '$LOCAL_DIRECTORY/src'. Please ensure the destination has enough space."
    rm $LOCAL_DIRECTORY/linux-5.17.2.tar.xz || die "Failed to delete local file '$LOCAL_DIRECTORY/linux-5.17.2.tar.xz'. Please ensure that the user '`whoami`' has sufficent permissions."
}

copy_large_local_remote() {
    # Dear users, don't copy this behaviour. We have intentionally used "cuno run" on individual commands here to promote  isolation. You should prefer to just run the entirety of your scripts with cuno activated to benefit from our latency hiding and metadata caching.
    $CUNO_RUN_COMMAND bash -c "cp -L -r $LOCAL_DIRECTORY/src $1" | tee -a $TEST_OUTPUT || die "Error during remote write, aborting benchmark. If the error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
}

copy_large_remote_local() {
    # Dear users, don't copy this behaviour. We have intentionally used "cuno run" on individual commands here to promote  isolation. You should prefer to just run the entirety of your scripts with cuno activated to benefit from our latency hiding and metadata caching.
    $CUNO_RUN_COMMAND bash -c "cp -L -r $REMOTE_DIRECTORY/dst $LOCAL_DIRECTORY/dst" | tee -a $TEST_OUTPUT || die "Error during remote read, aborting benchmark. If the error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
}

warm_up_write () {
    i=0
    while [[ "${i}" -lt "${WARM_UP_REPEATS}" ]]; do
        copy_large_local_remote "${REMOTE_DIRECTORY}/dst/test"
        i=$((i + 1))
    done
    clear_dest_remote 
}

test_setup

warn "-- Cleaning up test directory --"
cleanup 

warn "-- Creating test directories --"
create_source_directories

warn "-- Setup test files --"
setup_source_files

warn "-- Writing $WARM_UP_REPEATS time(s) as warm up --"
warm_up_write

warn "-- Run Benchmarks --"

if [[ -z "$DONT_RUN_WRITE" ]]; then
    warn "-------------------------- SMALL FILES (74999) LOCAL TO REMOTE (WRITE) -------------------------------"
    i=0
    sum=0
    while [[ "${i}" -lt "${REPEATS}" ]]; do
        # crucially, we don't delete the last time so that we can use the uploaded files for download benchmarks
        clear_dest_remote
        clear_cache
        current_remote_directory="${REMOTE_DIRECTORY}/dst/run_$i"
        $CUNO_RUN_COMMAND mkdir -p $current_remote_directory
        # Clearing cache here causes the cp to fail on Mountpoint because the directories get thrown away from their local cache
        # clear_cache
        # Sleep to let server-side caches expire, and to avoid gettting unrealistically consistent speeds (S3)
        warn "  -- sleeping for $SLEEP_TIME_SECONDS" 
        sleep $SLEEP_TIME_SECONDS
        start=$(date +%s.%N)
        copy_large_local_remote $current_remote_directory
        mid=$(date +%s.%N)
        # make sure cached data gets written back to the storage
        sync
        finish=$(date +%s.%N)
        duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
        duration_sync=$(echo "scale=5;${finish}-${mid}" | bc -l | awk '{printf("%.5f",$1)}')
        speed_gbips=$(echo "scale=5;${test_size}/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
        speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
        warn "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips | Time for sync: $duration_sync"
        i=$((i + 1))
        sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
        done
    average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
    warn "Results - Average (Gbps): $average_speed"
    warn "------------------------------------------------------------------------------------"
fi

# Delete the local store to make space
warn "-- Clearing local src directory --"
rm -rf "$LOCAL_DIRECTORY/src" #TODO
sync

if [[ -z "$DONT_RUN_READ" ]]; then
    warn "--------------------------- SMALL FILES (74999) REMOTE TO LOCAL (READ) --------------------------------"
    i=0
    sum=0
    while [[ "${i}" -lt "${REPEATS}" ]]; do
        clear_dest_local
        clear_cache
        # Sleep to let server-side caches expire 
        warn "  -- sleeping for $SLEEP_TIME_SECONDS" 
        sleep $SLEEP_TIME_SECONDS
        start=$(date +%s.%N)
        copy_large_remote_local
        mid=$(date +%s.%N)
        # make sure cached data gets written back to the storage
        sync
        finish=$(date +%s.%N)
        duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
        duration_sync=$(echo "scale=5;${finish}-${mid}" | bc -l | awk '{printf("%.5f",$1)}')
        speed_gbips=$(echo "scale=5;${test_size}/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
        speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
        warn "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips | Time for sync: $duration_sync"
        i=$((i + 1))
        sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done

    average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
    warn "Results - Average (Gbps): $average_speed"
    warn "------------------------------------------------------------------------------------"
fi