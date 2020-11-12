# Excelero Ninja Tools

The Excelero Ninja Tools are a set of system check tools that shouldn't be missing from any storage ninja's utility belt to ensure mission success.

Tool | Purpose
------------ | -------------
`ib_send_bw_all_to_1.sh` | Check N-to-1 network congestion handling
`ib_send_bw_all_to_all.sh` | Check that each host can communicate with all other hosts
`get_roce_throughput.sh` | Show live throughput for RoCE interfaces of a host
`get_ib_throughput.sh` | Show live throughput for InfiniBand interfaces of a host
`nvmesh_for_each_drive.sh` | Check each individual drive in a NVMesh cluster
`nvmesh_memory_monitor.sh` | Monitor NVMesh related memory
`nvmesh_update_RO_fs` | Switch easily between shared read only mount to exclusive read write mount modes
`fio_simple.sh` | Simple wrapper for fio to test block device throughput, IOPS, latency
`pcie_find_downgraded.sh`| Find PCIe devices with downgraded link speed/width

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

#### nvmesh_memory_monitor.sh: Monitor the NVMesh related memory 
When running the nvmesh_memory_monitor.sh, a CSV file will be created under /var/log/`hostname`-nvmesh-memory.csv. The content of the file can be imported into programs like MS Excel (with delimiter options of comma and space) and a memory graph can be easily created.

#### nvmesh_update_RO_fs: Switch easily between shared read only mount to exclusive read write mount modes
This script is orchestating the flow of updating a shared read only file system data.
It will umount all of the read-only mounted clients and mount it as read write on the desired client - and the opposite

#### fio_simple.sh: Simple wrapper for fio to test block device throughput, IOPS, latency
The flexible I/O tester (`fio`) has a vast amount of options, which can easily be overwhelming. This is a simple wrapper for `fio` to test block device throughput, IOPS and latency based on Excelero's best practices.  
(This tool is also known as the `dorw` script in Excelero's best practices.)

#### pcie_find_downgraded.sh: Find PCIe devices with downgraded link speed/width
Queries existing PCIe devices via `lspci`, filtered to only include Mellanox NICs or NVMe drives, and shows devices for which the current PCIe link speed or link width does not match the device capabilities. This helps to identify devices that were put in the wrong slot or are not running at full link speed for other reasons.
