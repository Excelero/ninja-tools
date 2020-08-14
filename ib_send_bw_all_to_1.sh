#!/bin/bash
#
# Check N-to-1 connectivity and transfer speed. 2nd and all following IPs in given list
# concurrently send to the first IP address in the list using ib_send_bw.
#
# Author: Sven Breuner
# Maintainer: Sven Breuner <sven[at]excelero.com>


# Initialize defaults...
EXECUTABLE="ib_send_bw" # can be switched to ib_read_bw with "-R"
MSGSIZE=65536 # Message size of ib_send_bw transfers
WAIT_TIME_SECS=15 # Max time to wait for ib_send_bw service to become ready
# (note: 15s ssh timeout because ssh can hang much longer for unreachable IPs)
SSH_CMD="ssh -o LogLevel=ERROR -o ConnectTimeout=15 -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no"
DURATION_SECS=10 # number of seconds for ib_send_bw transfer time
LISTEN_PORT_BASE=18515 # tcp port of ib_send_bw to listen on (plus participant index)
JUST_KILL=0 # set to "1" if user just wants to cleanup and not run a benchmark.
REVERSED="--reversed" # will be unset by "-r" to 1-to-N measurement
unset STDERR_TO_NULL # set by option "-m" to send stderr to /dev/null
unset NUMA_BIND # set by option "-b" to use numactl for ib_send_bw
unset USE_RDMA_CM # set by "-R" to use the RDMA Connection Manager
unset RDMA_CM_TOS # set by "-T" for RDMA_CM Type of Service
TMP_PATH="/tmp/all_to_1.results" # tmp file to store output of background processes


# Print usage info and exit
usage()
{
  echo "About:"
  echo "  Check N-to-1 connectivity and transfer speed. 2nd and all following IPs in" 
  echo "  given list concurrently send to the first IP address in the list using"
  echo "  ib_send_bw. Requires ssh without password from this host to all hosts in the"
  echo "  list."
  echo
  echo "Usage:"
  echo "  $0 [Options] host1:dev1:port1 h2:d2:p2 [... hN:dN:pN]"
  echo
  echo "Options:"
  echo "  h:d:p       Hostname/IP address can refer to any IP on the server, also for a"
  echo "              non-RDMA interface. Device is the mlx device to use, e.g."
  echo "              mlx5_0. Port is the mlx device port, e.g. 1."
  echo "  -b NUM      Bind ib_send_bw through numactl to NUMA zone. Can be a zone number"
  echo "              or a device description like \"netdev:ib0\" or \"block:nvme0n1\"."
  echo "  -s NUM      Size of ib_send_bw message to exchange in bytes. (Default: 65536)"
  echo "  -t NUM      Max time to wait for ib_send_bw service to become ready in"
  echo "              seconds. (Default: 15)"
  echo "  -d NUM      Duration of ib_send_bw transfer in seconds. (Default: 10)"
  echo "  -R          Use RDMA_CM (RDMA Connection Manager) to establish connections."
  echo "              In this case, the given hostnames/IP addresses need to refer to"
  echo "              the mlx device/port that should be used for the test."
  echo "              (Due to \"ib_send_bw -R --reversed\" not working, this will use"
  echo "              \"ib_read_bw -R\" instead.)"
  echo "  -T NUM      Set RDMA_CM type of service. Only valid in combination with \"-R\"."
  echo "              (Valid range is 0..255.)"
  echo "              the mlx device/port that should be used for the test."
  echo "  -m          Mute stderr output for ssh commands to prevent it from spoiling"
  echo "              the output format (e.g. messages like \"TERM variable not set\""
  echo "              from a bad shell profile). Also mutes real errors, so run without"
  echo "              this option first."
  echo "  -p NUM      Base TCP port for ib_send_bw to listen for incoming connections."
  echo "              Host index will be added to this port number. (Default: 18515)"
  echo "  -k          Just kill any ib_send_bw leftovers from a failed run on the given"
  echo "              hosts."
  echo "  -r          Reverse traffic direction to measure 1-to-N."
  echo 
  echo "Examples:"
  echo "  $ $0 192.168.0.1:mlx5_0:1 192.168.0.2:mlx5_0:1 192.168.0.3:mlx5_0:1"
  echo "  $ $0 \`cat myhostsfile\`"

  exit 1
}

