#!/bin/bash
#
# Test individual drives in an NVMesh instance: Create a volume per drive, attach them to localhost
# and run an arbitrary command on each single-drive volume. Uses the nvmesh CLI to discover drives.
#
# Author: Sven Breuner
# Maintainer: Sven Breuner <sven[at]excelero.com>


# Initialize defaults...
NVMESH_MARJOR_VER=2 # required major version of nvmesh CLI
LIST_DRIVES=0 # set via cmd line arg to print drives
CREATE_VOLUMES=0 # set via cmd line arg to create volumes
VOLUME_SIZE="1G" # size to pass as capacity to "nvmesh volume create"
VOLUME_PREFIX="drv_" # name prefix for created NVMesh volumes
ATTACH_VOLUMES=0 # set via cmd line arg to attach created volumes
DETACH_VOLUMES=0 # set via cmd line arg to detach created volumes
DELETE_VOLUMES=0 # set via cmd line arg to delete created volumes
unset DELETE_NOCONFIRM # set via cmd line arg to delete without confirmation
unset PER_DRIVEVOL_USER_CMD # set via cmd line arg to run this for each single drive volume


# Print usage info and exit
usage()
{
  echo "About:"
  echo "  Test individual drives in an NVMesh instance: Create a volume for each drive,"
  echo "  attach them to localhost and run an arbitrary command on each single-drive" 
  echo "  volume. Uses the nvmesh CLI to discover drives."
  echo
  echo "Usage:"
  echo "  $0 <Mode> [More Modes] [Options] [Command [Command Arguments] ]"
  echo
  echo "Modes:"
  echo "  -l          List serial numbers of drives, filtered to show only usable drives."
  echo "  -c          Create a (concatenated) volume for each usable drive, using the"
  echo "              volume prefix and the drive serial number as volume name."
  echo "  -a          Attach volumes to localhost."
  echo "  -d          Detach volumes from localhost."
  echo "  -D          Delete volumes."
  echo "  Command     Run the given command for each created volume. \"%VOL%\" in"
  echo "              command or its arguments will be replaced by the name of each"
  echo "              volume."
  echo
  echo "Options:"
  echo "  -s NUM      Size to pass as capacity to \"nvmesh volume create\". (Default: 1G)"
  echo "  -p STRING   Volume name prefix for \"nvmesh volume create\". (Default: \"drv-\")"
  echo "  -N          No ask for confirmation on volume deletion."
  echo 
  echo "Examples:"
  echo "  $ $0 -c -a"
  echo "  $ $0 fio --filename=/dev/nvmesh/%VOL% \\"
  echo "    --time_based --runtime=5 --direct=1 --ioengine=libaio --group_reporting \\"
  echo "    --name=test --rw=randread --bs=4k --numjobs=10 --iodepth=10"
  echo "  $ $0 -d -D"

  exit 1
}

# Parse command line arguments
parse_args()
{
  local OPTIND # local to prevent effects from other subscripts

  if [ $# -eq 0 ]; then
    echo "ERROR: No mode selected."
    usage
  fi

  while getopts ":aDdclNp:s:" opt; do
    case "${opt}" in
      a)
        # Attach volumes
        ATTACH_VOLUMES=1
        ;;
      c)
        # Create one volume for each drive
        CREATE_VOLUMES=1
        ;;
      D)
        # Delete volumes
        DELETE_VOLUMES=1
        ;;
      d)
        # Detach volumes
        DETACH_VOLUMES=1
        ;;
      l)
        # List usable drive serial numbers
        LIST_DRIVES=1
        ;;
      N)
        # No ask for confirmation on volume deletion
        DELETE_NOCONFIRM="-y"
        ;;
      p)
        # Prefix to use for volume names on creation
        VOLUME_PREFIX=${OPTARG}
        ;;
      s)
        # Size for each volume on creation
        VOLUME_SIZE=${OPTARG}
        ;;
      *)
        # Other option arguments are invalid
        usage
        ;;
    esac
  done

  shift $((OPTIND-1))

  # Non-option arguments are assumed to be a command (and command arguments) to use for each volume
  PER_DRIVEVOL_USER_CMD=($*)
}

# Check if the jq tool is installed and exit if not installed.
find_jq_or_exit()
{
  which jq >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
    echo "ERROR: jq command not found. Try \"yum/apt install jq\"."
    exit 1
  fi
}

# Check nvmesh CLI version and exit if version mismatch
check_nvmesh_cli_ver_or_exit()
{
  find_nvmesh_cli_or_exit

  nvmesh_out=`nvmesh version`
  
  if [ $? -ne 0 ]; then
    echo "ERROR: nvmesh CLI version query failed."
    exit 1
  fi

  major_ver=`echo $nvmesh_out | cut -d. -f1` 

  if [ "$major_ver" -ne $NVMESH_MARJOR_VER ]; then
    echo "ERROR: nvmesh CLI major version mismatch. Detected version: \"$major_ver\"." \
      "Expected version: \"$NVMESH_MARJOR_VER\""
    exit 1
  fi
}


