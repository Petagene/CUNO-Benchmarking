#!/bin/bash

# BETA SCRIPT
# Remuxing is CPU bound in many cases, and more work is required to get this right. 

# This script downloads the Big Buck Bunny mp4 to the current working directory, converts it to the mpeg-ts format, runs "write" benchmarks by remuxing this mpeg-ts to an mp4 at the remote destination specified in parameters.sh, then uploads the mpeg-ts and runs "read" benchmarks while remuxing it to mp4 in the current working directory.

# Parameters for benchmark_scripts/run_cuno_ffmpeg_remux_benchmark.sh #
CUNO_FFMPEG_REMOTE_PREFIX=s3://
CUNO_FFMPEG_BUCKET=                       #required
CUNO_FFMPEG_REMOTE_DIRECTORY=test_directory
CUNO_FFMPEG_LOCAL_DIRECTORY=benchmark
CUNO_FFMPEG_TEST_OUTPUT=test_results.txt
# Minimum mpeg-ts file size
CUNO_FFMPEG_MIN_TEST_FILE_SIZE_GiB=4
CUNO_FFMPEG_REPEATS=3
# Time to sleep for between writes and between reads, to allow server-side caches to expire and to avoid hotspots of external traffic.
CUNO_FFMPEG_SLEEP_TIME_SECONDS=300
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
CUNO_FFMPEG_WARM_UP_REPEATS=0


# Parameters for benchmark-scripts/run_filesystem_ffmpeg_remux_benchmark.sh #
FILESYSTEM_FFMPEG_REMOTE_DIRECTORY=             #required
FILESYSTEM_FFMPEG_LOCAL_DIRECTORY=benchmark
FILESYSTEM_FFMPEG_TEST_OUTPUT=test_results.txt
# Minimum mpeg-ts file size
FILESYSTEM_FFMPEG_MIN_TEST_FILE_SIZE_GiB=4
FILESYSTEM_FFMPEG_REPEATS=3
# Time to sleep for between writes and between reads, to allow server-side caches to expire and to avoid hotspots of external traffic.
FILESYSTEM_FFMPEG_SLEEP_TIME_SECONDS=300
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
FILESYSTEM_FFMPEG_WARM_UP_REPEATS=1

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
    [ -z "$CUNO_FFMPEG_BUCKET" ] && die "CUNO_FFMPEG_BUCKET in parameters.sh needs to be defined and non-empty. Please specify it as the bucket you wish to test in."
    REMOTE_DIRECTORY=$CUNO_FFMPEG_REMOTE_PREFIX$CUNO_SF_BUCKET/$CUNO_FFMPEG_REMOTE_DIRECTORY
    CUNO_RUN_COMMAND="cuno run"
    
    [[ -n "$CUNO_LOADED" ]] && die "This benchmark requires that cunoFS is not already active on this shell. Please exit your cunoFS-activated shell and try again." 
    
    warn "Using $(cuno -V)"
else
    [ -z "$FILESYSTEM_FFMPEG_REMOTE_DIRECTORY" ] && die "FILESYSTEM_FFMPEG_REMOTE_DIRECTORY in parameters.sh needs to be defined and non-empty. Please specify it as the mountpoint (or a directory within the mount) of the filesystem"
    REMOTE_DIRECTORY=$FILESYSTEM_FFMPEG_REMOTE_DIRECTORY
fi
# Define generic parameters to use in this script by using $1 as the PREFIX_ for parameters in parameters.sh
eval LOCAL_DIRECTORY='$'"${1}"_FFMPEG_LOCAL_DIRECTORY
eval TEST_OUTPUT='$'"${1}"_FFMPEG_TEST_OUTPUT
eval REPEATS='$'"${1}"_FFMPEG_REPEATS
# Time to sleep between runs, to allow for server-side caches to time out.
eval SLEEP_TIME_SECONDS='$'"${1}"_FFMPEG_SLEEP_TIME_SECONDS
test_size=1.21072
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
eval WARM_UP_REPEATS='$'"${1}"_FFMPEG_WARM_UP_REPEATS
eval MIN_TEST_FILE_SIZE_GiB='$'"${1}"_FFMPEG_MIN_TEST_FILE_SIZE_GiB

