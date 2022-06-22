REMOTE_DIRECTORY=ebs_folder
LOCAL_DIRECTORY=local_test
TEST_OUTPUT=test_results.txt
REPEATS=2
TEST_FILE_SIZE_GiB=16

cleanup() {
    rm -rf "$LOCAL_DIRECTORY/src"
    rm -rf "$LOCAL_DIRECTORY/dst"

    rm -rf "$REMOTE_DIRECTORY/$LOCAL_DIRECTORY"
    rm -rf "$REMOTE_DIRECTORY/$LOCAL_DIRECTORY"
}
create_source_directories() {
    mkdir -p $LOCAL_DIRECTORY/src
    mkdir -p $LOCAL_DIRECTORY/dst
    mkdir -p $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src
    mkdir -p $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst
}

clear_cache() {
    sudo sync; echo 3 > sudo sh -c "/usr/bin/echo 3 > /proc/sys/vm/drop_caches"
}

setup_source_files() {
    #dd if=/dev/zero of=$LOCAL_DIRECTORY/src/gen_file count=1048576 bs=$((1024*$TEST_FILE_SIZE_GiB))
    echo "    -- Preparing local" | tee -a $TEST_OUTPUT
    dd if=/dev/zero of=$LOCAL_DIRECTORY/src/test_file1 count=1048576 bs=$((1024*$TEST_FILE_SIZE_GiB))
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file2
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file3
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file4
    cp $LOCAL_DIRECTORY/src/test_file1 $LOCAL_DIRECTORY/src/test_file5
    echo "    -- Uploading to cloud" | tee -a $TEST_OUTPUT
    cp -r $LOCAL_DIRECTORY/src/* $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src/.
}

attempt_burst() {
    for i in {0..1000}
    do 
        clear_cache
        cat $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src/test_file1 > /dev/null
    done
}

clear_dest_remote() {
    rm -rf $REMOTE_DIRECTORY/$LOCAL_DIRECTOR/dst | tee -a $TEST_OUTPUT
}

clear_dest_local() {
    rm -rf $LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT
}

copy_large_local_remote() {
    CUNO_CP_SPEEDUP=0 cp -r $LOCAL_DIRECTORY/src $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT
}

copy_large_remote_local() {
    CUNO_CP_SPEEDUP=0 cp -r $REMOTE_DIRECTORY/$LOCAL_DIRECTORY/src $LOCAL_DIRECTORY/dst | tee -a $TEST_OUTPUT
}

echo "-- Cleaning up test directory --" | tee -a $TEST_OUTPUT
cleanup 

echo "-- Creating test directories --" | tee -a $TEST_OUTPUT
create_source_directories

echo "-- Setup test files --" | tee -a $TEST_OUTPUT
setup_source_files

echo "-- Exhaust burst --" | tee -a $TEST_OUTPUT
attempt_burst

echo "-- Run EBS Tests --" | tee -a $TEST_OUTPUT
echo "---------------------------LARGE FILES (WRITE) --------------------------------" | tee -a $TEST_OUTPUT
i=0
sum=0
duration_sum=0
max=0
min=1000
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
    if [[ $(echo "$speed_gbps > $max" |bc -l)  ]]; then
        max=$speed_gbps
    fi
    echo "min: $min $speed_gbps"
    if [ $(echo "$speed_gbps < $min" |bc -l) ]; then
        min=$speed_gbps
    fi
    done
average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
#average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
echo "Results - Average (Gbps): $average_speed"  | tee -a $TEST_OUTPUT
echo "------------------------------------------------------------------------------------" | tee -a $TEST_OUTPUT

echo "--------------- Clear local src -----------------------"
rm -rf "$LOCAL_DIRECTORY/src"

echo "--------------------------LARGE FILES (READ)-------------------------------" | tee -a $TEST_OUTPUT
i=0
sum=0
duration_sum=0
max=0
min=1000
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
    if [[ $(echo "$speed_gbps > $max" | bc -l)  ]]; then
        max=$speed_gbps
    fi

    if [ $(echo "$speed_gbps < $min" | bc -l) ]; then
        min=$speed_gbps
    fi
    done
average_speed=$(echo "scale=5;${sum}/${REPEATS}" | bc -l | awk '{printf("%.5f",$1)}')
echo "Results - Average (Gbps): $average_speed" | tee -a $TEST_OUTPUT
echo "------------------------------------------------------------------------------------" | tee -a $TEST_OUTPUT
