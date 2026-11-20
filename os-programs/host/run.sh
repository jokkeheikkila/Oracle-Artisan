#!/bin/bash
# This script is invoked from Oracle DB scheduler (program OS_PROGRAM_PROG)
#
# Author: Jokke Heikkilä, 07.01.2014
#
# Argument usage:
#  $1 = script file to be executed (in the same folder as this script)
#  $2 = return code file
#  $3 = return message file
#  $4-n = other attributes
#
# Output files are written to the folder "output" under this folder.
# Directory OS_PROGRAM_OUTPUT_DIR must point to that folder.

set -e

cd "$(dirname "$0")"

./$1 $4 $5 $6 $7 $8 $9 ${10} ${11} ${12} ${13} ${14} ${15} ${16} ${17} ${18} ${19} ${20} >  output/$3 2>&1 || {
  echo "0"         >  output/$2
  echo "ERROR"     >> output/$3
  exit 0;
}

echo "1"           >  output/$2
echo "SUCCESS"     >> output/$3

exit 0
