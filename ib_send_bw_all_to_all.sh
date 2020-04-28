#!/bin/bash
#
# Check 1-to-1 connectivity and transfer speed from each IP address in given list to all others in
# the list using ib_send_bw.
#
# Author: Sven Breuner
# Maintainer: Sven Breuner <sven[at]excelero.com>


# Initialize defaults...
MSGSIZE=65536 # Message size of ib_send_bw transfers
WAIT_TIME_SECS=15 # Max time to wait for ib_send_bw service to become ready
# (note: 15s ssh timeout because ssh can hang much longer for unreachable IPs)
SSH_CMD="ssh -o LogLevel=ERROR -o ConnectTimeout=15 -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no"
DO_LOCAL_COMM=1 # 0 to skip ib_send_bw test with server and client being the same IP
unset STDERR_TO_NULL # set by option "-m" to send stderr to /dev/null
unset NUMA_BIND # set by option "-b" to use numactl for ib_send_bw
unset BIDIRECTIONAL # set by option "-B" to run bidirectional "ib_send_bw -b"


# Print usage info and exit
usage()
{
  echo "About:"
  echo "  Check 1-to-1 connection and transfer speed from each IP address in given list"
  echo "  to all others in the list using ib_send_bw. Requires ssh without password from"
  echo "  this host to all hosts in the list."
  echo
  echo "Usage:"
  echo "  $0 [Options] IP_addr1 IP_addr2 [... IP_addrN]"
  echo
  echo "Options:"
  echo "  IP_address  Each IP address must refer to a RDMA-capable network interface."
  echo "  -b NUM      Bind ib_send_bw through numactl to NUMA zone. Can be a zone number"
  echo "              or a device description like \"netdev:ib0\" or \"block:nvme0n1\"."
  echo "  -s NUM      Size of ib_send_bw message to exchange in bytes. (Default: 65536)"
  echo "  -t NUM      Max time to wait for ib_send_bw service to become ready in"
  echo "              seconds. (Default: 15)"
  echo "  -l          Skip local communication test with client and server being the"
  echo "              same IP address."
  echo "  -m          Mute stderr output for ssh commands to prevent it from spoiling"
  echo "              the output format (e.g. messages like \"TERM variable not set\""
  echo "              from a bad shell profile). Also mutes real errors, so run without"
  echo "              this option first."
  echo "  -B          Measure bidirectional throughput."
  echo 
  echo "Examples:"
  echo "  $ $0 192.168.0.{1..4} 192.168.0.{11..14}"
  echo "  $ $0 \`cat myhostsfile\`"

  exit 1
}

