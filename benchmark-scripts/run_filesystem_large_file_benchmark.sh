#!/bin/bash

_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>/dev/null && pwd)

bash -c "${_SCRIPT_DIR}/large_file_benchmark.sh FILESYSTEM"
