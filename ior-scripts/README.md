[TOC]

#### Requirements
- An HPC setup via pcluster
	- https://www.hpcworkshops.com/04-amazon-fsx-for-lustre/01-install-pc.html
	- Recommended node size: c5n.x18large
	- Recommended AMI: Amazon Linux 2

- cuno.so installed in the created /shared directory.

#### Setup
At the top of the create.sh and read_test.batch are configurable variables. These should be configured for the relevant setups.

```
--ntasks, allows setting of the total number of tasks run.
--ntasks-per-node, defines how many jobs are run on a single node
```

The `create.sh` script will need to be run to ensure readable files are created on the server for IOR to test against.

#### Running
Once the cluster is setup and cuno is installed the read_test.batch can be runnable on the scheduler via `sbatch read_test.batch`


