#!/bin/bash

usage()
{
  echo "Monitor the NVMesh memory related into a file."
  echo
  echo
  echo "Usage:"
  echo "  $0  ./nvmesh_memory_monitor.sh [-t time] [-o output_file] &"
  echo
  echo
  echo "Options:"
  echo "  -t NUM      Set the interval between each collection - in seconds (Default: 60)"
  echo "  -p STRING   Set the destination for the output file. (Default: \"/var/log/\`hostname\`-nvmesh-memory.csv\")"
  echo
  echo
  echo "Example:"
  echo "  $ $0 ./nvmesh_memory_monitor.sh -t 120 -o /tmp/nvmesh_memory_monitor.log &"
  echo "  [1] 6885 "
  echo
  echo "  $ ps -ef | grep nvmesh_memory_monitor.sh"
  echo "  root      6885 30072  0 14:39 pts/1    00:00:00 /bin/bash ./nvmesh_memory_monitor.sh -t 120 -o /tmp/nvmesh_memory_monitor.log "
  echo
  echo "  $ kill 6885 "

  exit 1
}

parse_args()
{
  while getopts ":to:" opt; do
    case "${opt}" in
      t)
        time_interval=${OPTARG}
        ;;
      o)
        output_file=${OPTARG}
        ;;
      *)
        usage
        ;;
    esac
  done

  shift $((OPTIND -1))

  if [ -z "$output_file" ] ; then
    output_file=/var/log/`hostname`-nvmesh-memory.csv
  fi
  if [ -z "$time_interval" ] ; then
    time_interval=60
  fi
}

check_root()
{
  if [ `whoami` != root ]; then
    echo "Please run this script as root or using sudo"
    exit
  fi
}


parse_args "$@"
check_root

echo "DATE,TOTAL_MEM_USED,TOTAL_MEM_AVAILABLE,TOMA_MEM_USED,MGMT_CM_MEM_USED,NVMESHAGENT_MEM_USED,NODE_MEM_USED,MONGO_MEM_USED,MONGO_MEM_DETAILED,KERNEL_MEM_USED,LOAD_AVG" > $output_file

while true ; do
  DATE=`date '+%Y:%m:%d-%H:%M:%S'`
  TOTAL_MEM_USED=`free|grep Mem|awk {'print $3'}`
  TOTAL_MEM_AVAILABLE=`free |grep Mem|awk {'print $2'}`
  TOMA_MEM_USED=`ps aux|grep nvmeibt_toma | grep -v grep |awk {'print $5'}`
  MGMT_CM_MEM_USED=`ps aux|grep managementCM | grep -v grep |awk {'print $5'}`
  NVMESHAGENT_MEM_USED=`ps aux|grep managementAgent.py | grep -v grep |awk {'print $5'}`
  NODE_MEM_USED=`ps aux|grep app.js | grep -v grep |awk {'print $5'}`
  MONGO_MEM_USED=`ps aux|grep mongod | grep -v grep |awk {'print $5'}`
  MONGO_MEM_DETAILED=`top -bn1 | grep mongod | awk {'print $5'}`,`top -bn1 | grep mongod | awk {'print $6'}`,`top -bn1 | grep mongod | awk {'print $7'}`
  KERNEL_MEM_USED=$[`cat /proc/meminfo | grep Slab | awk {'print $2'}`+`cat /proc/meminfo | grep VmallocUsed | awk {'print $2'}`]
  LOAD_AVG=`cat /proc/loadavg | awk {'print $1,$2,$3'}`
     
  echo "$DATE,$TOTAL_MEM_USED,$TOTAL_MEM_AVAILABLE,$TOMA_MEM_USED,$MGMT_CM_MEM_USED,$NVMESHAGENT_MEM_USED,$NODE_MEM_USED,$MONGO_MEM_USED,$MONGO_MEM_DETAILED,$KERNEL_MEM_USED,$LOAD_AVG" >> $output_file
 
  sleep $time_interval 
done