# Check if the nvmesh CLI tool is installed and exit if not installed.
find_nvmesh_cli_or_exit()
{
  which nvmesh >/dev/null 2>&1
  
  if [ $? -ne 0 ]; then
    echo "ERROR: nvmesh CLI tool not found. Install the nvmesh-utils package."
    exit 1
  fi
}

# Query nvmesh CLI to get all drives.
# Filters out drives that are marked as excluded in NVMesh, marked as out of service, as not healthy
# or marked as dummy drive.
get_drives_filtered()
{
  cmd="nvmesh drive show --output-format json"
  nvmesh_out=`$cmd`
  
  if [ $? -ne 0 ]; then
    echo "ERROR: nvmesh query failed based on this command:"
    echo "-----------"
    echo "$cmd"
    echo "-----------"
    exit 1
  fi

  echo $nvmesh_out | jq '[ .[] | select (.isExcluded==false and .Model!="Dummy" and .health=="healthy" and .isOutOfService!=true) ]'
}

# List serial numbers of all drives (filtered to good drives)
list_drives()
{
  drives_filtered=`get_drives_filtered`
  
  echo $drives_filtered | jq '.[].diskID' | sed s/\"//g | cut -d. -f1
}

# Create NVMesh volume for each drive
create_vol_for_each_drive()
{
  drives_filtered=`list_drives`

  for drive in $drives_filtered; do
    cmd="nvmesh volume create --name ${VOLUME_PREFIX}${drive} --limit-by-drive ${drive}.1 --raid-level lvm --capacity ${VOLUME_SIZE}"

    echo "Volume create command:" $cmd
    $cmd

    if [ $? -ne 0 ]; then
      echo "ERROR: nvmesh volume creation failed based on this command:"
      echo "-----------"
      echo "$cmd"
      echo "-----------"
    fi
  done
}

# Delete NVMesh volume for each drive
delete_vol_for_each_drive()
{
  drives_filtered=`list_drives`

  for drive in $drives_filtered; do
    cmd="nvmesh volume delete --name ${VOLUME_PREFIX}${drive} ${DELETE_NOCONFIRM}"

    echo "Volume delete command:" $cmd
    $cmd

    if [ $? -ne 0 ]; then
      echo "ERROR: nvmesh volume deletion failed based on this command:"
      echo "-----------"
      echo "$cmd"
      echo "-----------"
    fi
  done
}

# Attach volume for each drive
attach_vol_for_each_drive()
{
  drives_filtered=`list_drives`

  for drive in $drives_filtered; do

    cmd="nvmesh_attach_volumes --wait_for_attach ${VOLUME_PREFIX}${drive}"

    echo "Attach volume command:" $cmd
    $cmd

    if [ $? -ne 0 ]; then
      echo "ERROR: nvmesh volume attachment failed based on this command:"
      echo "-----------"
      echo "$cmd"
      echo "-----------"
    fi
  done
}

# Detach volume for each drive
detach_vol_for_each_drive()
{
  drives_filtered=`list_drives`

  for drive in $drives_filtered; do

    cmd="nvmesh_detach_volumes ${VOLUME_PREFIX}${drive}"

    echo "Detach volume command:" $cmd
    $cmd

    if [ $? -ne 0 ]; then
      echo "ERROR: nvmesh volume detachment failed based on this command:"
      echo "-----------"
      echo "$cmd"
      echo "-----------"
    fi
  done
}

# Run a user-specified command for each single drive volume
run_user_cmd_for_each_vol()
{
  drives_filtered=`list_drives`

  for drive in $drives_filtered; do

    unset user_cmd

    # replace special string %VOL% with volume name in user command
    for (( i=0 ; i < ${#PER_DRIVEVOL_USER_CMD[@]}; i++ )) do

      user_cmd[i]="`echo ${PER_DRIVEVOL_USER_CMD[i]} | sed s!%VOL%!${VOLUME_PREFIX}${drive}!g`"

    done

    echo "Executing command:" ${user_cmd[@]}
    ${user_cmd[@]}

  done

}

find_nvmesh_cli_or_exit
check_nvmesh_cli_ver_or_exit
find_jq_or_exit

parse_args "$@"

if [ "$LIST_DRIVES" -eq 1 ]; then
  list_drives
fi

if [ "$CREATE_VOLUMES" -eq 1 ]; then
  create_vol_for_each_drive
fi

if [ "$ATTACH_VOLUMES" -eq 1 ]; then
  attach_vol_for_each_drive
fi

if [ "${#PER_DRIVEVOL_USER_CMD[@]}" -ne 0 ]; then
  run_user_cmd_for_each_vol
fi

if [ "$DETACH_VOLUMES" -eq 1 ]; then
  detach_vol_for_each_drive
fi

if [ "$DELETE_VOLUMES" -eq 1 ]; then
  delete_vol_for_each_drive
fi
