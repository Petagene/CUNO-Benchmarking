#!/bin/bash

warn() {
   echo -e "$*" | tee -a $LS_TEST_OUTPUT
}

die() {
   warn "$*"
   exit 1
}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>/dev/null && pwd)

$SCRIPT_DIR/large_file_benchmark.sh || die "Failed to complete CUNO Large File Benchmark"
$SCRIPT_DIR/linux_source_benchmark.sh || die "Failed to complete CUNO Small File Benchmark"
 
$SCRIPT_DIR/fs_large_file_benchmark.sh || die "Failed to complete Filesystem Large File Benchmark"

$SCRIPT_DIR/fs_linux_source_benchmark.sh || die "Failed to complete Filesystem Small File Benchmark"

$SCRIPT_DIR/ls_benchmark.sh || die "Failed to complete CUNO Large File Benchmark"
