#!/bin/bash
# 2006, ypc
# This script is to change Logical Volume for FAST partition from RAID 0 to RAID 1+0.
# 1.3

ask () {
	echo -en "\n\tContinue? (y/n) : "; read da; case "$da" in y*)echo -e "\tOkay.";; *) exit 1;; esac
}

echo -e "\t*** This script is to change Logical Volume for FAST partition from RAID 0 to RAID 1+0." 
ask

checkbk () {
	[ -d /var/fastdata ] && {
		echo -e "\t/var/fastdata EXIST. Please remove."
		exit 1
	}
}

#### FUNCTIONS:
# Stoping FAST
stopfast () {
	echo "Stopping FAST..."
	su - fast -c "nctrl stop"
	test=$(ps -efw | grep fast | grep -v grep| grep -v $0 | wc -l)
	if [ $test -lt 1 ]; then
       		echo "FAST is stoped."
	else
		echo -e '\E[33m'"\t\033[1mERROR:\033[0m\tFAST didn't stop\n\tby runing: su - fast -c \"nctrl stop\"\n\t check if user fast is loged in."
		exit 1
	fi
}

# Making fast smaller
# First remove the *.scrap files
cleanup () {
	echo -e "\n\tCleaning up fast data.\n\tFollowing files will be removed:"
	find /usr/local/fast -name '*.scrap' 
	ask
	find /usr/local/fast -name '*.scrap' -exec rm {} \;
	# removing zip files
	find /usr/local/fast -name '*.zip' -exec rm {} \;
	# removing core files
	find /usr/local/fast -name "core.[0-9]*" | xargs file | grep "LSB core file" | awk -F: '{print $1}' | xargs rm

	# Now. Lets remove the unused indexs.
	host=$(hostname | awk -F"." '{print $1}')
	datacenter=${host:0:3}
	index=$(expr "$host" : '.*\(.\)')
	for ds in datasearch datasearch_c2; do
		keepidx=$(ssh $datacenter\fsidx$index cat /usr/local/fast/$ds/data/data_index/indexValid.0)
		if [ $keepidx -eq 0 ]; then
			echo -e "\tWill be removing /usr/local/fast/$ds/data/data_index/index_0_1\n\tKeepindes is $keepidx"
			ask
			rm -fr /usr/local/fast/$ds/data/data_index/index_0_1
		else
			if [ $keepidx -eq 1 ]; then
				echo -e "\tWill be removing /usr/local/fast/$ds/data/data_index/index_0_0\n\tKeepindes is $keepidx"
				ask
				rm -fr /usr/local/fast/$ds/data/data_index/index_0_0
			fi
		fi
		rm -f /usr/local/fast/$ds/var/log/querylogs/query_log.200607*
	done
}
# Check disk space, now that we removed some stuff from FAST it should fit on the root filesystem
checksize () {
	# Size of used by fast in Gb
	#size=$(df -h /usr/local/fast | tail -1 | awk '{print $3}' | sed 's/G//')
	size=$(df -k /usr/local/fast | tail -1 | awk '{print $3}')
	# Size avaliable on / in Gb
	#$rootsize=$(df -h /dev/cciss/c0d0p3 | tail -1 | awk '{print $4}'| sed 's/G//')
	rootsize=$(df -k /dev/cciss/c0d0p3 | tail -1 | awk '{print $4}')
	if [ $rootsize -lt $size ]; then
		echo -e "\tWARNING! We have no room to backup fast data!\n\tReduce the size of fast manualy and run the script again."
		exit 1
	fi
	echo -e "\tDiskspace: / - $rootsize \t /usr/local/fast - $size \n\tStarting to make backup."
	ask
}

##### DATA back up
backupdata () {
	echo -e "\tMaking the backup...."
	mkdir /var/fastdata && cd /usr/local/fast; star cf - . | (cd /var/fastdata; star xpf -)
	cd /
}

