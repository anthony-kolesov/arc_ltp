#!/bin/sh

################################################################################
#                                                                              #
# Copyright (c) 2009 FUJITSU LIMITED                                           #
#                                                                              #
# This program is free software;  you can redistribute it and#or modify        #
# it under the terms of the GNU General Public License as published by         #
# the Free Software Foundation; either version 2 of the License, or            #
# (at your option) any later version.                                          #
#                                                                              #
# This program is distributed in the hope that it will be useful, but          #
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY   #
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License     #
# for more details.                                                            #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program;  if not, write to the Free Software                 #
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA      #
#                                                                              #
# Author: Miao Xie <miaox@cn.fujitsu.com>                                      #
#                                                                              #
################################################################################

cd $LTPROOT/testcases/bin

. ./cpuset_funcs.sh

export TCID="cpuset11"
export TST_TOTAL=6
export TST_COUNT=1

exit_status=0
# must >= 3 for: 1-$((nr_mems-2))
nr_cpus=4
nr_mems=3

# In general, the cache hog will use more than 10000 kb slab space on the nodes
# on which it is running. The other nodes' slab space has littler change.(less
# than 1000 kb).
upperlimit=10000
lowerlimit=2000

cpus_all="$(seq -s, 0 $((nr_cpus-1)))"
mems_all="$(seq -s, 0 $((nr_mems-1)))"

nodedir="/sys/devices/system/node"

FIFO="./myfifo"

declare -a memsinfo

init_mems_info_array()
{
	local i=

	for i in `seq 0 $((nr_mems-1))`
	do
		memsinfo[$i]=0
	done
}

# get_meminfo <nodeid> <item>
get_meminfo()
{
	local nodeid="$1"
	local nodepath="$nodedir/node$nodeid"
	local nodememinfo="$nodepath/meminfo"
	local item="$2"
	local infoarray=(`cat $nodememinfo | grep $item`)
	memsinfo[$nodeid]=${infoarray[3]}
}

# freemem_check
# We need enough memory space on every node to run this test, so we must check
# whether every node has enough free memory or not.
# return value: 1 - Some node doesn't have enough free memory
#               0 - Every node has enough free memory, We can do this test
freemem_check()
{
	local i=

	for i in `seq 0 $((nr_mems-1))`
	do
		get_meminfo $i "MemFree"
	done

	for i in `seq 0 $((nr_mems-1))`
	do
		# I think we need 100MB free memory to run test
		if [ ${memsinfo[$i]} -lt 100000 ]; then
			return 1
		fi
	done
}

# get_memsinfo
get_memsinfo()
{
	local i=

	for i in `seq 0 $((nr_mems-1))`
	do
		get_meminfo $i "FilePages"
	done
}

# account_meminfo <nodeId>
account_meminfo()
{
	local nodeId="$1"
	local tmp="${memsinfo[$nodeId]}"
	get_meminfo $@ "FilePages"
	memsinfo[$nodeId]=$((${memsinfo[$nodeId]}-$tmp))
}

# account_memsinfo
account_memsinfo()
{
	local i=

	for i in `seq 0 $((nr_mems-1))`
	do
		account_meminfo $i
	done
}


# result_check <nodelist>
# return 0: success
#	 1: fail
result_check()
{
	local nodelist="`echo $1 | sed -e 's/,/ /g'`"
	local i=

	for i in $nodelist
	do
		if [ ${memsinfo[$i]} -le $upperlimit ]; then
			return 1
		fi
	done

	local allnodelist="`echo $mems_all | sed -e 's/,/ /g'`"
	allnodelist=" "$allnodelist" "
	nodelist=" "$nodelist" "

	local othernodelist="$allnodelist"
	for i in $nodelist
	do
		othernodelist=`echo "$othernodelist" | sed -e "s/ $i / /g"`
	done

	for i in $othernodelist
	do
		if [ ${memsinfo[$i]} -gt $lowerlimit ]; then
			return 1
		fi
	done
}

