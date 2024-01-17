#!/bin/bash

# Parameters for benchmark_scripts/run_cuno_large_file_benchmark.sh #
CUNO_LF_REMOTE_PREFIX=s3://
CUNO_LF_BUCKET=                       #required
CUNO_LF_REMOTE_DIRECTORY=benchmark
CUNO_LF_LOCAL_DIRECTORY=benchmark
CUNO_LF_TEST_OUTPUT=test_results.txt
CUNO_LF_REPEATS=3
CUNO_LF_TEST_FILE_SIZE_GiB=32
CUNO_LF_NUM_TEST_FILES=5
# Time to sleep for between writes and between reads, to allow server-side caches to expire and to avoid hotspots of external traffic. 
CUNO_LF_SLEEP_TIME_SECONDS=300
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
CUNO_LF_WARM_UP_REPEATS=1

# Parameters for benchmark-scripts/run_filesystem_large_file_benchmark.sh #
FILESYSTEM_LF_REMOTE_DIRECTORY=             #required
FILESYSTEM_LF_LOCAL_DIRECTORY=benchmark
FILESYSTEM_LF_TEST_OUTPUT=test_results.txt
FILESYSTEM_LF_REPEATS=3
FILESYSTEM_LF_TEST_FILE_SIZE_GiB=32
FILESYSTEM_LF_NUM_TEST_FILES=5
# Time to sleep for between writes and between reads, to allow server-side caches to expire and to avoid hotspots of external traffic.
FILESYSTEM_LF_SLEEP_TIME_SECONDS=300
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
FILESYSTEM_LF_WARM_UP_REPEATS=1

# Parameters for benchmark_scripts/run_cuno_small_file_benchmark.sh #
CUNO_SF_REMOTE_PREFIX=s3://
CUNO_SF_BUCKET=                       #required
CUNO_SF_REMOTE_DIRECTORY=benchmark
CUNO_SF_LOCAL_DIRECTORY=benchmark
CUNO_SF_TEST_OUTPUT=test_results.txt
CUNO_SF_REPEATS=3
# Time to sleep for between writes and between reads, to allow server-side caches to expire and to avoid hotspots of external traffic.
CUNO_SF_SLEEP_TIME_SECONDS=300
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
CUNO_SF_WARM_UP_REPEATS=0


# Parameters for benchmark-scripts/run_filesystem_small_file_benchmark.sh #
FILESYSTEM_SF_REMOTE_DIRECTORY=             #required
FILESYSTEM_SF_LOCAL_DIRECTORY=benchmark
FILESYSTEM_SF_TEST_OUTPUT=test_results.txt
FILESYSTEM_SF_REPEATS=3
# Time to sleep for between writes and between reads, to allow server-side caches to expire and to avoid hotspots of external traffic.
FILESYSTEM_SF_SLEEP_TIME_SECONDS=300
# Number of initial write runs to discard before running benchmarks. We notice that the first run when an EC2 instance is booted up is significantly slower and not representative of real-world speeds. Without theorising why, we suggest throwing away at least 1 run when benchmarking.
FILESYSTEM_SF_WARM_UP_REPEATS=0

# Parameters for benchmark-scripts/ls_benchmark.sh #
LS_BUCKET=                       #required
LS_REMOTE_DIRECTORY=test_directory
LS_REMOTE_PREFIX=s3://
LS_LOCAL_DIRECTORY=benchmark
LS_TEST_OUTPUT=test_results.txt
LS_REPEATS=2
