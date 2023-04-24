#!/bin/bash
REMOTE_DIRECTORY=test_directory
LOCAL_DIRECTORY=benchmark
TEST_OUTPUT=test_results.txt
REPEATS=2


test_size=1.21072
fetch_linux_source() {
    wget "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-5.17.2.tar.xz"
}

cleanup() {
    rm -rf "$LOCAL_DIRECTORY/src"
    rm -rf "$LOCAL_DIRECTORY/dst"
    rm -rf "$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst"
    rm -rf "$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src"
}

create_source_directories() {
    mkdir -p $LOCAL_DIRECTORY/src
    mkdir -p $LOCAL_DIRECTORY/dst
    mkdir -p $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst
    mkdir -p $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src
}

clear_dest_remote() {
    rm -rf "$REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst" | tee -a $TEST_OUTPUT
}

attempt_burst() {
    for i in {0..1000}
    do 
        clear_cache
        cat $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src/linux-5.17.2/CREDITS > /dev/null
    done
}

clear_dest_local() {
    rm -rf $LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT
}

clear_cache() {
    sudo sync; sudo sh -c "/usr/bin/echo 3 > /proc/sys/vm/drop_caches"
    rm -rf /dev/shm/cuno*
}

setup_source_files() {
    echo "    -- Fetching linux source files" | tee -a $TEST_OUTPUT
    fetch_linux_source
    tar -xvf linux-5.17.2.tar.xz
    echo "    -- Preparing local" | tee -a $TEST_OUTPUT
    cp -L -r linux-5.17.2 $LOCAL_DIRECTORY/src/linux-5.17.2
    echo "    -- Uploading to cloud" | tee -a $TEST_OUTPUT
    cp -r $LOCAL_DIRECTORY/src/linux-5.17.2 $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src/.
    rm -rf linux-5.17.2.tar.xz
    rm -rf linux-5.17.2
}

copy_large_local_remote() {
    cp -r $LOCAL_DIRECTORY/src $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT
}

copy_large_remote_local() {
    cp -r $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src $LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT
}


echo "-- Cleaning up test directory --" | tee -a $TEST_OUTPUT
cleanup 

echo "-- Creating test directories --" | tee -a $TEST_OUTPUT
create_source_directories

echo "-- Setup test files --" | tee -a $TEST_OUTPUT
setup_source_files

echo "-- Exhaust burst --" | tee -a $TEST_OUTPUT
attempt_burst

echo "-- Run Cloud Tests --" | tee -a $TEST_OUTPUT
echo "--------------------------SMALL FILES (74999) (READ) -------------------------------" | tee -a $TEST_OUTPUT
i=0
sum=0
while [[ "${i}" -lt "${REPEATS}" ]]; do
    clear_dest_local
    clear_cache
    start=$(date +%s.%N)
    copy_large_remote_local
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;${test_size}/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done
average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
echo "Results - Average (Gbps): $average_speed"  | tee -a $TEST_OUTPUT
echo "------------------------------------------------------------------------------------" | tee -a $TEST_OUTPUT

echo "---------------------------SMALL FILES (74999) (WRITE) --------------------------------" | tee -a $TEST_OUTPUT
i=0
sum=0
while [[ "${i}" -lt "${REPEATS}" ]]; do
    clear_dest_remote
    clear_cache
    start=$(date +%s.%N)
    copy_large_local_remote
    finish=$(date +%s.%N)
    duration=$(echo "scale=5;${finish}-${start}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbips=$(echo "scale=5;${test_size}/${duration}" | bc -l | awk '{printf("%.5f",$1)}')
    speed_gbps=$(echo "scale=5;${speed_gbips}*8.58993" | bc -l | awk '{printf("%.5f",$1)}')
    echo "RUN[${i}] - Time Taken (s): $duration | Speed (Gbps): $speed_gbps | Speed (GiB/s): $speed_gbips"  | tee -a $TEST_OUTPUT
    i=$((i + 1))
    sum=$(echo "scale=5;${sum}+${speed_gbps}" | bc -l | awk '{printf("%.5f",$1)}')
    done

average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
#average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
echo "Results - Average (Gbps): $average_speed"  | tee -a $TEST_OUTPUT
echo "------------------------------------------------------------------------------------" | tee -a $TEST_OUTPUT
