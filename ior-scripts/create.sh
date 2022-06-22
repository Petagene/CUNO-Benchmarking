#!/bin/bash

export LD_PRELOAD="/shared/cuno.so"
export AWS_SECRET_ACCESS_KEY="."
export AWS_ACCESS_KEY_ID="."
export S3_PATH="."

if [[ "$#" -ne 2 ]]; then
    echo "Illegal number of parameters"
fi

i=$1
while [[ $i -le $2 ]]; do
        digits=${#i}
        zeros=$(echo 8-${digits} | bc -l)
        filename="/cuno/s3/$S3_PATH/."
	while [[ ${zeros} -gt 0  ]]; do
		filename="${filename}0"
		zeros=$((zeros-1))
	done
	filename="${filename}$i"
	echo -e "Creating $filename"
	dd if=/dev/zero of=$filename bs=64M count=256 iflag=fullblock
	i=$((i+1))
done
