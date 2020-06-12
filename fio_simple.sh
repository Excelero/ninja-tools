#!/bin/bash
#
# The flexible I/O tester (fio) provides a lot of options that can easily be overwhelming. This is a
# simple wrapper for fio to generate random IO.
# fio is available here: https://github.com/axboe/fio
#
# Author: Excelero
# Maintainer: Sven Breuner <sven[at]excelero.com>

unset FIO_PATH # path to fio executable (auto-detected)
unset FILENAMES # fio filenames generated from $DEVICE
unset RWMIXREAD # fio rwmixread generated from $READPERCENT

unset DEVICE # blockdev to use (set via cmd line arg)
unset IODEPTH # iodepth for async io (set via cmd line arg)
unset NUMJOBS # number of parallel jobs/processes (set via cmd line arg)
unset READPERCENT # percentage of read accessed (set via cmd line arg
unset BLOCKSIZE # block size for read/write (set via cmd line arg)


# Print usage info and exit
usage()
{
  echo "About:"
  echo "  The flexible I/O tester (fio) provides a lot of options that can easily be"
  echo "  overwhelming. This is a simple wrapper for fio to generate random I/O across"
  echo "  the complete size of a block device." 
  echo "  fio comes with many Linux distributions and is otherwise available here:"
  echo "  https://github.com/axboe/fio"
  echo
  echo "Usage:"
  echo "  $0 <DEVICE> <IODEPTH> <NUMJOBS> <READPERCENT> <BLOCKSIZE>"
  echo
  echo "Mandatory Arguments:"
  echo "  DEVICE      Device name in /dev or NVMesh volume name in /dev/nvmesh."
  echo "              (Can be multiple devices space-separated as single arg in quotes.)"
  echo "  IODEPTH     Number of concurrent asynchronous requests per job."
  echo "  NUMJOBS     Number of concurrent jobs (processes)."
  echo "  READPERCENT Percentage or read access. \"0\" means pure writing and \"100\""
  echo "              means pure reading."
  echo "  BLOCKSIZE   Block size of read/write accesses, e.g. \"4k\" or \"1m\"."
  echo
  echo "Examples:"
  echo "  Check read latency of NVMesh volume /dev/nvmesh/myvol:"
  echo "    $ $0 myvol 1 1 100 4k"
  echo "  Check read IOPS of device /dev/nvme0n1:"
  echo "    $ $0 nvme0n1 16 16 100 4k"
  echo "  Check write throughput of volumes /dev/nvmesh/myvol1 and /dev/nvmesh/myvol2:"
  echo "    $ $0 \"myvol1 myvol2\" 16 16 0 128k"

  exit 1
}

# Parse command line arguments
parse_args()
{
  local OPTIND # local to prevent effects from other subscripts

  while getopts ":h" opt; do
    case "${opt}" in
      h)
        # help
        usage
        ;;
      *)
        # Other option arguments are invalid
        usage
        ;;
    esac
  done

  shift $((OPTIND-1))

  # 5 here for the 5 mandatory args: DEVICE, IODEPTH etc
  if [ $# -ne 5 ]; then
    echo "ERROR: Invalid number of arguments."
    usage
  fi

  # Non-option arguments are assumed to be the mandatory command line args
  DEVICE=$1 # blockdev to use
  IODEPTH=$2 # iodepth for async io
  NUMJOBS=$3 # number of parallel jobs/processes
  READPERCENT=$4 # percentage of read accessed
  BLOCKSIZE=$5 # block size for read/write
}


# Check if fio is installed and exit if not installed.
# Sets $FIO_PATH.
find_fio_or_exit()
{
  FIO_PATH=$(which fio 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo "ERROR: fio executable not found. Try \"yum/apt install fio\" or get fio from"
    echo "here: https://github.com/axboe/fio"
    exit 1
  fi
}

# Prepare fio "--filename" args for the user-given device names.
# Sets $FILENAMES.
prepare_fio_filenames()
{
  FILENAMES=()

  for dev in $DEVICE; do
    if [ -e /dev/nvmesh/$dev ]; then
      FILENAMES+=("--filename=/dev/nvmesh/$dev")
    else
      FILENAMES+=("--filename=/dev/$dev")
    fi
  done
}

# Prepare fio "--rwmixread". For 100% read, use "--rw=randread" to avoid fio complaining about
# mounted file systems on device. For 0% read, use "--rw=randwrite" consequently.
# Sets $RWMIXREAD.
prepare_fio_rwmix()
{
  if [ $READPERCENT -eq 100 ]; then
    RWMIXREAD="--rw=randread"
  elif [ $READPERCENT -eq 0 ]; then
    RWMIXREAD="--rw=randwrite"
  else
    RWMIXREAD="--rw=randrw --rwmixread=$READPERCENT"  
  fi
}

parse_args "$@"
find_fio_or_exit
prepare_fio_filenames
prepare_fio_rwmix

fio_cmd="$FIO_PATH ${FILENAMES[@]} --iodepth=$IODEPTH --numjobs=$NUMJOBS $RWMIXREAD "
fio_cmd+="--bs=$BLOCKSIZE --direct=1 --norandommap --randrepeat=0 --verify=0 "
fio_cmd+="--ioengine=libaio --group_reporting --name=fio_simple --time_based --runtime=600"

echo "FIO COMMAND: $fio_cmd"
echo

$fio_cmd
