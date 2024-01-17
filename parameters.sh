#!/bin/bash

# Parameters for benchmark_scripts/large_file_benchmark.sh #
FB_BUCKET=                       #required
FB_REMOTE_DIRECTORY=test_directory
FB_REMOTE_PREFIX=s3://
FB_LOCAL_DIRECTORY=benchmark
FB_TEST_OUTPUT=test_results.txt
FB_REPEATS=2
FB_TEST_FILE_SIZE_GiB=16
FB_NB_TEST_FILES=5


# Parameters for benchmark_scripts/linux_source_benchmark.sh #
SB_BUCKET=                       #required
SB_REMOTE_DIRECTORY=test_directory
SB_REMOTE_PREFIX=s3://
SB_LOCAL_DIRECTORY=benchmark
SB_TEST_OUTPUT=test_results.txt
SB_REPEATS=2


# Parameters for benchmark-scripts/fs_large_file_benchmark.sh #
FF_REMOTE_DIRECTORY=             #required
FF_LOCAL_DIRECTORY=benchmark
FF_TEST_OUTPUT=test_results.txt
FF_REPEATS=2
FF_TEST_FILE_SIZE_GiB=16
FF_NB_TEST_FILES=5


# Parameters for benchmark-scripts/fs_linux_source_benchmark.sh #
FS_REMOTE_DIRECTORY=             #required
FS_LOCAL_DIRECTORY=benchmark
FS_TEST_OUTPUT=test_results.txt
FS_REPEATS=2


# Parameters for benchmark-scripts/ls_benchmark.sh #
LS_BUCKET=                       #required
LS_REMOTE_DIRECTORY=test_directory
LS_REMOTE_PREFIX=s3://
LS_LOCAL_DIRECTORY=benchmark
LS_TEST_OUTPUT=test_results.txt
LS_REPEATS=2