# general_memory_spread_test <cpusetpath> <is_spread> <cpu_list> <node_list> \
# <expect_nodes> <test_pid>
# expect_nodes: we expect to use the slab or cache on which node
general_memory_spread_test()
{
	local cpusetpath="$CPUSET/1"
	local is_spread="$1"
	local cpu_list="$2"
	local node_list="$3"
	local expect_nodes="$4"
	local test_pid="$5"

	cpuset_set "$cpusetpath" "$cpu_list" "$node_list" "0" 2> $CPUSET_TMP/stderr
	if [ $? -ne 0 ]; then
		cpuset_log_error $CPUSET_TMP/stderr
		tst_resm TFAIL "set general group parameter failed."
		return 1
	fi

	/bin/echo "$is_spread" > "$cpusetpath/memory_spread_page" 2> $CPUSET_TMP/stderr
	if [ $? -ne 0 ]; then
		cpuset_log_error $CPUSET_TMP/stderr
		tst_resm TFAIL "set spread value failed."
		return 1
	fi

	/bin/echo "$test_pid" > "$cpusetpath/tasks" 2> $CPUSET_TMP/stderr
	if [ $? -ne 0 ]; then
		cpuset_log_error $CPUSET_TMP/stderr
		tst_resm TFAIL "attach task failed."
		return 1
	fi

	# we'd better drop the caches before we test page cache.
	/bin/echo 3 > /proc/sys/vm/drop_caches 2> $CPUSET_TMP/stderr
	if [ $? -ne 0 ]; then
		cpuset_log_error $CPUSET_TMP/stderr
		tst_resm TFAIL "drop caches failed."
		return 1
	fi

	# wait for droping the cache
	sleep 10

	get_memsinfo
	/bin/kill -s SIGUSR1 $test_pid
	read exit_num < $FIFO
	if [ $exit_num -eq 0 ]; then
		tst_resm TFAIL "hot mem task failed."
		return 1
	fi

	account_memsinfo
	result_check $expect_nodes
	if [ $? -ne 0 ]; then
		tst_resm TFAIL "hog the memory on the unexpected node(FilePages_For_Nodes(KB): ${memsinfo[*]}, Expect Nodes: $expect_nodes)."
		return 1
	fi
}

base_test()
{
	local pid=
	local result_num=

	setup
	if [ $? -ne 0 ]; then
		exit_status=1
	else
		./cpuset_mem_hog &
		pid=$!
		general_memory_spread_test "$@" "$pid"
		result_num=$?
		if [ $result_num -ne 0 ]; then
			exit_status=1
		fi

		/bin/kill -s SIGUSR2 $pid
		wait $pid

		cleanup
		if [ $? -ne 0 ]; then
			exit_status=1
		elif [ $result_num -eq 0 ]; then
			tst_resm TPASS "Cpuset memory spread page test succeeded."
		fi
	fi
	((TST_COUNT++))
}

# test general spread page cache in a cpuset
test_spread_page1()
{
	while read spread cpus nodes exp_nodes
	do
		base_test "$spread" "$cpus" "$nodes" "$exp_nodes"
	done <<- EOF
		0	0	0	0
		1	0	0	0
		0	0	1	1
		1	0	1	1
		0	0	0,1	0
		1	0	0,1	0,1
	EOF
	# while read spread cpus nodes exp_nodes
}

test_spread_page2()
{
	local pid=
	local result_num=

	setup
	if [ $? -ne 0 ]; then
		exit_status=1
	else
		./cpuset_mem_hog &
		pid=$!
		general_memory_spread_test "1" "$cpus_all" "0" "0" "$pid"
		result_num=$?
		if [ $result_num -ne 0 ]; then
			exit_status=1
		else
			general_memory_spread_test "1" "$cpus_all" "1" "1" "$pid"
			result_num=$?
			if [ $result_num -ne 0 ]; then
				exit_status=1
			fi
		fi

		/bin/kill -s SIGUSR2 $pid
		wait $pid

		cleanup
		if [ $? -ne 0 ]; then
			exit_status=1
		elif [ $result_num -eq 0 ]; then
			tst_resm TPASS "Cpuset memory spread page test succeeded."
		fi
	fi
}

init_mems_info_array
freemem_check
if [ $? -ne 0 ]; then
	tst_brkm TFAIL ignored "Some node doesn't has enough free memory(100MB) to do test(MemFree_For_Nodes(KB): ${memsinfo[*]})."
	exit 1
fi

dd if=/dev/zero of=./DATAFILE bs=1M count=100
if [ $? -ne 0 ]; then
	tst_brkm TFAIL ignored "Creating DATAFILE failed."
	exit 1
fi

# drop page caches
/bin/echo 1 > /proc/sys/vm/drop_caches

# wait for droping caches
sleep 10

mkfifo $FIFO
if [ $? -ne 0 ]; then
	rm -f DATAFILE
	tst_brkm TFAIL ignored "failed to mkfifo $FIFO"
	exit 1
fi

test_spread_page1
test_spread_page2

rm -f DATAFILE $FIFO

exit $exit_status