# Parse command line arguments
parse_args()
{
  local OPTIND # local to prevent effects from other subscripts

  while getopts ":b:d:kmp:Rrs:T:t:" opt; do
    case "${opt}" in
      b)
        # Bind to NUMA zone through numactl (by number or e.g. netdev:ib0)
        NUMA_BIND="numactl -m ${OPTARG} -N ${OPTARG}"
        ;;
      d)
        # No self-connect test with client and server being the same IP
        DURATION_SECS=${OPTARG}
        ;;
      k)
        # Just cleanup ib_send_bw leftovers from a failed run
        JUST_KILL=1
        ;;
      m)
        # Mute stderr for ssh commands
        STDERR_TO_NULL="2>/dev/null"
        ;;
      p)
        # Base tcp listen port for ib_send_bw (plus participant index)
        LISTEN_PORT_BASE=${OPTARG}
        ;;
      R)
        # Use RDMA Connection Manager
        # Use ib_read_bw due to a bug in "ib_send_bw -R --reversed"
        USE_RDMA_CM="-R"
        EXECUTABLE="ib_read_bw"
        ;;
      r)
        # Reverse traffic direction to measure 1-to-N
        unset REVERSED
        ;;
      s)
        # Size of message to exchange in bytes
        MSGSIZE=${OPTARG}
        ;;
      T)
        # Set RDMA Type of Service
        RDMA_CM_TOS="--tos=${OPTARG}"
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

  # Adapt reverse option for ib_read_bw in case of RDMA_CM
  if [ ! -z "$USE_RDMA_CM" ]; then
     # User selected RCMA_CM, so we use ib_read_bw instead of ib_send_bw
     if [ -z "$REVERSED" ]; then
       # empty $REVERSED means user wants to test 1-to-N, so add "--reversed" for ib_read_bw
       REVERSED="--reversed"
     else
       # not empty $REVERSED means user wants to test N-to-1, so unset "--reversed" for ib_read_bw
       unset REVERSED
     fi
  fi

  # Non-option arguments are assumed to be IP addresses
  PARTICIPANTS=($*)

  # If no IPs were given by user then fail
  if [ ${#PARTICIPANTS[@]} -lt 2 ]; then
    echo "ERROR: At least 2 hostnames or IP addresses are needed."
    usage
  fi


  # Split participant entries into host/device/devport
  for (( i=0; i < ${#PARTICIPANTS[@]}; i++ )) do
    HOSTS[$i]=`echo ${PARTICIPANTS[$i]} | cut -d: -f1`
    DEVICES[$i]=`echo ${PARTICIPANTS[$i]} | cut -d: -f2`
    PORTS[$i]=`echo ${PARTICIPANTS[$i]} | cut -d: -f3`
  done

  # Split into first participant and others.
  # "first" is the 1 on our N-to-1, "others" are the N in N-to-1.
  FIRST_PARTICIPANT=${PARTICIPANTS[0]}
  OTHER_PARTICIPANTS=("${PARTICIPANTS[@]:1}")
  FIRST_HOST=${HOSTS[0]}
  OTHER_HOSTS=("${HOSTS[@]:1}")
  FIRST_DEVICE=${DEVICES[0]}
  OTHER_DEVICES=("${DEVICES[@]:1}")
  FIRST_PORT=${PORTS[0]}
  OTHER_PORTS=("${PORTS[@]:1}")
}

# Kill all ib_send_bw leftovers after error
kill_leftovers()
{
  # kill all ib_send_bw leftovers on other hosts (i.e. the N in our N-to-1)
  for (( idx=0; idx < ${#OTHER_PARTICIPANTS[@]}; idx++ )) do

    to_ip=${OTHER_HOSTS[$idx]}
    to_device=${OTHER_DEVICES[$idx]}
    to_devport=${OTHER_PORTS[$idx]}

    echo "Cleaning up any ${EXECUTABLE} leftovers for ${OTHER_PARTICIPANTS[$idx]}..."
    ${SSH_CMD} ${to_ip} "pkill -f \"^${EXECUTABLE} -d ${to_device} -i ${to_devport}\"" ${STDERR_TO_NULL}
  done

  # kill all ib_send_bw leftovers on first host (i.e. the 1 in our N-to-1)

  from_ip=${FIRST_HOST}
  from_device=${FIRST_DEVICE}
  from_devport=${FIRST_PORT}

  echo "Cleaning up any ib_send_bw leftovers for ${FIRST_PARTICIPANT}..."
  ${SSH_CMD} ${from_ip} "pkill -f \"^${EXECUTABLE} -d ${from_device} -i ${from_devport}\"" ${STDERR_TO_NULL}
}

# Use ib_send_bw from each IP in the list to each other IP in the list.
do_all_to_one()
{

  # run ib_send_bw server on all OTHER_PARTICIPANTS (i.e. the N in our N-to-1)
  for (( idx=0; idx < ${#OTHER_PARTICIPANTS[@]}; idx++ )) do

      to_ip=${OTHER_HOSTS[$idx]}
      to_device=${OTHER_DEVICES[$idx]}
      to_devport=${OTHER_PORTS[$idx]}
      to_listen_port=$((${LISTEN_PORT_BASE} + ${idx}))

      echo "Preparing ${OTHER_PARTICIPANTS[$idx]}... "

      # run remote ib_send_bw service
      # (the initial commands are to detect the corresponding device for the given ip)

      to_cmd="${SSH_CMD} ${to_ip} '
        ${NUMA_BIND} ${EXECUTABLE} -d ${to_device} -i ${to_devport} -F -D ${DURATION_SECS} \
          ${REVERSED} -p ${to_listen_port} -s ${MSGSIZE} ${USE_RDMA_CM} ${RDMA_CM_TOS} >/dev/null'"

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
          kill_leftovers
          exit 1
        fi

        # check if ib_send_bw already opened a port to listen for connections
        netstat_cmd="${SSH_CMD} ${to_ip} \
          'if ! ls -l /proc/\`pgrep -f \"^${EXECUTABLE} -d ${to_device} -i ${to_devport}\"\`/fd 2>&1 \
             | grep infinibandevent >/dev/null; then 
             exit 1; 
          fi'"
      
        if eval ${netstat_cmd} ${STDERR_TO_NULL}; then
          to_is_ready=1
          break;
        fi

      # wait a little while before trying again...
      sleep 0.01

      done # end wait for-loop

      if [ $to_is_ready -eq 0 ]; then
        echo "Timeout waiting for ${to_ip} to become ready based on this command:"
        echo "---"
        echo "$ ${to_cmd}"
        echo "---"
        kill_leftovers
        exit 1
      fi

      # service@$to_ip is ready, so continue preparing the next one...

  done # end of other_participants for-loop

  # services on others running, so start connecting from the 1 in our N-to-1

  from_ip=${FIRST_HOST}
  from_device=${FIRST_DEVICE}
  from_devport=${FIRST_PORT}

  echo "Connecting client processes from ${FIRST_PARTICIPANT}... "

  from_cmd="${SSH_CMD} ${from_ip} '
    other_participants=(${OTHER_PARTICIPANTS[@]});
    other_hosts=(${OTHER_HOSTS[@]});
    other_devices=(${OTHER_DEVICES[@]});
    other_ports=(${OTHER_PORTS[@]});
    
    rm -f ${TMP_PATH};
    
    for (( idx=0; idx < \${#other_participants[@]}; idx++ )) do
      to_ip=\${other_hosts[\$idx]};
      to_listen_port=\$((${LISTEN_PORT_BASE} + \${idx}));
      ${NUMA_BIND} ${EXECUTABLE} -d $from_device -i $from_devport -F \
        -D ${DURATION_SECS} ${REVERSED} -p \$to_listen_port -s $MSGSIZE ${USE_RDMA_CM} \
        ${RDMA_CM_TOS} \$to_ip \
        | grep \"^ ${MSGSIZE}\" \
        | awk \" { printf \\\"%7.0f \${other_participants[\$idx]}\\\n\\\", \\\$4 }\" >> ${TMP_PATH} &
    done;
    
    wait;
    
    echo;
    echo \"INDIVIDUAL RESULTS...\";

    sum=0;

    while read line; do
      line_array=(\$line);
      sum=\$(( \$sum + \${line_array[0]} ));
      printf \"%7d MB/s %s\\\n\" \$line;
    done < ${TMP_PATH};
    
    echo;
    echo \"RESULTS SUM:\" \$sum MB/s'"

  eval ${from_cmd} ${STDERR_TO_NULL}

  # if everything went well then the from_cmd already printed the result

  if [ ! $? -eq 0 ]; then
    echo "Connection attempt from ${from_ip} failed based on this command:"
    echo "---"
    echo "$ ${from_cmd}"
    echo "---"
    kill_leftovers
    exit 1
  fi

}


parse_args "$@"

if [ ${JUST_KILL} -eq 1 ]; then
  kill_leftovers
  exit 0
fi

do_all_to_one
