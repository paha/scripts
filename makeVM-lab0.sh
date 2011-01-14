#!/bin/bash
#
# spk Nov 2008
# Creates a VM and puts an OS on it.
# updated to use vSphere vcli and tools plus general style improvements, Nov 2009
#

#---Variables------------------------------------------------------------------
lock=/tmp/makeVm.lock
TemplateFile=/tmp/vmcreate.xml
vmPerlPath=/opt/spk/lib/vmware-vcli/apps
# Default parameters:
VMDatastore=filer1a-vms
# disk size 20Gb
VMDisksize=20971520
VMMemsize=768

# TODO (from October 2008):
# -add to the template VM resource pool, any other parameters to be templated?
# -if something goes wrong, give an option to scrap everything that was done
# -when puppet external store is in place, add the node to puppet
# -having external puppet store DB will also allow to pull/put data from there, integrating Inf tools and cutting steps needed to deploy


#------FUNCTIONS---------------------------------------------------------------
usage () {
	cat<< USAGE

 USAGE: $(basename $0) -i ipAddress [other parameters]
 Script creates VM and cobbler system with the MAC of created VM, then powers on the VM so it would get OS.
 Requires resolvable IP. Default values are in (). Provide parameters or change defaults in the script if needed.
    -i  Required. IP address. No default.
    -n  VMname. If not provided, FQDN will be used. ($VMName)
    -h  VM Host on which vm will be made. (vc1 - vmhost3; vc3 - vmhost15)
    -d  VM Datacenter. (vc1 = sealab; vc3 = Devlab)
    -o  VM Guest OS. Valid OSs: rhel5-x86-64,rhel5.2-x86-64,rhel5.5-x86-64,rhel5-i386,rhel4-x86-64,centos5-x86-64,centos5.3-x86-64,(centos5.5-x86-64),centos5-i386
    -s  VM Datastore. ($VMDatastore)
    -k  VM Disk size. ($VMDisksize)
    -m  VM Memory size. ($VMMemsize)
    -t  VM VLAN. Will be determined based on IP.
    -y  Non-interactive mode. Answers yes to all prompts (false)
    -c  VirtualCenter. Valid VCs: vc1 and vc3. (vc3)

USAGE
}

makeTemplate () {
    cat > $TemplateFile <<TEMPLATE
<?xml version="1.0"?>
<Virtual-Machines>
TEMPLATE
    # separating so we could make a set of VMs:
    #for (( i=0; i <= ${#VMname[@]}; i++)); do
    cat >> $TemplateFile <<TEMPLATE
    <Virtual-Machine>
        <Name>$VMName</Name>
        <Host>$VMHost</Host>
        <Datacenter>$VMDC</Datacenter>
        <Guest-Id>$VMOS</Guest-Id>
        <Datastore>$VMDatastore</Datastore>
        <Disksize>$VMDisksize</Disksize>
        <Memory>$VMMemsize</Memory>
        <Number-of-Processor>1</Number-of-Processor>
        <Nic-Network>$VMnet</Nic-Network>
        <Nic-Poweron>1</Nic-Poweron>
    </Virtual-Machine>
TEMPLATE
    #done
cat >> $TemplateFile <<TEMPLATE
</Virtual-Machines>
TEMPLATE
}

ask () {
	[ -z $noprompt ] || return
	echo -en "Are we good to go? (y,yes)|(n,no) : "
	read da
    [[ "$da" =~ "y" ]] || ERROR "Terminating futher execution."
}

EXIT () {
	rm -f $lock $TemplateFile /tmp/$VMName.info 2>/dev/null
	exit 1
}

ERROR () {
    usage
    echo -e "\n ERROR: ${1:-"Unknown Error"}" 1>&2
    EXIT
}

makevm () {
    cat <<CHECK

 About to create a VM with following parameters:
 	VI Server: 	$VI_SERVER
 	Name: 		$VMName
 	Host: 		$VMHost
	Datacenter:	$VMDC
	Guest-Id: 	$VMOS
	Datastore: 	$VMDatastore
	Disksize: 	$VMDisksize
	Memory: 	$VMMemsize
	Procs:		1
	Network:	$VMnet

CHECK

    ask
    makeTemplate

    # Using viperl script and created template to make VM. It is different from the standard script just in the definition of the controller
    echo -e "\n > Creating vm $VMName on $VMHost...\n"
    $vmPerlPath/spk/vmcreate-spk.pl --filename $TemplateFile --schema $vmPerlPath/schema/vmcreate.xsd
    [ $? != 0 ] && ERROR " Something went wrong while making VM"

    # checking if vm was made
    echo -e "\n > Gathering info about $VMName..." 
    $vmPerlPath/vm/vminfo.pl --vmname $VMName > /tmp/$VMName.info
    [ $(grep -c 'not found' /tmp/$VMName.info) -gt 0 ] && ERROR " Something went wrong while making VM"

    #echo -e "\tBellow is the info from VI about the new VM:"
    #cat /tmp/$VMName.info
}