# Parse command line arguments
parse_args()
{
  local OPTIND # local to prevent effects from other subscripts

  while getopts ":Bb:lms:t:" opt; do
    case "${opt}" in
      B)
        # Bidirectional measurement
        BIDIRECTIONAL="-b"
        ;;
      b)
        # Bind to NUMA zone through numactl (by number or e.g. netdev:ib0)
        NUMA_BIND="numactl -m ${OPTARG} -N ${OPTARG}"
        ;;
      l)
        # No self-connect test with client and server being the same IP
        DO_LOCAL_COMM=0
        ;;
      m)
        # Mute stderr for ssh commands
        STDERR_TO_NULL="2>/dev/null"
        ;;
      s)
        # Size of message to exchange in bytes
        MSGSIZE=${OPTARG}
        ;;
      t)
        # Max time to wait for ib_send_bw service to become ready
        WAIT_TIME_SECS=${OPTARG}
        ;;
      *)
        # Other option arguments are invalid
        usage
        ;;
    esac
  done

  shift $((OPTIND-1))

  # Non-option arguments are assumed to be IP addresses
  IPs=($*)

  # If no IPs were given by user then fail
  if [ ${#IPs[@]} -lt 2 ]; then
     echo "ERROR: At least 2 IP addresses are needed."
     usage
  fi
}

# Use ib_send_bw from each IP in the list to each other IP in the list.
do_each_to_each()
{
  for (( from_idx=0; from_idx < ${#IPs[@]}; from_idx++ )) do
    for (( to_idx=0; to_idx < ${#IPs[@]}; to_idx++ )) do

      from_ip=${IPs[$from_idx]}
      to_ip=${IPs[$to_idx]}

      if [ $from_idx -eq $to_idx ] && [ $DO_LOCAL_COMM -eq 0 ]; then
        continue
      fi

      if [ $from_idx -eq $to_idx ]; then
        printf '%-15s -> %-15s: ' ${from_ip} "LOCAL"
        #echo -n "${from_ip} -> SELF: "
      else
        printf '%-15s -> %-15s: ' ${from_ip} ${to_ip}
        #echo -n "${from_ip} -> ${to_ip}: "
      fi

      # run remote ib_send_bw service
      # (the initial commands are to detect the corresponding device for the given ip)

      to_cmd="${SSH_CMD} ${to_ip} '\
        iface=\`ip -4 -br a | grep ${to_ip} | cut \"-d \" -f 1\`; \
        device=\`ibdev2netdev | grep \"\$iface\" | cut \"-d \" -f 1\`; \
        devport=\`ibdev2netdev | grep \"\$iface\" | cut \"-d \" -f 3\`; \
        if [ \"\$iface\" = \"\" ] || [ \"\$device\" = \"\" ] || [ \"\$devport\" = \"\" ]; then \
          echo \"Unable to detect RDMA device for ${to_ip}.\"; \
          exit 1; \
        fi; \
        ${NUMA_BIND} ib_send_bw -d \"\$device\" -i \"\$devport\" ${BIDIRECTIONAL} -F -R \
          -s ${MSGSIZE} >/dev/null'"

      eval ${to_cmd} ${STDERR_TO_NULL} &
      to_pid=$!

      # wait for remote ib_send_bw service to become ready

      to_is_ready=0 # checks in for-loop below will set to "1" when server ready

      # (note: SECONDS is automatically incremented by bash)
      for((SECONDS=0; SECONDS < $WAIT_TIME_SECS; )); do

        # check if ssh command is still running
        if ! kill -0 ${to_pid} >/dev/null 2>&1; then
          echo "Unexpected termination of process for ${to_ip}. This was the command:"
          echo "---"
          echo "$ ${to_cmd}"
          echo "---"
          exit 1
        fi

        # check if ib_send_bw already opened a port to listen for connections
        netstat_cmd="${SSH_CMD} ${to_ip} \
          'if ! ls -l /proc/\`pgrep -f \"^ib_send_bw\"\`/fd 2>&1 | grep infinibandevent >/dev/null; then \
             exit 1; \
          fi'"
      
        if eval ${netstat_cmd} ${STDERR_TO_NULL}; then
          to_is_ready=1
          break;
        fi

        # wait a little while before trying again...
        sleep 0.01

      done # end for wait for-loop

      if [ $to_is_ready -eq 0 ]; then
        echo "Timeout waiting for ${to_ip} to become ready based on this command:"
        echo "---"
        echo "$ ${to_cmd}"
        echo "---"
        echo "Cleaning up any ib_send_bw leftovers on server host ${to_ip}..."
        ${SSH_CMD} ${to_ip} 'pkill ib_send_bw' ${STDERR_TO_NULL}
        exit 1
      fi

      # server@$to_ip is ready, so let's connect the client@$from_ip

      from_cmd="${SSH_CMD} ${from_ip} '\
        iface=\`ip -4 -br a | grep ${from_ip} | cut \"-d \" -f 1\`; \
        device=\`ibdev2netdev | grep \"\$iface\" | cut \"-d \" -f 1\`; \
        devport=\`ibdev2netdev | grep \"\$iface\" | cut \"-d \" -f 3\`; \
        if [ \"\$iface\" = \"\" ] || [ \"\$device\" = \"\" ] || [ \"\$devport\" = \"\" ]; then \
          echo \"Unable to detect RDMA device for ${from_ip}.\"; \
          exit 1; \
        fi; \
        ${NUMA_BIND} ib_send_bw -d \"\$device\" -i \"\$devport\" ${BIDIRECTIONAL} -F -R \
          -s ${MSGSIZE} ${to_ip} \
          | grep \"^ ${MSGSIZE}\" | awk \"{ print \\\$4 }\" ' "

      from_cmd_out=`eval ${from_cmd} ${STDERR_TO_NULL}`

      # if everything went well then from_cmd_out should now contain the bandwidth value

      if [ ! $? -eq 0 ]; then
        echo "Connection attempt from ${from_ip} failed based on this command:"
        echo "---"
        echo "$ ${from_cmd}"
        echo "Cleaning up any ib_send_bw leftovers on server host ${to_ip}..."
        echo "---"
        ${SSH_CMD} ${to_ip} 'pkill ib_send_bw' ${STDERR_TO_NULL}
        exit 1
      fi

      echo "$from_cmd_out MB/s avg"

    done # end of to_idx for-loop
  done # end of from_idx for-loop
}


parse_args "$@"

do_each_to_each