checkbackupsize () {
	echo -e "\tWill check the size of the backup..."
	fastsize=$(du -sh /usr/local/fast | awk '{print $1}')
	backupsize=$(du -sh /var/fastdata | awk '{print $1}')
	if [ "$fastsize" != "$backupsize" ]; then
		echo -e "\tSizes are different: /usr/local/fast - $fastsize\t/var/fastdata - $backupsize\n\tCheck, exiting."
		exit 1
	else
		echo -e "\tlooks good: /usr/local/fast - $fastsize\t/var/fastdata - $backupsize"
	fi
}

##### Unmount fast partition
umountfast () {
	echo -e "\n\tWill unmount /usr/local/fast"
	ask
	umount /usr/local/fast 1>/dev/null 2>&1
	if [ $? != 0 ]; then
		echo -e '\E[33m'"\t\033[1mERROR:\033[0m\UMOUNT Failed. Exiting."
		exit 1
	fi
}

##### Change the RAID
# Checking if we have the right Logical Drive, system is on LG:
raidchange () {
	cld=$(hpacucli ctrl slot=0 ld all show | grep 67.8 | awk '{print $2}')
	if [ $cld -ne 1 ]; then
		echo -e '\E[33m'"\t\033[1mERROR:\033[0m\\tld 1 consists of 146 GB drives. Exiting."
		exit 1
	fi

	slg=$(hpacucli ctrl slot=0 pd all show | grep -m 1 146.8 | awk '{print $2}' | awk -F: '{print $1}')
	if [ $slg -ne 2 ]; then
		echo -e '\E[33m'"\t\033[1mld 2 uses drives on port 1.\033[0m\Please verify."
		hpacucli ctrl slot=0 ld all show
		hpacucli ctrl slot=0 pd all show
		echo -e "\Do you want to proceed with the deletion of ld 2?"
		ask
		hpacucli ctrl slot=0 ld 2 delete forced
		echo -e "\tCreating ld with RAID 1+0 with command: \"hpacucli ctrl slot=0 create type=ld drives=1:2,1:3,1:4,1:5 raid=1+0\""
		ask
		hpacucli ctrl slot=0 create type=ld drives=1:2,1:3,1:4,1:5 raid=1+0
		echo -e "\tPlease verify:"
		hpacucli ctrl slot=0 ld all show
		hpacucli ctrl slot=0 pd all show
	else
		echo -e "\tCheck configuration:"
		hpacucli ctrl slot=0 ld all show
		hpacucli ctrl slot=0 pd all show
		echo -e "\Do you want to proceed with the deletion of ld 2?"
		ask
		hpacucli ctrl slot=0 ld 2 delete forced
		echo -e "\tCreating ld with RAID 1+0" 
		hpacucli ctrl slot=0 create type=ld drives=2:2,2:3,2:4,2:5 raid=1+0
		echo -e "\tPlease verify:"
		hpacucli ctrl slot=0 ld all show
		hpacucli ctrl slot=0 pd all show
	fi
}

##### Create partition
createpartition () {
	echo -e "\n\tWill be adding a primary partition to /dev/cciss/c0d1, please verify:"
	ask
	echo -e "Creating primary partition on /dev/cciss/c0d1 ..."
	fdisk /dev/cciss/c0d1 1>/dev/null 2>&1 <<DO
n
p
1


w
DO
	echo -e "\tPlease verify that partition was created:"
	fdisk /dev/cciss/c0d1 -l
}

##### If we got this far, time to make the filesystem
makefilesystem () {
	echo -e "\tMaking a filesystem.."
	mke2fs -m 2 -j /dev/cciss/c0d1p1
	#### Mount
	mount /usr/local/fast
}

##### Restore the data
restoredata () {
	echo -e "\tRestoring from the backup..."
	cd /var/fastdata; star cf - . | (cd /usr/local/fast; star xpf -)
	chown fast.fast /usr/local/fast
}

##### DO IT HERE:

checkbk
stopfast
cleanup
checksize
backupdata
checkbackupsize
#cp -r -u /usr/local/fast /var/fastdata
umountfast
raidchange
createpartition
makefilesystem
restoredata

echo -e "\n\tDONE.\n\tNow. Once the entire row is done start fast with:\n\tsu - fast -c \"nctrl stop\""
exit 0
