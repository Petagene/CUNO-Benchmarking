[TOC]

#### Requirements

- An EC2 instance with CUNO installed.
	- Recommended instance size: c5n.x18large
	- Recommended AMI: Amazon Linux 2
- Credentials installed for the test buckets.
- A ramdisk of size (TEST_FILE_SIZE_GiB*5) setup on the instance.
	- TEST_FILE_SIZE_GiB is configurable in benchmark_scripts/large_file_benchmark.sh
	- ramdisks can be setup as follows (160GiB): `mkdir ramdisk; sudo mount -t tmpfs -o size=160G tmpfs ramdisk`
#### Setup
Benchmark scripts can be found in `benchmark-scripts`. At the top of each script file there are configurable variables. These should be configured for the relevant setups. For example:
```bash
BUCKET=bucket1
REMOTE_DIRECTORY=test_dir
REMOTE_PREFIX=s3://
LOCAL_DIRECTORY=local_test
TEST_OUTPUT=test_results.txt
REPEATS=2
TEST_FILE_SIZE_GiB=1
```
-- Here BUCKET, is the remote bucket you want to test `cp` to and from. 
-- Remote directory and local directory are directories created for this testing. Local directory should be inside the ramdisk directory: eg. `ramdisk/test_local`. 
-- Test_file_size_gib is the size of test files that will be created and `cp'd`. There are 5 files of this size generated. So ensure the ramdisk is sufficient.

The script directory can be SCPed to the script directory `scp -r -i KEY.pem scripts ec2-user@IP4:.`

#### Running
Once CUNO is installed and the ramdisk is created and all script variables are configured, a variety of tests can be run.
`benchmark-scripts/large_file_benchmark.sh` will benchmark the copying of multiple large files (recommended 16GiB per file).
`benchmark-scripts/linux_source_benchmark.sh` will benchmark the copying of a large amount of small files (74999 files of the linux source code).
`benchmark-scripts/ebs_large_file_benchmark.sh` will benchmark the copying of multiple large files using an EBS mount.
`benchmark-scripts/ebs_linux_source_benchmark.sh` will benchmark the copying of a large amount of small files (74999 files of the linux source code) to an EBS mount.
`benchmark-scripts/ls_benchmark.sh` will benchmark the ls time for 10000 files.
The ls script can be modified (removal of the S3_PREFIX) to allow listing tests locally.
`benchmark-scripts/run_all.sh` will run all the above cases.