warn "-- STARTING $1 FFMPEG BENCHMARK --"
warn "PARAMETERS:"
warn "  - REMOTE_DIRECTORY: ${REMOTE_DIRECTORY}"
warn "  - LOCAL_DIRECTORY: $(realpath "${LOCAL_DIRECTORY}")"
warn "  - TEST_OUTPUT: ${TEST_OUTPUT}"
warn "  - REPEATS: ${REPEATS}"
warn "  - SLEEP_TIME_SECONDS: ${SLEEP_TIME_SECONDS}"
warn "  - WARM_UP_REPEATS: ${WARM_UP_REPEATS}"
warn "  - MIN_TEST_FILE_SIZE_GiB: ${MIN_TEST_FILE_SIZE_GiB}" 

cleanup_trap() {
    trap - EXIT 2 6 15
    warn "-- Post-test cleanup --"
    [ -z "$DONT_CLEAN_UP" ] && cleanup
    warn "-- FINISHED FFMPEG BENCHMARK --"
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
    $CUNO_RUN_COMMAND mkdir -p "$REMOTE_DIRECTORY" || die "Failed to create '$REMOTE_DIRECTORY'. Please ensure the current user '`whoami`' has sufficient permissions, and that you have write access."
    # S3 Mountpoint doesn't support touch a file on S3, so we need to do it locally and copy across to test for write access
    touch ./tmp_file_to_test_setup
    # S3 Mountpoint never allows overwriting a file, so delete it first if it exists
    $CUNO_RUN_COMMAND rm -f "$REMOTE_DIRECTORY/test_setup" || true
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
    rm -rf $LOCAL_DIRECTORY/dst/* | tee -a $TEST_OUTPUT || die "Failed to delete contents of local directory '$LOCAL_DIRECTORY/dst/'. Is this error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
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
    warn "  -- Preparing local"

    if ! command -v ffmpeg &> /dev/null ; then 
        warn "    -- Fetching ffmpeg"
        export FFMPEG=$LOCAL_DIRECTORY/ffmpeg-master-latest-linux64-gpl/bin/ffmpeg
        # Don't repeat this if we don't have to
        if [ ! -f "$FFMPEG" ] ; then 
            # Clean up anything there if it happens to exist
            rm -rf "$FFMPEG" || true 
            wget "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz" -P "$LOCAL_DIRECTORY" || die "Failed to download https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz locally."
            tar -C "$LOCAL_DIRECTORY" -xf "$LOCAL_DIRECTORY/ffmpeg-master-latest-linux64-gpl.tar.xz" 
            rm "$LOCAL_DIRECTORY/ffmpeg-master-latest-linux64-gpl.tar.xz" || die "Failed to delete local file '$LOCAL_DIRECTORY/ffmpeg-master-latest-linux64-gpl.tar.xz'. Please ensure that the user '`whoami`' has sufficent permissions."
        fi
    else
        export FFMPEG=ffmpeg
    fi
    
    if [ ! -f "$LOCAL_DIRECTORY/bbb.ts" ] ; then
        warn "    -- Fetching Big Buck Bunny mp4"
        # clean up anything there if it happens to exist
        rm -rf "$LOCAL_DIRECTORY/bbb.ts" || true 
        # Use 1080p 30fps because it is smallest, and therefore we can try to hit "MIN_TEST_FILE_SIZE_GiB" parameter more closely.
        wget "https://download.blender.org/demo/movies/BBB/bbb_sunflower_1080p_30fps_normal.mp4.zip" -P "$LOCAL_DIRECTORY" || die "Failed to download https://download.blender.org/demo/movies/BBB/bbb_sunflower_1080p_30fps_normal.mp4.zip locally."
        unzip -o "$LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4.zip" -d $LOCAL_DIRECTORY || die "Failed to extract mp4 from $LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4.zip file"
        rm "$LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4.zip"  || die "Failed to delete $LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4.zip"
        # Convert into mpeg-ts because mpeg-ts can be appended to itself to create a larger test file, and because writing an mp4 is a good test or random-write ability of a filesystem.
        warn "    -- Remuxing mp4 to mpeg-ts locally "
        $FFMPEG -hide_banner -loglevel error -i "$LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4" -c copy "$LOCAL_DIRECTORY/bbb.ts" || die "Failed to remux $LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4 to $LOCAL_DIRECTORY/bbb.ts (mpeg-ts)"
        rm "$LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4" || die "Failed to delete $LOCAL_DIRECTORY/bbb_sunflower_1080p_30fps_normal.mp4"
    fi
    
    warn "    -- Concatenating mpeg-ts to get to the desired minimum file size "
    rm -f "$LOCAL_DIRECTORY/bbb_concat.ts" || true
    # 1024*1024*1024 = 1073741824 Bytes in 1 GiB
    SIZE=$((MIN_TEST_FILE_SIZE_GiB*1073741824))
	current_size=0
    while [[ "${current_size}" -lt "${SIZE}" ]]; do
        cat "$LOCAL_DIRECTORY/bbb.ts" >> "$LOCAL_DIRECTORY/bbb_concat.ts" || die "Check that your ramdisk is large enough to accomodate the MIN_TEST_FILE_SIZE_GiB: $MIN_TEST_FILE_SIZE_GiB GiB"
        current_size=$(stat -c "%s" "$LOCAL_DIRECTORY/bbb_concat.ts")
    done
    echo "Test mpeg-ts file size is $(echo "scale=2; $current_size/1073741824" | bc) GiB "
    test_size=$(echo "scale=2; $current_size/1073741824" | bc)
    # Place the correctly-size mpeg-ts file into the local and remote src directories
    mv $LOCAL_DIRECTORY/bbb_concat.ts $LOCAL_DIRECTORY/src/bbb_concat.ts
    $CUNO_RUN_COMMAND bash -c "cp $LOCAL_DIRECTORY/src/bbb_concat.ts $REMOTE_DIRECTORY/src/bbb_concat.ts"
}

attempt_burst() {
    clear_cache || break
    for i in {0..200}
    do 
        $CUNO_RUN_COMMAND cat $REMOTE_DIRECTORY/src/ >/dev/null 2>/dev/null || break
    done
    clear_cache || break
}

remux_local_remote() {
    echo "running local to remote"
    # Dear users, don't copy this behaviour. We have intentionally used "cuno run" on individual commands here to promote isolation. You should prefer to just run the entirety of your scripts with cuno activated to benefit from our latency hiding and metadata caching.
    $CUNO_RUN_COMMAND bash -c "$FFMPEG -hide_banner -loglevel error -i ""$LOCAL_DIRECTORY/src/bbb_concat.ts"" -c copy $1/bbb_concat.mp4" | tee -a "$TEST_OUTPUT" || die "Error during remote write, aborting benchmark. If the error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
}

remux_remote_local() {
    # Dear users, don't copy this behaviour. We have intentionally used "cuno run" on individual commands here to promote isolation. You should prefer to just run the entirety of your scripts with cuno activated to benefit from our latency hiding and metadata caching.
    $CUNO_RUN_COMMAND bash -c "$FFMPEG -hide_banner -loglevel error -i $REMOTE_DIRECTORY/src/bbb_concat.ts -c copy $LOCAL_DIRECTORY/dst/bbb_concat.mp4" | tee -a $TEST_OUTPUT || die "Error during remote read, aborting benchmark. If the error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
}

copy_local_remote() {
    # Dear users, don't copy this behaviour. We have intentionally used "cuno run" on individual commands here to promote  isolation. You should prefer to just run the entirety of your scripts with cuno activated to benefit from our latency hiding and metadata caching.
    $CUNO_RUN_COMMAND bash -c "cp -r $LOCAL_DIRECTORY/src $1" | tee -a $TEST_OUTPUT || die "Error during copy from $LOCAL_DIRECTORY/src to $REMOTE_DIRECTORY/dst, aborting benchmark. If the error persists, create an issue here https://cunofs.youtrack.cloud/issues or contact support@cuno.io"
}

warm_up_write () {
    i=0
    while [[ "${i}" -lt "${WARM_UP_REPEATS}" ]]; do
        copy_local_remote "${REMOTE_DIRECTORY}/dst/test"
        i=$((i + 1))
    done
    clear_dest_remote 
}

test_setup

warn "-- Cleaning up test directories --"
cleanup 

warn "-- Creating test directories --"
create_source_directories

warn "-- Setup test files --"
setup_source_files

# warn "-- Exhaust burst --"
# attempt_burst

warn "-- Writing $WARM_UP_REPEATS time(s) as warm up --"
warm_up_write

warn "-- Run Benchmarks --"

if [[ -z "$DONT_RUN_WRITE" ]]; then
    warn "-------------------------- FFMPEG REMUX LOCAL TO REMOTE (WRITE) -------------------------------"
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
        remux_local_remote $current_remote_directory
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
    warn "--------------------------- FFMPEG REMUX REMOTE TO LOCAL (READ) --------------------------------"
    i=0
    sum=0
    while [[ "${i}" -lt "${REPEATS}" ]]; do
        clear_dest_local

        clear_cache
        # Sleep to let server-side caches expire 
        warn "  -- sleeping for $SLEEP_TIME_SECONDS" 
        sleep $SLEEP_TIME_SECONDS
        start=$(date +%s.%N)
        remux_remote_local
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