getMAC () {
    # obtaining MAC from the new VM
    echo -e "\n > Getting MAC of $VMName..." 
    vmMAC=$($vmPerlPath/spk/getNicInfo.pl --vm $VMName 2>/dev/null)
    [ -z $vmMAC ] && ERROR " Failed to get MAC for VMName. Will not continue."
}

makeSystem () {
    cat <<CHECK

 About to make a cobbler system with the following parameters:
	Name:		$VMName
	ip:		$IP
	MAC:		$vmMAC
	hostname:	$FQDN
	Gateway:	$DGW
	Profile:	$CobProfile	

CHECK

    ask
    # making cobbler system
    # if the systems is already there, which is fine, we will enable netboot and update MAC
    if [ $(cobbler system report --name $VMName | wc -l) -gt 10 ]; then
        # the system is there, so we will use 'edit'
        # $cobbler_CMD system edit --name $VMName --netboot-enabled=1 --mac=$vmMAC
        # Oct 2009 - rather then edit, we will remove it.
        echo -e "\n > Removing cobbler system $VMName ..."
        cobbler system remove --name=$VMName
    fi

    # Creating a cobbler system:
    echo -e "\n > Creating cobbler system $VMName ..."
    cobbler system add --name=$VMName --ip=$IP --mac=$vmMAC --hostname=$FQDN --gateway=$DGW --subnet=255.255.255.0 --netboot-enabled=1 --profile=$CobProfile --ksmeta="nameserver=10.110.1.13" --dns-name=$FQDN --static=1
    [ $? != 0 ] && ERROR " Something went wrong. Check out the errors, and try again when issues are addressed."
    cobbler sync
}

powerONvm () {
    # powering on the new VM
    echo -e "\n > Powering ON $VMName..."
    $vmPerlPath/vm/vmcontrol.pl --vmname $VMName --operation poweron >/tmp/$VMName.info
    if [ $(grep -c 'Fault' /tmp/$VMName.info) -gt 0 ]; then
    	echo -e "\n\tSomething went wrong. Failed to power On the $VMName.\n You would have to check it manualy, but the rest is complete."
    else
	    cat /tmp/$VMName.info
	    echo -e "\n Done.\n $FQDN should be getting it's OS now, check it in a few."
    fi
}

#---Script---------------------------------------------------------------------
[ "$(/usr/bin/whoami)" != "root" ] && ERROR "Must be root"
[ -x /usr/bin/cobbler -o -d $vmPerlPath/spk ] || ERROR " cobbler and(or) vmware-viperl is missing on this host. Can't continue."
[ -e $lock ] && ERROR " Lock file present ($lock). Exiting."
touch $lock

# we expect more then two command line arguments 
[ $# -lt 2 ] && ERROR " Not enough arguments to continue."

# getting our parameters
while getopts "yi:n:h:d:o:s:k:m:v:c:" OPTION; do
	case "$OPTION" in
		i)	IP=$OPTARG;;
		n)	VMName=$OPTARG;;
		h)	VMHost=$OPTARG;;
		d)	VMDC=$OPTARG;;
		o)	OS=$OPTARG;;
		s)	VMDatastore=$OPTARG;;
		k)	VMDisksize=$OPTARG;;
		m)	VMMemsize=$OPTARG;;
		v)	VMnet=$OPTARG;;
		y)	noprompt=1;;
    c)  VC=$OPTARG;;
    \?)	ERROR " What "
	esac
done

[ -z "$IP" ] && ERROR "Must have IP to continue."

# Getting VC session parameters
case "$VC" in
    vc3|""|VC3)     
        VCrc=/root/.vSphererc
        [ -z $VMHost ] && VMHost=vmhost10.lab0.speakeasy.priv
        [ -z $VMDC ] && VMDC=DevLab;;
    vc1|VC1)        
        VCrc=/root/.viperlrc
        [ -z $VMHost ] && VMHost=vmhost3.lab0.speakeasy.priv
        [ -z $VMDC ] && VMDC=sealab;;
    *)              ERROR " Unknown VirtualCenter."
