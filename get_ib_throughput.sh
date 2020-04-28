#!/bin/bash
#
# Show live throughput for InfiniBand interfaces based on data counters in /sys/class/infiniband.
#
# Author: Sven Breuner
# Maintainer: Sven Breuner <sven[at]excelero.com>


# Print usage info and exit
usage()
{
  echo "Show live throughput for InfiniBand interfaces based on data counters in"
  echo "/sys/class/infiniband."
  echo
  echo "Usage:"
  echo "  $0 [Options] [Interface:Port [Interface:Port [...] ]"
  echo
  echo "Options:"
  echo "  -m          Use multiple lines per interface, one for rx and one for tx."
  echo "  -s          Single run. Default is an infinite loop."
  echo "  -t NUM      Time interval in seconds. Defaults to 1 sec."
  echo "  interface   Interface to query counters for. Defaults to automatic query"
  echo "              of available interfaces based on ibdev2netdev."
  echo 
  echo "Example:"
  echo "  $ $0 mlx5_0:1 mlx5_1:1"

  exit 1
}

# Parse command line arguments and set defaults
parse_args()
{
  local OPTIND # local to prevent effects from other subscripts

  # default settings
  multiline=0 # 1 for multiple lines for rx and tx per interface
  quit=0 # 1 for single run instead of infinite loop
  t=1 # time interval in seconds

  while getopts ":hmst:" opt; do
    case "${opt}" in
      m)
        # Single run instead of infinite loop
        multiline=1
        ;;
      s)
        # Single run instead of infinite loop
        quit=1
        ;;
      t)
        # Time interval in seconds
        t=${OPTARG}
        ;;
      *)
        # Other option arguments are invalid
        usage
        ;;
    esac
  done

  shift $((OPTIND-1))

  # Non-option arguments are assumed to be interface names
  NICs=($*)

  # If no interfaces were given by user then auto detect from ibdev2netdev
  # (We ignore "Up/Down" in ibdev2netdev output, because that's only for IPoIB.)
  if [ ${#NICs[@]} -eq 0 ]; then
     NICs=(`ibdev2netdev | cut -d '=' -f 1 | cut -d ' ' -f 1,3 | sed 's/ /:/'`)
  fi
}


# Print statistics for given time interval. (Includes sleep.)
print_stats()
{
  # read absolute rx/tx counters of given interfaces (reuse from last round if possible)
  if [ ${#STATS_B[@]} -eq 0 ]; then
    for (( i=0; i < ${#NICs[@]}; i++ )) do
      dev=$(echo ${NICs[$i]} | cut -d: -f1)
      port=$(echo ${NICs[$i]} | cut -d: -f2)

      STATS_A[$i]=$(cat /sys/class/infiniband/${dev}/ports/${port}/counters/port_rcv_data)
      STATS_A[$i]+=" "
      STATS_A[$i]+=$(cat /sys/class/infiniband/${dev}/ports/${port}/counters/port_xmit_data)
      # STAT_A[$i] contains 2 space-separated values now: the absolute rx bytes and tx bytes
    done
  else
    # reuse counters from last round
    STATS_A=("${STATS_B[@]}")
  fi

  # wait for given time interval (seconds)
  sleep $t;

  # read absolute rx/tx counters again and print difference
  for (( i=0; i < ${#NICs[@]}; i++ )) do
    dev=$(echo ${NICs[$i]} | cut -d: -f1)
    port=$(echo ${NICs[$i]} | cut -d: -f2)

    STATS_B[$i]=$(cat /sys/class/infiniband/${dev}/ports/${port}/counters/port_rcv_data)
    STATS_B[$i]+=" "
    STATS_B[$i]+=$(cat /sys/class/infiniband/${dev}/ports/${port}/counters/port_xmit_data)

    A=(${STATS_A[$i]})
    B=(${STATS_B[$i]})

    # port_*_data counters text from IB standard doc: "Total number of data octets, divided by 4,
    # transmitted on all VLs during the sampling interval."
    # Note that the 4 here is fixed, independent of the "active_width" of a link.
    rate_multiplier=4

    RX=$(( $rate_multiplier * (${B[0]}-${A[0]}) / (1024 * 1024 * $t) ))
    TX=$(( $rate_multiplier * (${B[1]}-${A[1]}) / (1024 * 1024 * $t) ))

    if [ $multiline -gt 0 ]; then
      echo "${NICs[$i]} RX MiB/s: $RX"
      echo "${NICs[$i]} TX MiB/s: $TX"
    else
      printf '%-8s | MiB/s | RX %6s | TX %6s\n' ${NICs[$i]} $RX $TX
    fi

  done
}


parse_args "$@"

SECONDS=0 # automatically incremented by bash

while true; do
  stats_out=$(print_stats)

  if [ $quit -gt 0 ]; then
    echo "$stats_out"
    exit 0
  fi

  echo "--- ${SECONDS}s ---"
  echo "$stats_out"
done
