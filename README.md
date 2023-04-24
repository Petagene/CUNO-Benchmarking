[TOC]

# Purpose
   
This benchmarking suite is meant to evaluate and compare the read/write performance of object storage access through CUNO against other storage types (e.g. local storage such as `EXT4`, shared storage such as `Lustre`/`NAS`/`SAN`, etc). Each script in the `./benchmark-scripts` directory will evaluate the expected performance of CUNO for different workloads on the current machine (large file access, small file access, etc...).
   
# Requirements

- A Linux machine or instance with lots of memory and high speed networking.
	- e.g.: AWS EC2 instance size: `c5n.x18large` (which has `192GB` of RAM).
	- Recommended AWS EC2 AMI if using AWS: `Amazon Linux 2`, otherwise `RedHat`/`Rocky`/`Ubuntu`/`Fedora`/`...`.
- Credentials for the test buckets.
- A ramdisk of size `TEST_FILE_SIZE_GiB * 5` (or more) setup on the instance.
	- `TEST_FILE_SIZE_GiB` is configurable in `benchmark_scripts/large_file_benchmark.sh`.
	- A `160GiB`-large ramdisk can be setup as follows, mounted on the `./ramdisk/` directory: `mkdir ramdisk; sudo mount -t tmpfs -o size=160G tmpfs ramdisk`.
   - Note: Since ramdisks are in-memory storage, they aren't limited by the disk's bandwidth, which is why a `tmpfs` ramdisk is required for these benchmarks.
   
# Setup

1. Clone this directory:
```bash
   git clone https://github.com/Petagene/CUNO-Benchmarking.git
```
2. Install cuno.
3. Import the object storage credentials into cuno
(this could be a credentials file similar to `~/.aws/credentials`, depending on your object storage solution):
```bash
   cuno creds import credentials.txt
```
4. Create a large ramdisk sufficient for testing performance to/from object storage (at least `5x16GiB` if using `16GiB` test files):
```bash
   mkdir ramdisk
   sudo mount -t tmpfs -o size=85G tmpfs ramdisk
```
5. Change directory to this ramdisk, and create a new benchmark directory on this ramdisk:
```bash
   cd ramdisk
   mkdir benchmark
```
6. Modify the benchmark script header to point to the test bucket (by modifying the `BUCKET` variable):
   * You can also optionally change the default values of other parameters.
```bash
   ###
   BUCKET=my_unique_bucket_name
   ###
```
7. Launch cuno:
```bash
   cuno
```
8. Launch the desired benchmark:
   * e.g.:
```bash
  <path/to/CUNO-Benchmarking>/benchmark-scripts/large_file_benchmark.sh
```
or (amongst others):
```bash
  <path/to/CUNO-Benchmarking>/benchmark-scripts/linux_source_benchmark.sh
```
   
# Benchmarking Paramters

Benchmark scripts can be found in `benchmark-scripts`.
At the top of each script file there are configurable variables.
These should be configured for the relevant setups.
For example:
```bash
BUCKET=bucket1
REMOTE_DIRECTORY=test_dir
REMOTE_PREFIX=s3://
LOCAL_DIRECTORY=benchmark
TEST_OUTPUT=test_results.txt
REPEATS=2
TEST_FILE_SIZE_GiB=16
```

# Different Benchmarks  

This benchmarking suite can test different aspects of CUNO:
   - `benchmark-scripts/large_file_benchmark.sh` will benchmark the copying of multiple large files (recommended at lease`16GiB` per file).
   - `benchmark-scripts/linux_source_benchmark.sh` will benchmark the copying of a large amount of small files (74999 files of the linux source code).
   - `benchmark-scripts/ebs_large_file_benchmark.sh` will benchmark the copying of multiple large files using an EBS mount.
   - `benchmark-scripts/ebs_linux_source_benchmark.sh` will benchmark the copying of a large amount of small files (74999 files of the linux source code) to an EBS mount.
   - `benchmark-scripts/ls_benchmark.sh` will benchmark the `ls` time for 10000 files.
   
      - The `ls` script can be modified (removal of the `S3_PREFIX`) to allow listing tests locally.
   - `benchmark-scripts/run_all.sh` will run all the above cases.