esac

if [ -r $VCrc ]; then
	source $VCrc
else
	ERROR " $VCrc not found. Needed to get connection settings to VI. Can't continue."
fi

# getting hostname from reverse lookup
HOST=$(host -4 $IP)
if [ -z "$HOST" -o $? != 0 ]; then
	ERROR " Failed reverse lookup $IPCheck the IP."
else
    FQDN=$(echo $HOST | awk '{print $NF}' | sed 's/[.\t]*$//')
fi

# checking if IP is not used
ping -c 1 -w 1 $IP  1>/dev/null 2>&1 
[ $? == 0 ] && ERROR " $IP is alive. Terminating futher execution."

[ -z "$VMName" ] && VMName=$FQDN

# trying to get VLAN for VM. Working only with 10.111.0.0/16 now.
# Nov 2009. Temporarily dropped a map from vmhost15, until we will build more intelligent tools. 
[ -z $VMnet ] && {
	dsub=$(echo $IP | awk -F. '{print $2"."$3}')
   case "$dsub" in
        "112.1")    VMnet="Vlan2201-rd-spk-public-10.112.1.0-24";;
        "112.120")  VMnet="Vlan2320-rd-int-apps-10.112.120.0-24";;
        "112.122")  VMnet="Vlan2322-sys-apps-int-10.112.122.0-24";;
        "112.210")  VMnet="Vlan2410-rd-filer-apps-10.112.210.0-24";;
        "112.220")  VMnet="Vlan2420-rd-dmz-mgmt-10.112.220.0-24";;
        "112.222")  VMnet="Vlan2422-rd-apps-mgmt-10.112.222.0-24";;
        "112.250")  VMnet="Vlan2450-rd-net-mgmt-10.112.250.0-24";;
        "111.1")    VMnet="Vlan1201-qa-spk-public-10.111.1.0-24";;
        "111.220")  VMnet="Vlan1420-qa-dmz-mgmt-10.111.220.0-24";;
        "111.222")  VMnet="Vlan1422-qa-apps-mgmt-10.111.222.0-24";;
        "110.1")    VMnet="Vlan201-stage-spk-public-10.110.1.0-24";;
        "110.214")  VMnet="Vlan414-stage-filer-mgmt-10.110.214.0-24";;
        "110.220")  VMnet="Vlan420-stage-dmz-mgmt-10.110.220.0-24";;
        "110.222")  VMnet="Vlan422-stage-apps-mgmt-10.110.222.0-24";;
        *)          ERROR " Unsupported vlan." 
    esac
}

# trying to sort out OS
if [ -z "$OS" ]; then
	# Setting defaults:
	VMOS=rhel5_64Guest
	CobProfile=Centos-5.5-x86_64
else
	case "$OS" in
		# there are only 5 profiles in cobbler now
		rhel5-x86-64)	VMOS=rhel5_64Guest; CobProfile=RHEL-5.5-x86_64;;
		rhel5.2-x86-64)	VMOS=rhel5_64Guest; CobProfile=RHEL-5-x86_64;;
		rhel5.5-x86-64)	VMOS=rhel5_64Guest; CobProfile=RHEL-5.5-x86_64;;
		rhel5-i386)	VMOS=rhel5_32Guest; CobProfile=RHEL-5-i386;;
		rhel4-x86-64)	VMOS=rhel4_64Guest; CobProfile=rhel46-es-x86_64;;
		centos5-x86-64) VMOS=rhel5_64Guest; CobProfile=Centos-5.5-x86_64;;
 	        centos5.3-x86-64) VMOS=rhel5_64Guest; CobProfile=Centos-5-x86_64;;
 	        centos5.5-x86-64) VMOS=rhel5_64Guest; CobProfile=Centos-5.5-x86_64;;
		centos5-i386)   VMOS=rhel5_32Guest; CobProfile=Centos-5-i386;;
		*)              ERROR " Invalid OS provided.";;
	esac
fi

makevm
getMAC

# we need to determine default gateway
DGW=$(echo $IP | awk -F"." '{print $1"."$2"."$3"."1}')

makeSystem
powerONvm

rm -f $lock $TemplateFile /tmp/$VMName.info 2>/dev/null
exit 0
