# Table Of Contents

1. [Introduction](#Introduction)
2. [Requirements](#Requirements)
3. [Test Setup](#test-setup)
   - [CUNO](#cuno)
   - [Other Storage Medium](#other-storage-medium)
4. [Running A Benchmark](#running-a-benchmark)
5. [Benchmarking Options](#benchmarking-options)
6. [Available Benchmarks](#available-benchmarks)
7. [Program Requirements](#program-requirements)
   
# Introduction
   
This is a collection of scripts that measure the performance of CUNO across different tasks and workloads.
They also let you compare CUNO with other common storage types (e.g. ext4, [EBS](https://aws.amazon.com/ebs/), [Lustre](https://www.lustre.org/), NAS and SAN).
   
# Requirements

- A Linux client with sufficent memory and high speed networking
	- e.g.: AWS EC2 instance size: `c5n.x18large` (which has `192GB` of RAM)
	- Recommended EC2 AMI if using AWS: `Amazon Linux 2`
- Credentials for your test buckets.
- A ramdisk of size `100GiB` or more for the default settings (it can be set lower or higher if the test parameters are changed)
	- A ramdisk can be created and mounted on `./ramdisk` as follows: `mkdir -p ramdisk; sudo mount -t tmpfs -o size=100G tmpfs ramdisk`
   

# Test Setup
   
## CUNO

1. Clone this directory:
```bash
git clone https://github.com/Petagene/CUNO-Benchmarking.git ~/CUNO_Benchmarking
```
2. Install cuno
3. Import the object storage credentials into cuno
(this could be a credentials file similar to `~/.aws/credentials`, depending on your object storage solution):
```bash
cuno creds import credentials.txt
```
4. Create a large ramdisk sufficient for testing performance to/from object storage (at least `5x16GiB + 16` if using `16GiB` test files):
```bash
mkdir -p ramdisk
sudo mount -t tmpfs -o size=100G tmpfs ramdisk
```
5. Change directory to this ramdisk, and create a new benchmark directory on this ramdisk:
```bash
cd ramdisk
mkdir -p benchmark
```
6. Modify the test parameters in `parameters.sh` to point to your test bucket (by modifying the `xx_BUCKET` variables):
   * You can also optionally change the default values of other parameters if you wish to change the testing environment.
```bash
###
FB_BUCKET=my_test_bucket         #required
###
SB_BUCKET=my_test_bucket         #required
###
```
7. Launch cuno:
```bash
cuno
```

## Other Storage Medium

1. Clone this directory:
```bash
git clone https://github.com/Petagene/CUNO-Benchmarking.git ~/CUNO-Benchmarking
```
2. Create a large ramdisk sufficient for testing performance to/from object storage (at least `5x16GiB + 16` if using `16GiB` test files):
```bash
mkdir -p ramdisk
sudo mount -t tmpfs -o size=100G tmpfs ramdisk
```
3. Change directory to this ramdisk, and create a new benchmark directory on this ramdisk:
```bash
cd ramdisk
mkdir -p benchmark
```
4. Modify the test parameters in `parameters.sh` to point to the mount location of the filesystem you want to test (by modifying the `xx_REMOTE_DIRECTORY` variables):
   * You can also optionally change the default values of other parameters if you wish to change the testing environment
```bash
###
FF_REMOTE_DIRECTORY=/mnt/ebs_fs        #required
###
FS_REMOTE_DIRECTORY=/mnt/lustre_fs     #required
###
```

# Running A Benchmark

After completing the relevant [Test Setup](#test-setup), you can run the benchmark with:
```bash
~/CUNO-Benchmarking/benchmark-scripts/fs_linux_source_benchmark.sh
```
or
```bash
~/CUNO-Benchmarking/benchmark-scripts/fs_linux_source_benchmark.sh
```


# Benchmarking Options

Each benchmark script has configurable parameters, which can be changed for the relevant setups.
All of the test parameters can be changed in the `./parameters.sh` file at the base of the repository.
Only the parameters marked as `#required` are necessary to add, the other ones have default values.

For example, to configure `large_file_benchmark.sh` to use the bucket `test_bucket`, you should write:
```bash
# Parameters for benchmark_scripts/large_file_benchmark.sh #
FB_BUCKET=test_bucket            #required
FB_REMOTE_DIRECTORY=test_directory
FB_REMOTE_PREFIX=s3://
FB_LOCAL_DIRECTORY=benchmark
FB_TEST_OUTPUT=test_results.txt
FB_REPEATS=2
FB_TEST_FILE_SIZE_GiB=16
FB_NB_TEST_FILES=5
```

# Available Benchmarks

This benchmarking suite can test different aspects of CUNO, and compare them to other filesystems:
   - `CUNO Large File Benchmark`: Read/write performance of copying large files to and from object storage with CUNO
      - Script: `benchmark-scripts/large_file_benchmark.sh` 
      - Recommended parameters:
         - `FB_TEST_FILE_SIZE_GiB=16` or more
         - `FB_NB_TEST_FILES=5`
      - Required parameters:
         - `FB_BUCKET=` needs to be manually specified.
   - `CUNO Small File Benchmark`: Read/write performance of copying a large amount of small files (74999 files in the linux kernel source tarball) to and from object storage with CUNO
      - Script: `benchmark-scripts/linux_source_benchmark.sh` 
      - Required parameters:
         - `SB_BUCKET=` needs to be manually specified
   - `Filesystem Large File Benchmark`: Read/write performance of copying large files to and from any filesystem (`EBS`, `EFS`, etc...)
      - Script: `benchmark-scripts/fs_large_file_benchmark.sh` 
      - Recommended parameters:
         - `FF_TEST_FILE_SIZE_GiB=16` or more
         - `FF_NB_TEST_FILES=5`
      - Required parameters:
         - `FF_REMOTE_DIRECTORY=` needs to be manually specified
   - `Filesystem Small File Benchmark`: Read/write performance of copying a large amount of small files (74999 files in the linux kernel source tarball) to and from any filesystem
      - Script: `benchmark-scripts/fs_linux_source_benchmark.sh` 
      - Required parameters:
         - `FS_REMOTE_DIRECTORY=` needs to be manually specified
   - `ls Benchmark`:
      - Script: `benchmark-scripts/ls_benchmark.sh`
      - Tests: will benchmark the `ls` time for 10000 files
      - Required parameters:
         - `LS_BUCKET=` needs to be manually specified
   - `Run All Benchmarks Above`:
      - Script: `benchmark-scripts/run_all.sh`

Note:
It is possible to test CUNO-mount with the filesystem benchmarks.

# Program Requirements

This suite requires the following tools in order to function properly:
   - tee
   - tar
   - bc
   - awk
   - wget
   - dd
