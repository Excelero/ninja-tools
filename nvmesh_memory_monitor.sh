#!/bin/bash
    echo "DATE,TOTAL_MEM_USED,TOTAL_MEM_AVAILABLE,TOMA_MEM_USED,MGMT_CM_MEM_USED,NVMESHAGENT_MEM_USED,NODE_MEM_USED,MONGO_MEM_USED,MONGO_MEM_DETAILED,KERNEL_MEM_USED,LOAD_AVG" > /var/log/`hostname`-nvmesh-memory.csv
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
     
    echo "$DATE,$TOTAL_MEM_USED,$TOTAL_MEM_AVAILABLE,$TOMA_MEM_USED,$MGMT_CM_MEM_USED,$NVMESHAGENT_MEM_USED,$NODE_MEM_USED,$MONGO_MEM_USED,$MONGO_MEM_DETAILED,$KERNEL_MEM_USED,$LOAD_AVG" >> /var/log/`hostname`-nvmesh-memory.csv
 
    sleep 60 
done
