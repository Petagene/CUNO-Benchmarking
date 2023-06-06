#!/bin/bash
  
if [ $# -ne 1 ]; then
echo "Usage: $0 <mount_point>"
echo "This script was created to exhaust AWS EFS Burst Credits."
echo "To use it, simply pass in the path to an EFS mount point as an argument."
echo "In order to clear kernel FS caches, this script must be run as root."
exit 1
fi

# Check if the script is being run as root
if [[ $EUID -ne 0 ]]; then
  echo "In order to clear kernel FS caches, this script must be run as root."
  exit 1
fi

mount_point=$1

echo 3 > /proc/sys/vm/drop_caches

# Create a 25GB file
echo "Writing temporary file $mount_point/efs_burst_clear ..."
dd if=/dev/zero of=$mount_point/efs_burst_clear bs=1M count=25000

# Read the file back 99 times, clearing the cache each time
echo "Reading back ..."
for i in {1..99}; do
    echo 3 > /proc/sys/vm/drop_caches
    echo "$i / 99"
    dd if=$mount_point/efs_burst_clear of=/dev/null bs=1M
done

echo "Removing temporary file"
rm $mount_point/efs_burst_clear

echo "Done"
