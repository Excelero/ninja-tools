# Excelero Ninja Tools

The Excelero Ninja Tools are a set of system check tools that shouldn't be missing from any storage ninja's utility belt to ensure mission success.

Tool | Purpose
------------ | -------------
`ib_send_bw_all_to_1.sh` | Check N-to-1 network congestion handling
`ib_send_bw_all_to_all.sh` | Check that each host can communicate with all other hosts
`get_roce_throughput.sh` | Show live throughput for RoCE interfaces of a host
`get_ib_throughput.sh` | Show live throughput for InfiniBand interfaces of a host
`nvmesh_for_each_drive.sh` | Check each individual drive in a NVMesh cluster

#### ib_send_bw_all_to_1.sh: Check N-to-1 network congestion handling
Takes a list of hosts (including mlx device and device port to use) as arguments and uses the first one in the list as the "1" in "N-to-1". The following hosts are the "N", meaning all following send data concurrently to the first one in the list through `ib_send_bw`. The resulting throughput numbers makes it easy to see if the congestion handling of a RoCE network has not been configured well.
#### ib_send_bw_all_to_all.sh: Check that each host can communicate with all other hosts
Takes a list of hosts and establishes point to point connections from all given IP addresses to all other given IP addresses though `ib_send_bw`. The resulting numbers confirm connectivity and also that throughput meets the expected level.
#### get_roce_throughput.sh: Show live throughput for RoCE interfaces of a host
Helps to see if a network throughput limit is hit and to ensure that data is flowing the way it is supposed to flow, e.g. nicely balanced across multiple interfaces. Reads RDMA unicast traffic counters from `ethtool`.
#### get_ib_throughput.sh: Show live throughput for InfiniBand interfaces of a host
Helps to see if a network throughput limit is hit and to ensure that data is flowing the way it is supposed to flow, e.g. nicely balanced across multiple interfaces. Reads port data counters in `/sys/class/infiniband`.
#### nvmesh_for_each_drive.sh: Check each individual drive in a NVMesh cluster
Can create/attach a volume for each drive and then run an arbitrary command (e.g. time-based `fio`) for each single-drive volume to make sure the drive is behaving normal. The built-in help shows a `fio` example.
