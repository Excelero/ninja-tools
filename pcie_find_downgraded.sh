#!/bin/bash
#
# Find NVMe or Mellanox PCIe devices that have downgraded link speed/width.
#
# Author: Sven Breuner
# Maintainer: Sven Breuner <sven[at]excelero.com>


VERBOSE=0 # set to 1 via argument for verbose mode
PRINT_NUM_FOUND=0 # set to 1 via argument to print discovered num of devices

NUM_NVMES_FOUND=0 # number of found NVMe drives
NUM_NICS_FOUND=0 # number of found NICs

# Print usage info and exit
usage()
{
  echo "About:"
  echo "  Find NVMe or Mellanox PCIe devices that have downgraded link speed/width."
  echo
  echo "Usage:"
  echo "  $0 [options]"
  echo
  echo "Option Arguments:"
  echo "  -h          Print this help."
  echo "  -n          Print number of discovered devices."
  echo "  -v          Be verbose. Print all checked devices and their link speed/width."
  echo
  echo "Examples:"
  echo "  Find all NVMe or Mellanox PCIe devices that have downgraded link speed/width:"
  echo "    $ $0"

  exit 1
}

# Parse command line arguments
parse_args()
{
  local OPTIND # local to prevent effects from other subscripts

  while getopts ":hnv" opt; do
    case "${opt}" in
      h)
        # help
        usage
        ;;
      n)
        # print num of discovered devices
        PRINT_NUM_FOUND=1
        ;;
      v)
        # verbose
        VERBOSE=1
        ;;
      *)
        # Other option arguments are invalid
        usage
        ;;
    esac
  done

  shift $((OPTIND-1))

  # 5 here for the 5 mandatory args: DEVICE, IODEPTH etc
  if [ $# -ne 0 ]; then
    echo "ERROR: Invalid argument: $1"
    usage
  fi
}


# Check if lspci is installed and exit if not installed.
find_lspci_or_exit()
{
  LSPCI_PATH=$(which lspci 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    echo "ERROR: lspci tool not found. Try \"yum/apt install pcituils\""
    exit 1
  fi
}

parse_args "$@"
find_lspci_or_exit

lspci_output="$(lspci | grep -e Mellanox -e NVMe -e 'Non-Volatile memory controller')"

while read -r dev_line; do
  dev_description=$(echo $dev_line | cut -f2- "-d ")
  dev_addr=$(echo $dev_line | cut -f1 "-d ")
  
  dev_details=$(lspci -vvv -s $dev_addr)
  
  link_capabilities=$(echo "$dev_details" | grep "LnkCap:")
  link_state=$(echo "$dev_details" | grep "LnkSta:")
  
  link_capable_width=$(echo $link_capabilities | grep -ohE "Width x[[:digit:]]+")
  link_state_width=$(echo $link_state | grep -ohE "Width x[[:digit:]]+")
  link_capable_speed=$(echo $link_capabilities | grep -ohE "Speed [[:digit:]]+GT/s")
  link_state_speed=$(echo $link_state | grep -ohE "Speed [[:digit:]]+GT/s")
  
  # increase counters
  if [ -n "$(echo $dev_line | grep -e NVMe -e 'Non-Volatile memory controller')" ]; then
    ((NUM_NVMES_FOUND+=1))
  fi

  if [ -n "$(echo $dev_line | grep -e Mellanox)" ]; then
    ((NUM_NICS_FOUND+=1))
  fi
  
  if [ "$VERBOSE" -eq 1 ]; then
    echo "${dev_description}:"
    echo "Capabilities:  $link_capable_width; $link_capable_speed"
    echo "Current state: $link_state_width; $link_state_speed"
	echo
  else
    # print only the ones where state is not equal to capabilities
	if [ "$link_capable_width" != "$link_capable_width" ] || \
	  [ "$link_capable_speed" != "$link_capable_speed" ]; then
	  
      echo "${dev_description}:"
      echo "Capabilities:  $link_capable_width; $link_capable_speed"
      echo "Current state: $link_state_width; $link_state_speed"
	  echo
	fi
  fi

done < <(echo "$lspci_output")

if [ "$PRINT_NUM_FOUND" -eq 1 ]; then
  echo "Discovered devices: Mellanox NICs: $NUM_NICS_FOUND; NVMe devices: $NUM_NVMES_FOUND"
fi