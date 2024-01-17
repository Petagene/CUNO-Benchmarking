**Version 1.0.2**

# Table of Contents

1. [Introduction](#introduction)
2. [Requirements](#requirements)
3. [Test Setup](#test-setup)
   - [Available Benchmarks and Options](#available-benchmarks-and-options)
4. [Running a Benchmark](#running-a-benchmark)
   - [cunoFS](#cunofs-direct-interception)
   - [Other Filesystems](#other-filesystems)

# Introduction
   
This is a collection of scripts that measure the performance of cunoFS across different tasks and workloads.
They also let you compare cunoFS with other common storage types (e.g. ext4, [EBS](https://aws.amazon.com/ebs/), [Lustre](https://www.lustre.org/), NAS and SAN).
   
# Requirements

- A Linux client with sufficent memory and high speed networking
	- e.g.: AWS EC2 instance size: `c5n.x18large` (which has `192GB` of RAM)
	- Recommended EC2 AMI if using AWS: `Amazon Linux 2`
- Read and write access for your test buckets/containers.
- A ramdisk of size `100GiB` or more for the default settings (it can be set lower or higher if the test parameters are changed)
	- A ramdisk can be created and mounted on `./ramdisk` as follows: `mkdir -p ramdisk; sudo mount -t tmpfs -o size=170G tmpfs ramdisk`

The following tools need to be installed:
   - tee
   - tar
   - bc
   - awk
   - wget
   - dd   

# Test Setup

Each benchmark script has configurable parameters, which can be changed for the relevant setups.
All of the test parameters can be changed in the `~/CUNO_Benchmarking/parameters.sh` file at the base of the repository.
Only the parameters marked as `#required` are necessary to add, the other ones have default values.

## Available Benchmarks and Options

This benchmarking suite can test different aspects of cunoFS, and compare them to other filesystems.

### cunoFS Direct Interception Large File Benchmark
Read/write performance of copying large files to and from object storage with cunoFS Direct Interception.
- Script: `benchmark-scripts/run_cuno_large_file_benchmark.sh` 
- Recommended parameters:
   - `CUNO_LF_TEST_FILE_SIZE_GiB=16` or more
   - `CUNO_LF_NUM_TEST_FILES=5`
- Required parameters:
   - `CUNO_LF_BUCKET` needs to be manually specified.

### cunoFS Direct Interception Small File Benchmark
Read/write performance of copying a large amount of small files (74999 files in the linux kernel source) to and from object storage with cunoFS Direct Interception.
- Script: `benchmark-scripts/run_cuno_small_file_benchmark.sh` 
- Required parameters:
   - `CUNO_SF_BUCKET` needs to be manually specified

### Filesystem Large File Benchmark
Read/write performance of copying large files to and from any mounted filesystem (`EBS`, `EFS`, `cunoFS Mount`, etc...).
- Script: `benchmark-scripts/run_filesystem_large_file_benchmark.sh` 
- Recommended parameters:
   - `FILESYSTEM_LF_TEST_FILE_SIZE_GiB=16` or more
   - `FILESYSTEM_LF_NB_TEST_FILES=5`
- Required parameters:
   - `FILESYSTEM_LF_REMOTE_DIRECTORY` needs to be manually specified

### Filesystem Small File Benchmark
Read/write performance of copying a large amount of small files (74999 files in the linux kernel source) to and from any mounted filesystem
- Script: `benchmark-scripts/run_filesystem_small_file_benchmark.sh` 
- Required parameters:
   - `FILESYSTEM_SF_REMOTE_DIRECTORY` needs to be manually specified

### cunoFS Direct Interception Listing Benchmark
- Script: `benchmark-scripts/ls_benchmark.sh`
- Tests: will benchmark the `ls` time for 10000 files
- Required parameters:
   - `LS_BUCKET` needs to be manually specified
- Needs to be run inside a cunoFS activated shell, start one by running `cuno`.

# Running a benchmark

## cunoFS Direct Interception

1. Clone this directory to your home directory:
```bash
git clone https://github.com/Petagene/CUNO-Benchmarking.git ~/CUNO_Benchmarking
```
2. [Download, install and activate cunoFS](https://cuno-cunofs.readthedocs-hosted.com/en/stable/getting-started-download-and-installation.html) - make sure to register for a commercial evaluation [here](https://cuno.io/register).
3. [Import your object storage credentials](https://cuno-cunofs.readthedocs-hosted.com/en/stable/getting-started-configuring-credentials.html)
4. Create a ramdisk large enough for your configured benchmarking options (e.g. at least `5x32GiB + 10GiB` if using `32GiB` test files):
```bash
mkdir -p ramdisk
sudo mount -t tmpfs -o size=170G tmpfs ramdisk
```
5. Change directory to this ramdisk, and create a new benchmark directory on this ramdisk:
```bash
cd ramdisk
mkdir -p benchmark
```
6. Modify the test parameters in `~/CUNO_Benchmarking/parameters.sh` to point to your test bucket (by modifying the `CUNO_{LF/SF}_BUCKET` variables):
   * You can also optionally change the default values of other parameters if you wish to change the testing environment.
```bash
###
CUNO_LF_BUCKET=my_test_bucket         #required
###
CUNO_SF_BUCKET=my_test_bucket         #required
###
```
7. Modify any other related options, see [Benchmarking Options](#available-benchmarks-and-options).  
8. Run with `benchmark-scripts/run_cuno_{large_file/small_file}_benchmark.sh`

## Other filesystems

We assume you have already mounted your other filesystem and it is accessible and writable.

1. Clone this directory:
```bash
git clone https://github.com/Petagene/CUNO-Benchmarking.git ~/CUNO-Benchmarking
```
2. Create a ramdisk large enough for your configured benchmarking options (e.g. at least `5x32GiB + 10` if using `32GiB` test files):
```bash
mkdir -p ramdisk
sudo mount -t tmpfs -o size=170G tmpfs ramdisk
```
3. Change directory to this ramdisk, and create a new benchmark directory on this ramdisk:
```bash
cd ramdisk
mkdir -p benchmark
```
4. Modify the test parameters in `~/CUNO_Benchmarking/parameters.sh` to point to the mount location of the filesystem you want to test (by modifying the `FILESYSTEM_{LF/SF}_REMOTE_DIRECTORY` variables):
   * You can also optionally change the default values of other parameters if you wish to change the testing environment
```bash
###
FILESYSTEM_LF_REMOTE_DIRECTORY=/mnt/ebs_fs        #required
###
FILESYSTEM_SF_REMOTE_DIRECTORY=/mnt/lustre_fs     #required
###
```
5. Modify any other related options, see [Benchmarking Options](#available-benchmarks-and-options). 
6. Run with `benchmark-scripts/run_filesystem_{large_file/small_file}_benchmark.sh`
