#!/bin/bash
#################################################################################
# Description:	This script is intended to enable you to create number of Splunk infrastructure
# 	elements on the fly. A perfect tool to setup a quick Splunk lab for training
# 	or testing purposes.
#
# List of capabilities:
#	-Extensive Error checking
#	-Load control (throttling) if exceeds 4screes
#	-Built-in dynamic host names and IP allocation
#	-Create and configure large number of Splunk hosts very fast
#	-Different logging levels (show docker commands executed)
#	-Complete multi and single site cluster builds including CM and DEP servers
#	-Manual and auto modes (standard configurations)
#	-Modular design that can easily be converted to a higher-level language like python
#	-Custom login screen (helpful for lab & Search Parties scenarios)
#	-Low resources requirements
#	-Eliminate the need to learn docker (but you should)
#	-OSX support
#
# Licenses: 	Licensed under GPL v3 <link>
# Author:    	mhassan@splunk.com
# Version:	 $Id:$
#
#Usage :  create-slunk.sh -v[3 4 5] 
#		v1-2	default setting (recommended for ongoing usage)
#		-v3	show sub-steps under each host build
#		-v4	show remote CMD executed in docker container
#		-v5	even more verbosity (debug)
# MAC OSX : must install ggrep to get PCRE regrex matching working 
# -for Darwin http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html
# -mount point must be under /User/${USER}
#
# TO-DO: -add routines for UF and HF containers with eventgen.py
#	-add DS containers with default serverclass.conf
#	-ability to adjust RF and SF
#	-abitllity to set seach affinity
#	-DMC instance
#################################################################################

#Network stuff --------
ETH_OSX="lo0"			#default interface to use with OSX laptop (el captin)
ETH_LINUX="eno1"		#default interface to use with Linux server (ubuntu 16.04

#IP aliases --------
#LINUX is routed and hosts can be reached from anywhere in the network
START_ALIAS_LINUX="192.168.1.100";  	END_ALIAS_LINUX="192.168.1.254"

#OSX space will not be routed, and host reached from the laptop only
START_ALIAS_OSX="10.0.0.100";  		END_ALIAS_OSX="10.0.0.254"

DNSSERVER="192.168.1.19"		#if running dnsmasq. Set to docker-host machine IP
#----------
#----------PATHS
#Full PATH is dynamic based on OS type, see detect_os()
FILES_DIR="$PWD" 		#place anything needs to copy to container here
LIC_FILES_DIR="NFR"		#place all your license file here
VOL_DIR="docker-volumes"	#directory name for volumes mount point.Full path is dynamic based on OS type

#The following are set in detect_os()
#MOUNTPOINT=
#ETH=
#GREP=
#----------

#----------Images
#more can be found http://hub.docker.com
SPLUNK_IMAGE="mhassan/splunk"		#my own built image 6.4.3
#SPLUNK_IMAGE="splunk/splunk"		#official image -recommended-  6.5.0
#SPLUNK_IMAGE="splunk/splunk:6.5.0"	#official image 6.5.0

#other possible options
#SPLUNK_IMAGE="outcoldman/splunk:6.4.2"	#tested but taken offline by outcoldman
#SPLUNK_IMAGE="btorresgil/splunk"	#untested
#SPLUNK_IMAGE="xeor/splunk"		#unstested
#----------

#----------Cluster stuff
BASEHOSTNAME="IDX"			#default hostname to create
CM_BASE="CM"
DMC_BASE="DMC"
LM_BASE="LM"
DEP_BASE="DEP"
IDX_BASE="IDX"
SH_BASE="SH"
SPLUNKNET="splunk-net"			#default name for splunk docker network (host-to-host comm)
#Splunk standard ports
SSHD_PORT="8022"			#in case we need to enable sshd, not recommended
SPLUNKWEB_PORT="8000"
MGMT_PORT="8089"
#KV_PORT="8191"
RECV_PORT="9997"
REPL_PORT="9887"
HEC_PORT="8081"
APP_SERVER_PORT="8065"			#new to 6.5
APP_KEY_VALUE_PORT="8191"		#new to 6.5
USERADMIN="admin"
USERPASS="hello"

RFACTOR="3"		#default replication factor
SFACTOR="2"		#default seach factor

SHCLUSTERLABEL="shcluster1"
IDXCLUSTERLABEL="idxcluster1"
LABEL="label1"
DEFAULT_SITES_NAMES="STL LON HKG"	#used in auto-mode s-2-s

MYSECRET="mysecret"
STD_IDXC_COUNT="3"	#default IDXC count
STD_SHC_COUNT="3"	#default SHC count
DEP_SHC_COUNT="1"	#default DEP count
#----------

#---------Logs
CMDLOGBIN="$PWD/cmds_capture.bin"	#capture all docker cmds (with color)
CMDLOGTXT="$PWD/cmds_capture.log"	#capture all docker cmds (just ascii txt)
#LOGFILE="${0##*/}.log"   #log file will be this_script_name.log
SCREENLOGFILE="screens_capture.log"   	#capture all screen shots during execution
HOSTSFILE="$PWD/docker-hosts.dnsmasq"  #local host file. optional if dns caching is used
#--------

#--------Load control
MAXLOADTIME=10		#seconds increments for timer
MAXLOADAVG=4		#Not used
LOADFACTOR=3            #allow (3 x cores) of load on docker-host
LOADFACTOR_OSX=1        #allow (1 x cores) for the MAC (testing..)
#--------

#--------COLORES
NC='\033[0m' # No Color
Black="\033[0;30m";             White="\033[1;37m"
Red="\033[0;31m";               LightRed="\033[1;31m"
Green="\033[0;32m";             LightGreen="\033[1;32m"
BrownOrange="\033[0;33m";       Yellow="\033[1;33m"
Blue="\033[0;34m";              LightBlue="\033[1;34m"
Purple="\033[0;35m";            LightPurple="\033[1;35m"
Cyan="\033[0;36m";              LightCyan="\033[1;36m"
LightGray="\033[0;37m";         DarkGray="\033[1;30m"
BoldYellowBlueBackground="\e[1;33;44m"
#--------

#-------Misc
GREP_OSX="/usr/local/bin/ggrep" #you MUST install Gnu grep on OSX
GREP_LINUX="/bin/grep"          #default grep for Linux
PS4='$LINENO: '			#show line num when used bash -x ./script.sh
FLIPFLOP=0			#used to toggle color value in logline().Needs to be global
#Set the local splunkd path if you're running Splunk on this docker-host (ex laptop).
#Used in validation_check() routine to detect local instance and kill it.
LOCAL_SPLUNKD="/opt/splunk/bin/splunk"  #don't run local splunkd instance on docker-host
#----------

# *** Let the fun begin ***

#Log level is controlled with I/O redirection. Must be first thing executed in a bash script
# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
exec >> >(tee -i $SCREENLOGFILE)
exec 2>&1

#---------------------------------------------------------------------------------------------------------
check_shell () {
# Check that we're in a BASH shell
if test -z "$BASH" ; then
  echo "This script ${0##*/} must be run in the BASH shell... Aborting."; echo;
  exit 192
fi
return 0
}    #end check_shell()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
logline() { 
#Log docker CMD string to logfile. Group event color by host
cmd=$1; curr_host=$2
#DATE=` date +'%b %e %R'`
DATE=`date +%Y-%m-%d:%H:%M:%S`
#echo "curr[$curr_host]  prev[$prev_host]" >> $CMDLOGBIN

#change log entry color when the remote docker cmd executed in new host
if [ "$FLIPFLOP" == 0 ] && [ "$curr_host" != "$prev_host" ]; then 
	FLIPFLOP=1; COLOR="${LightBlue}"; echo > $CMDLOGBIN
elif [ "$FLIPFLOP" == 1 ] && [ "$curr_host" != "$prev_host" ]; then
	FLIPFLOP=2; COLOR="${Yellow}"; echo > $CMDLOGBIN
elif [ "$FLIPFLOP" == 2 ] && [ "$curr_host" != "$prev_host" ]; then
        FLIPFLOP=0; COLOR="${LightCyan}"; echo > $CMDLOGBIN
fi

printf "${White}[$DATE]:${NC}$COLOR $cmd${NC}\n" >> $CMDLOGBIN
printf "[$DATE]: $cmd$\n" >> $CMDLOGTXT

#echo "[$DATE]:$cmd\n" >> $CMDLOGBIN
#sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" -i $CMDLOGBIN
prev_host=$curr_host

return 0
}
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
remove_ip_aliases () {
#Delete ip aliases on the interface (OS dependent)

base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `; # base_ip=$base_ip"."
start_octet4=`echo $START_ALIAS | cut -d"." -f4 `
end_octet4=`echo $END_ALIAS | cut -d"." -f4 `

if [ "$os" == "Darwin" ]; then
	read -p "Enter interface aliases binded to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_OSX"; fi
	for i in `seq $start_octet4  $end_octet4`; do
		sudo ifconfig  $eth  $base_ip.$i 255.255.255.0 -alias
        	echo -ne "${NC}Removing: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
	done
elif  [ "$os" == "Linux" ]; then
	read -p "Enter interface aliases binded to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_LINUX"; fi
 	for  ((i=$start_octet4; i<=$end_octet4 ; i++))  do
                echo -ne "${NC}Removing: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
                sudo ifconfig $eth:$i "$base_ip.$i" down;
        done
fi
printf "${NC}\n"
return 0
}
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
setup_ip_aliases () {
#Check if ip aliases created, if not them bring up (tested on Ubuntu 16.04). Quick and dirty method. May need to change

base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `; # base_ip=$base_ip"."
start_octet4=`echo $START_ALIAS | cut -d"." -f4 `
end_octet4=`echo $END_ALIAS | cut -d"." -f4 `

printf "${LightBlue}==>${NC} Checking if last IP alias is configured on any NIC [$END_ALIAS]..."
last_alias=`ifconfig | $GREP $END_ALIAS `
if [ -n "$last_alias" ]; then
	printf "${Green} OK!\n"
else
	printf "${Red}NOT FOUND${NC}\n"
fi
echo
if [ "$os" == "Darwin" ] && [ -z "$last_alias" ]; then
	read -p "Enter interface to bind aliases to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_OSX"; fi
	printf "Building IP aliases for OSX...[$base_ip.$start_octet4-$end_octet4]\n"
        #to remove aliases repeat with -alias switch
        for i in `seq $start_octet4  $end_octet4`; do 
		sudo ifconfig  $eth  $base_ip.$i 255.255.255.0 alias
        	echo -ne "${NC}Adding: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
	done
elif [ "$os" == "Linux" ] && [ -z "$last_alias" ]; then
	read -p "Enter interface to bind aliases to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_LINUX"; fi
	printf "Building IP aliases for LINUX...[$base_ip.$start_octet4-$end_octet4]\n"
	for  ((i=$start_octet4; i<=$end_octet4 ; i++))  do 
        	echo -ne "${NC}Adding: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
		sudo ifconfig $eth:$i "$base_ip.$i" up; 
	done
fi
printf "${NC}\n"
read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
return 0
}  #setup_ip_aliases()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_load () {
#We need to throttle back host creation if running on low powered server. Set to 4 x numb of cores

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

if [ "$os" == "Darwin" ]; then
	cores=`sysctl -n hw.ncpu`
elif [ "$os" == "Linux" ]; then
	cores=`$GREP -c ^processor /proc/cpuinfo`
fi

#int=${float%.*}
#if [ $(echo " $test > $k" | bc) -eq 1 ] float comparison
t=$MAXLOADTIME;
while true 
do
	if [ "$os" == "Darwin" ]; then
	#sudo memory_pressure -l warn| head -n 28
		loadavg=`sysctl -n vm.loadavg | awk '{print $2}'`
		LOADFACTOR=$LOADFACTOR_OSX
		#max_mem=`top -l 1 | head -n 10 | grep PhysMem | awk '{print $2}' | sed 's/G//g' `
	else
        	loadavg=`cat /proc/loadavg |awk '{print $1}'|sed 's/,//g'`
        	#max_mem=`free -mg|grep -i mem|awk '{print $2}' `
	fi

	load=${loadavg%.*}
	MAXLOADAVG=`echo $cores \* $LOADFACTOR | bc -l `
	c=`echo " $load > $MAXLOADAVG" | bc `;
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} OS:[$os] MAX ALLOWED LOAD:[$MAXLOADAVG] current load:[$loadavg] cores[$cores]${NC}\n" >&5
	if [  "$c" == "1" ]; then
		echo
		for c in $(seq 1 $t); do
			echo -ne "${LightRed}High load avg [load:$loadavg max allowed:$MAXLOADAVG cores:$cores]. Pausing ${Yellow}$t${NC} seconds... ${Yellow}$c\033[0K\r"
        		sleep 1
		done
		t=`expr $t + $t`
	else
		break
	fi
done
return 0
}  #check load()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
install_gnu_grep () {

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#----------
printf "${LightBlue}==>${NC} Checking Xcode commandline tools:${NC} "
cmd=$(xcode-select -p)
if [ -n $cmd ]; then
	printf "${Green}Already installed${NC}\n"
else
	printf "${Yellow}Running [xcode-select --install]${NC}\n"
 	cmd=$(xcode-select --install)
fi
#----------
#To completely remove brew and ggrep:
#brew uninstall grep pcre
#rm -fr /usr/local/bin/ggrep
#/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall)"
#sudo rm -rf /usr/local/Homebrew/

printf "${LightBlue}==>${NC} Checking brew package management:${NC} "
condition=$(which brew 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${Yellow}Running [/usr/bin/ruby -e \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\" ]${NC}\n"
	printf "${LightGray}"
 	/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
	printf "${NC}\n"
else
	printf "${Green}Already installed${NC}\n"
fi
#----------
printf "${LightBlue}==>${NC} Checking pcre package:${NC} "
cmd=$(brew ls pcre --versions)
if [ -n "$cmd" ]; then
	printf "${Green}Already installed${NC}\n"
else
	printf "${Yellow}Running [brew install pcre]${NC}\n"
 	brew install pcre
fi
#----------
printf "${LightBlue}==>${NC} Checking ggrep package:${NC} "
cmd=$(brew ls grep --versions|cut -d" " -f2)
if [ -n "$cmd" ]; then
        printf "${Green}Already installed${NC}\n"
else
        printf "${Yellow}Running [brew install homebrew/dupes/grep]${NC}\n"
 	brew tap homebrew/dupes
 	brew install homebrew/dupes/grep
        printf "${Yellow}Running [sudo ln -s /usr/local/Cellar/grep/$cmd/bin/ggrep /usr/local/bin/ggrep]${NC}\n"
 	sudo ln -s /usr/local/Cellar/grep/$cmd/bin/ggrep /usr/local/bin/ggrep
fi
printf "${Yellow}Running [brew list]${NC}\n"
 brew list --versions

printf "${Yellow}Installation done!${NC}\n\n"
read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
echo
return 0
}  #end install gnu_grep
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
validation_check () {
display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

if [ "$os" == "Darwin" ]; then
	printf "${LightBlue}==>${NC} Checking if GNU grep is installed [$GREP]..."
        condition=$(which $GREP_OSX 2>/dev/null | grep -v "not found" | wc -l)
        if [ $condition -eq 0 ] ; then
                printf "${Red} NOT FOUND!${NC}\n"
                printf "GNU grep is needed for this script to work. We use PCRE regex in ggrep! \n"
		read -p "Install Gnu grep ggrep? [Y/n]? " answer
        	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
			install_gnu_grep
		else
			printf "${LightRed}This scrip will not work without Gnu grep. Exiting...${NC}\n"
			printf "http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html \n"
			exit
		fi
        else
                printf "${Green} OK!${NC}\n"
        fi
fi

#-----------memory check
printf "${LightBlue}==>${NC} Checking if we have enough free memory..."
if [ "$os" == "Linux" ]; then
        max_mem=`free -mg|grep -i mem|awk '{print $2}' `
        if [ "$max_mem" -le "30" ]; then
		printf "${BrownOrange} [$max_mem GB] WARNING!${NC}\n"
		printf "${DarkGray}"
		printf "    Suggestions:\n"
                printf "    1-Recommending 32GB or more for smooth operation.\n"
                printf "    2-Some of the cluster automated builds may fail.\n"
                printf "    3-Try limiting your builds to 15 containers.\n"
                printf "    4-Kill unused apps running on this host.\n"
		printf "    5-Restart \"existed\" container manually.\n\n"
		printf "${NC}"
	else
                printf "[$max_mem GB]${Green} OK!${NC}\n"
	fi
elif [ "$os" == "Darwin" ]; then
#http://apple.stackexchange.com/questions/4286/is-there-a-mac-os-x-terminal-version-of-the-free-command-in-linux-systems
	FREE_BLOCKS=$(vm_stat | grep free | awk '{ print $3 }' | sed 's/\.//')
	INACTIVE_BLOCKS=$(vm_stat | grep inactive | awk '{ print $3 }' | sed 's/\.//')
	SPECULATIVE_BLOCKS=$(vm_stat | grep speculative | awk '{ print $3 }' | sed 's/\.//')
	FREE=$((($FREE_BLOCKS+SPECULATIVE_BLOCKS)*4096/1048576))
	INACTIVE=$(($INACTIVE_BLOCKS*4096/1048576))
	TOTAL=$((($FREE+$INACTIVE)))
	#echo "Free: $FREE MB"
	#echo "Inactive:$INACTIVE MB"
	#echo "Total free: $TOTAL MB"
#	max_mem=`top -l 1 | head -n 10 | grep PhysMem | awk '{print $6}' | sed 's/M//g' `
	max_mem=`expr $TOTAL / 1024`
        if [ "$max_mem" -le "30" ]; then
		printf "${BrownOrange} [$max_mem GB] WARNING!${NC}\n"
		printf "${DarkGray}"
		printf "    Suggestions:\n"
		printf "    1-Remove legacy boot2docker if installed (Not needed starting docker 1.12).\n" 
                printf "    2-Recommending 32GB or more for smooth operation.\n"
                printf "    3-Some of the cluster automated builds may fail if we don't have enough memory/CPU.\n"
                printf "    4-Try limiting your builds to 15 containers.\n"
                printf "    5-Kill unused apps running on this host.\n"
		printf "    6-Restart \"exited\" containers manually.\n"
		printf "${White}    7-Change docker default settings! Docker-icon->Preferences->General->pick max CPU/MEM available${NC}\n\n" 
	else
                printf "[$max_mem GB]${Green} OK!${NC}\n"
	fi
fi
#-----------

#-----------docker daemon check
printf "${LightBlue}==>${NC} Checking if docker daemon is running..."
is_running=`docker info|grep Images`
if [ -z "$is_running" ]; then
	printf "${Red}NOT RUNNING!${NC}.\n"
	if [ "$os" == "Darwin" ]; then
                printf "MAC OSX installation: https://docs.docker.com/v1.10/mac/step_one/ \n"
	elif [ "$os" == "Linux" ]; then
                printf "Linux installation: https://docs.docker.com/engine/installation/ \n"
	fi
        exit
else
        printf "${Green} OK!${NC}\n"
fi
#-----------

#-----------image check
printf "${LightBlue}==>${NC} Checking if Splunk image is available [$SPLUNK_IMAGE]..."
image_ok=`docker images|grep $SPLUNK_IMAGE`
if [ -z "$image_ok" ]; then
	printf "${Red}NOT FOUND!${NC}\n\n"
	printf "${DarkGray}"
        printf "I will attempt to download this image. If that doesn't work you can try: \n"
	printf "  1-link: https://github.com/outcoldman/docker-splunk \n"
	printf "  2-link: https://github.com/splunk/docker-splunk/tree/master/enterprise \n"
	printf "  3-Search for Splunk images https://hub.docker.com/search/?isAutomated=0&isOfficial=0&page=1&pullCount=0&q=splunk&starCount=0\n\n"
	printf "${NC}\n"
	read -p "Pull [$SPLUNK_IMAGE] from docker hub (mayb take time)? [Y/n]? " answer
        if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		printf "${Yellow}Running [docker pull $SPLUNK_IMAGE]...${NC}\n"
		docker pull $SPLUNK_IMAGE
		printf "\n"
		printf "${Yellow}Running [docker images]...${NC}\n"
        	docker images
		printf "\n"
        else
                printf "${Red}Cannot proceed with splunk image! Exiting...${NC}\n"
                printf "See https://hub.docker.com/r/mhassan/splunk/ \n\n"
		exit
        fi
	#out="$(docker pull $SPLUNK_IMAGE 2>&1)"
	#if ( compare "$out" "error" ); then
	#	printf "Pull failed! Lets try searching for \"splunk\" image on the repository...."
	#	#printf "${Yellow}Running [docker search splunk]...${NC}\n\n"
	#	#docker search splunk
	#else	
	#	printf "${Yellow}Running [docker images]...${NC}\n\n"
	#	docker images
	#	printf "\n\n${Yellow}Please restart the script again!${NC}\n"
        #exit
	#fi
else
        printf "${Green} OK!${NC}\n"
fi
#-----------

#-----------splunk-net check
printf "${LightBlue}==>${NC} Checking if docker network is created [$SPLUNKNET]..."
net=`docker network ls | grep $SPLUNKNET `
if [ -z "$net" ]; then 
	printf "${Green} Creating...${NC}\n"
        docker network create -o --iptables=true -o --ip-masq -o --ip-forward=true $SPLUNKNET
else
       printf "${Green} OK!${NC}\n"
fi
#-----------license files/dir check
printf "${LightBlue}==>${NC} Checking if we have license files *.lic in [$PROJ_DIR/$LIC_FILES_DIR]..."
if [ ! -d $PROJ_DIR/$LIC_FILES_DIR ]; then
    		printf "${Red} DIR DOESN'T EXIST!${NC}\n"
		printf "${DarkGray}"
		printf "    Suggestions:\n"
		printf "    -Please create $PROJ_DIR/$LIC_FILES_DIR and place all *.lic files there.\n"
		printf "    -Change the location of LICENSE dir in the config section of the script.${NC}\n\n"
elif  ls $PROJ_DIR/$LIC_FILES_DIR/*.lic 1> /dev/null 2>&1 ; then 
       		printf "${Green} OK!${NC}\n"
	else
        	printf "${Red}NO LIC FILE(S) FOUND!${NC}\n"
		printf "${DarkGray}"
		printf "    Suggestions:\n"
		printf "    -If *.lic exist, make sure they are readable.${NC}\n\n"
fi
#-----------local splunkd check
#Little tricky, local splunkd process running on docker-host is different than splunkd inside a container!
printf "${LightBlue}==>${NC} Checking if non-docker splunkd process is running [$LOCAL_SPLUNKD]..."
PID=`ps aux | $GREP 'splunkd' | $GREP 'start' | head -1 | awk '{print $2}' `  	#works on OSX & Linux
if [ "$os" == "Darwin" ] && [ -n "$PID" ]; then
	splunk_is_running="$PID"
elif [ "$os" == "Linux" ] && [ -n "$PID" ]; then
	splunk_is_running=`cat /proc/$PID/cgroup|head -n 1|grep -v docker`	#works on Linux only
fi
#echo "PID[$PID]"
#echo "splunk_is_running[$splunk_is_running]"
if [ -n "$splunk_is_running" ]; then
	printf "${Red}Running [$PID]${NC}\n"
	read -p "Kill it? [Y/n]? " answer
       	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		sudo $LOCAL_SPLUNKD stop
	else
		printf "${Red}WARNING! Running local splunkd may prevent containers from binding to interfaces!${NC}\n\n"	
	fi
else
	printf "${Green} OK!${NC}\n"
fi
#-----------

#TO DO:
#check dnsmasq
#check $USER
#Your Mac must be running OS X 10.8 “Mountain Lion” or newer to run Docker software.
#https://docs.docker.com/engine/installation/mac/

return 0
}     #end validation_check()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
detect_os () {	
#Set global vars based on OS type:
# ETH to use
# GREP command. Must install ggrep utility on OSX 
# MOUNTPOINT   (OSX is strict about permissions)

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

uname=`uname -a | awk '{print $1}'`	
if [ "$(uname)" == "Darwin" ]; then
    	os="Darwin"
	START_ALIAS=$START_ALIAS_OSX
	END_ALIAS=$END_ALIAS_OSX
	ETH=$ETH_OSX
	GREP=$GREP_OSX		#for Darwin http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html
	MOUNTPOINT="/Users/${USER}/$VOL_DIR"
	PROJ_DIR="/Users/${USER}"  #anything that needs to copied to container
	sys_ver=`system_profiler SPSoftwareDataType|grep "System Version" |awk '{print $5}'`
	kern_ver=`system_profiler SPSoftwareDataType|grep "Kernel Version" |awk '{print $3,$4}'`
	printf "${LightBlue}==> ${White}Detected MAC OSX...[System:$sys_ver Kernel:$kern_ver]${NC}\n"
	validation_check

elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    	os="Linux"
	START_ALIAS=$START_ALIAS_LINUX
        END_ALIAS=$END_ALIAS_LINUX
	GREP=$GREP_LINUX
	ETH=$ETH_LINUX
	MOUNTPOINT="/home/${USER}/$VOL_DIR"
	PROJ_DIR="/home/${USER}/"
	release=`lsb_release -r |awk '{print $2}'`
	kern_ver=`uname -r`
	printf "${LightBlue}==> ${White}Detected LINUX...[Release:$release Kernel:$kern_ver]${NC}\n"
	validation_check

elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    	os="Windows"
fi
return 0
}	#end detect_os ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
compare () {
# String comparison routine.
# usage:   compare(string, sub-string)
# Returns 0 if the specified string compare the specified sub-string,otherwise return 1

string=$1 ; substring=$2

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

    if test "${string#*$substring}" != "$string"
    then
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} strings matching${NC}\n"  >&5
        return 0    # $substring is in $string
    else
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} strings NOT matching!${NC}\n"  >&5
        return 1    # $substring is not in $string
    fi
return 0
} #end compare()
#---------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------
add_license_file () {
#This function will just copy the license file. Later on if the container get configured
#as a license-slave; then this file become irrelevant
# $1=fullhostname
#Little tricky see: https://docs.docker.com/engine/reference/commandline/cp/

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

CMD="docker cp $PROJ_DIR/$LIC_FILES_DIR  $1:/opt/splunk/etc/licenses/enterprise"; OUT=`$CMD`
printf "\t->Copying license file(s). Will override if later became license-slave " >&3 ; display_output "$OUT" "" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$1"

if ( compare "$1" "LM" ); then
	printf "\t->*LM* host! Forcing immidiate splunkd restart.Please wait " >&3
	docker exec -ti $1  /opt/splunk/bin/splunk restart > /dev/null >&1
	printf "${Green} Done! ${NC}\n" >&3
fi
return 0
} #end add_license_file()
#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------
reset_splunk_passwd () {
# $1=fullhostname

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

docker exec -ti $1 touch /opt/splunk/etc/.ui_login	#prevent first time changeme password screen
docker exec -ti $1 rm -fr /opt/splunk/etc/passwd	#remove any existing users (include admin)

#reset password to "$USERADMIN:$USERPASS"
CMD="docker exec -ti $1 /opt/splunk/bin/splunk edit user admin -password hello -roles admin -auth admin:changeme"
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
logline "$CMD" "$1"
printf "${Purple}$1${NC}: > $CMD\n"

if ( compare "$CMD" "failed" ); then
   echo "\t->Trying default password "
   CMD="docker exec -ti $1 /opt/splunk/bin/splunk edit user admin -password changeme -roles admin -auth $USERADMIN:$USERPASS"
   printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
   logline "$CMD" "$1"
   printf "${Purple}$1${NC}: $OUT\n"
fi
return 0
}  #end reset_splunk_passwd()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
pausing () {
#$1=seconds

for c in $(seq 1 $1); do  
	echo -ne "${LightGray}\t->Pausing $1 seconds... ${Yellow}$c\r"  >&3
	sleep 1
done
printf "${LightGray}\t->Pausing $1 seconds... ${Green}Done!${NC}\n"  >&3

return 0
} #end pausing()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
restart_splunkd () {
#1: hostname 
#$2=b Execute in the background and don't wait to return.This will speed up everything but load the CPU

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

if [ "$2" == "b" ]; then
	printf "\t->Restarting splunkd in the ${White}background${NC} " >&3
        CMD="docker exec -d $1 /opt/splunk/bin/splunk restart "
        OUT=`$CMD`; display_output "$OUT" "The Splunk web interface is at" "3"
   	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$1"
else
	printf "\t->Restarting splunkd. Please wait! " >&3
	CMD="docker exec -ti $1 /opt/splunk/bin/splunk restart "
        OUT=`$CMD`; display_output "$OUT" "The Splunk web interface is at" "3"
   	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$1"
fi

return 0
} #end restart_splunkd()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_output () {
#This function displays the output from CMD (docker command executed)
#$1  Actual message after executing docker command
#$2  The expected "good" message returned if docker command executed OK. Otherwise everything would be an error
#$3  The loglevel (I/O redirect) to display the message (good for verbosity settings)

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

outputmsg=$1; OKmsg=$2; loglevel=$3
OKmsg=`echo $OKmsg| tr '[a-z]' '[A-Z]'`				#convert to upper case 
outputmsg=`echo -n $outputmsg| tr '[a-z]' '[A-Z]' |sed -e 's/^M//g' | tr -d '\r' ` #cleanup & convert to upper case 
size=${#outputmsg}

#also display returned msg if log level is high
#printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} vars outputmsg:[$outputmsg] OKmsg:[$OKmsg]${NC}\n"  >&5
#echo "result[$1]"
        if ( compare "$outputmsg" "$OKmsg" ) || [ "$size" == 64 ] || [ "$size" == 0 ] ; then
                printf "${Green} OK! ${NC}\n"  >&$loglevel
        else
               # printf "\n${DarkGray}[%s] ${NC}" "$1"
                printf "${Red}[%s] ${NC}\n" "$1" >&$loglevel
                #restart_splunkd "$host"
        fi
return 0
}  #end display_output()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
host_status () {     ####### NOT USED YET ########
#$1=hostname
#restart host and splunkd is not running

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

hoststate=`docker ps -a --filter name=$1 --format "{{.Status}}" | awk '{print $1}'`
splunkstate=`docker exec -ti $1 /opt/splunk/bin/splunk status| $GREP splunkd| awk '{ print $3}'`
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} host:[$1] hoststate:[$hoststate] splunkstate:[$splunkstate] ${NC}\n" &>5

if [ "$hoststate" == "" ];  then
        printf "${Purple}[$1]${NC}: ${Purple} Host state: Container does not exist!${NC} \n"
        return 1
elif [ "$hoststate" != "Up" ];  then
        printf "${Purple}[$1]${NC} ${Purple} Host state: Container is not running. Restarting${NC} \n"
        docker start $1
        sleep 10
elif [ "$splunkstate" != "running" ]; then
        printf "${Purple}[$1]${NC}${Purple} Host state: Splunkd is not running. Restarting${NC}!\n"
        restart_splunkd "$1"
fi
return 0
}   #end host_status()
#---------------------------------------------------------------------------------------------------------------
display_debug () {

func_name=$1; arg_num=$2; param_list=$3; calls=$4
calls_count=`echo $calls|wc -w|sed 's/ //g'`
calls=`echo $calls| sed 's/ / <- /g'`;
printf "\n${LightRed}DEBUG:=> CALLS($calls_count) =>${Yellow}[$calls]${NC}\n"  >&6
printf "${LightRed}DEBUG:=> STARTED  =>${Yellow}$func_name(): ${Purple}args:[$arg_num] ${Yellow}(${LightGreen}$param_list${Yellow})${NC}\n" >&6

return 0
}
#---------------------------------------------------------------------------------------------------------------
make_lic_slave () {
# This function designate $hostname as license-slave using LM (License Manager)
#Always check if $lm exist before processing

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

lm=$1; hostname=$2; 
if [ -n "$lm" ]; then
	#echo "hostname[$hostname]  lm[$lm] _____________";exit
	lm_ip=`docker port  $lm| awk '{print $3}'| cut -d":" -f1|head -1`
  	if [ -n "$lm_ip" ]; then
        	CMD="docker exec -ti $hostname /opt/splunk/bin/splunk edit licenser-localslave -master_uri https://$lm_ip:$MGMT_PORT -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
        	printf "\t->Making [$hostname] license-slave using LM:[$lm] " >&3 ; display_output "$OUT" "has been edited" "3"
		printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4 
		logline "$CMD" "$hostname"
        	fi
fi

return 0
} 	#end make_lic_slave()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_host_exist () {		 ####### NOT USED YET ########
#$1=hostname (may include digits sequence)   $2=list_to_check_against
#Check if host exist in list; if not create it using basename only . The new host seq is returned by function

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

printf "${Purple}[$1] Host check >>> "
basename=$(printf '%s' "$1" | tr -d '0123456789')  #strip numbers
if [ -z "$2" ]; then
        printf "${LightPurple}Group is empty >>> creating host ${NC}\n";
        create_generic_splunk $basename 1
else if ( compare "$2" "$1" ); then
                printf "${Purple}Found in group. No action. ${NC}\n";
                return 0
        else
                printf "${LightPurple}Not found in group >>> Using basename to create next in sequence ${NC}\n";
                create_generic_splunk $basename 1
                num=`echo $?`    #last host seq number created
                return $num
        fi
fi
return 0
}  #end check_host_exist ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
show_all_containers () {
#This function displays containers groups by role (role is determined using hostname ex: SH, DS, IDX, CM,...etc)
display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

count=`docker ps -aq|wc -l`
if [ $count == 0 ]; then
	echo "No containers to list"
	return 0
fi
i=0
for id in $(docker ps -aq); do
    let i++
    internal_ip=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $id`
    bind_ip=`docker inspect --format '{{ .HostConfig }}' $id| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
    hoststate=`docker ps -a --filter id=$id --format "{{.Status}}" | awk '{print $1}'`
    hostname=`docker ps -a --filter id=$id --format "{{.Names}}"`
    host_line[$i]="$bind_ip"
    if [ $hoststate == "Up" ]; then
    	splunkstate=`docker exec -ti $id /opt/splunk/bin/splunk status| $GREP splunkd| awk '{ print $3}'`
    else
	splunkstate=""	
    fi	
    case "$hoststate" in
	Up)      hoststate="${Green}$hoststate ${NC}" ;;
	Created) hoststate="${DarkGray}$hoststate ${NC}" ;;
	Exited)  hoststate="${Red}$hoststate ${NC}" ;;
    esac
    if ( compare "$splunkstate" "running" ); then
		splunkstate="${Green}$splunkstate${NC}"
    else
		splunkstate="${Red}$splunkstate${NC}"
    fi
    if ( compare "$hostname" "DEP" ); then
    	printf "${LightBlue}$i) %-15s%-20b${NC} Splunkd:%-20b Bind:${LightBlue}%-10s${NC} Internal:${DarkGray}%-10s${NC}\n" "[$hostname]:" "$hoststate" "$splunkstate" "$bind_ip" "$internal_ip"
    elif ( compare "$hostname" "CM" ); then
    	printf "${LightBlue}$i) %-15s%-20b${NC} Splunkd:%-20b Bind:${LightBlue}%-10s${NC} Internal:${DarkGray}%-10s${NC}\n" "[$hostname]:" "$hoststate" "$splunkstate" "$bind_ip" "$internal_ip"
   else
    	printf "${Purple}$i) %-15s%-20b${NC} Splunkd:%-20b Bind:${LightGray}%-10s${NC} Internal:${DarkGray}%-10s${NC}\n" "[$hostname]:" "$hoststate" "$splunkstate" "$bind_ip" "$internal_ip"
   fi
done

echo  "count:$count"
echo
#only for the Mac
if [ "$os" == "Darwin" ]; then
	read -p 'Selet a host to launch in your default browser? '  choice
	if [ -z "$choice" ]; then
		continue
	elif [ "$choice" -le "$i" ] && [ "$choice" -ne "0" ] ; then
			open http://${host_line[$i]}:8000
		else
			printf "Invalid choice! Valid options [1..$i]\n"
	fi
fi
return 0
}  #end  show_all_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
splunkd_status_all () {
#This functions displays splunkd status on all containers

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
for i in `docker ps --format "{{.Names}}"`; do
        printf "${Purple}$i${NC}: "
        docker exec -ti $i /opt/splunk/bin/splunk status| $GREP splunkd| awk '{ \
        if($3=="not")           {$3="\033[31m" $3 "\033[0m" }  \
        if($3=="running")       {$3="\033[32m" $3 "\033[0m" } ; \
        print $1,$2,$3,$4,$5 }'
done
return 0
}	#end splunkd_status_all()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
show_groups () {
#This functions shows all containers grouped by role (using base hostname)
#captain=`docker exec -ti $i /opt/splunk/bin/splunk show shcluster-status|head -10 | $GREP -i label |awk '{print $3}'| sed -e 's/^M//g' | tr -d '\r' | tr  '\n' ' '`

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

idx_list=`docker ps -a --filter name="IDX|idx" --format "{{.Names}}"|sort `
sh_list=`docker ps -a --filter name="SH|sh" --format "{{.Names}}"|sort`
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort`
lm_list=`docker ps -a --filter name="LM|lm" --format "{{.Names}}"|sort`
dep_list=`docker ps -a --filter name="DEP|dep" --format "{{.Names}}"|sort`
ds_list=`docker ps -a --filter name="DS|ds" --format "{{.Names}}"|sort`
hf_list=`docker ps -a --filter name="HF|hf" --format "{{.Names}}"|sort`
uf_list=`docker ps -a --filter name="UF|uf" --format "{{.Names}}"|sort`

echo "------------ Servers grouped by hostname (i.e. role) ---------------"
printf "${Purple}LMs${NC}: " ;      printf "%-5s " $lm_list;echo
printf "${Purple}CMs${NC}: " ;      printf "%-5s " $cm_list;echo
printf "${Yellow}IDXs${NC}: ";      printf "%-5s " $idx_list;echo
printf "${Green}SHs${NC}: ";        printf "%-5s " $sh_list;echo
printf "${Cyan}DSs${NC}: ";         printf "%-5s " $ds_list;echo
printf "${OrangeBrown}DEPs${NC}: "; printf "%-5s " $dep_list;echo
printf "${Blue}HFs${NC}: ";         printf "%-5s " $hf_list;echo
printf "${LightBlue}UFs${NC}: ";    printf "%-5s " $uf_list;echo
echo

echo "---------- Current running IDXC's -------"
for i in $cm_list; do
	printf "${Yellow}$i${NC}: "	
	docker exec -ti $i /opt/splunk/bin/splunk show cluster-status -auth $USERADMIN:$USERPASS \
	| $GREP -i IDX | awk '{print $1}' | paste -sd ' ' -
done
echo

echo "---------- Current running SHC's -------"
prev_list=''
for i in $sh_list; do
	sh_cluster=`docker exec -ti $i /opt/splunk/bin/splunk show shcluster-status -auth $USERADMIN:$USERPASS | $GREP -i label |awk '{print $3}'| sed -e 's/^M//g' | tr -d '\r' | tr  '\n' ' ' `
	if ( compare "$sh_cluster" "$prev_list" );  then
		continue
	else
        	printf "${Yellow}$i${NC}: %s" "$sh_cluster"
		prev_list=$sh_cluster
	fi
	echo
done
echo
return 0
}  #end show_groups()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
custom_login_screen () {
#This function creates custom login screen with some useful data (hostnam, IP, cluster label)

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
vip=$1;  fullhostname=$2

#reset password to "$USERADMIN:$USERPASS"
CMD="docker exec -ti $fullhostname touch /opt/splunk/etc/.ui_login"      #prevent first time changeme password screen
OUT=`$CMD`;   #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
logline "$CMD" "$fullhostname"
CMD="docker exec -ti $fullhostname rm -fr /opt/splunk/etc/passwd"        #remove any existing users (include admin)
OUT=`$CMD`;   #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
logline "$CMD" "$fullhostname"
CMD="docker exec -ti $fullhostname /opt/splunk/bin/splunk edit user admin -password $USERPASS -roles $USERADMIN -auth admin:changeme"
OUT=`$CMD`;   display_output "$OUT" "user admin edited" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$fullhostname"

if ( compare "$CMD" "failed" ); then
        echo "Trying default password"
   #     docker exec -ti $fullhostname rm -fr /opt/splunk/etc/passwd        #remove any existing users (include admin)
        CMD="docker exec -ti $fullhostname touch /opt/splunk/etc/.ui_login"      #prevent first time changeme password screen
	OUT=`$CMD` ; display_output "$OUT" "user admin edited" "5"
	#printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$fullhostname"

        CMD="/opt/splunk/bin/splunk edit user $USERADMIN -password changeme -roles admin -auth $USERADMIN:$USERPASS"
	OUT=`$CMD` ; #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
	logline "$CMD" "$fullhostname"
	display_output "$OUT" "user admin edited" "5"
	#printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
	logline "$CMD" "$fullhostname"
fi

#set home screen banner in web.conf
hosttxt=`echo $fullhostname| $GREP -Po '\d+(?!.*\d)'  `        #extract string portion
hostnum=`echo $fullhostname| $GREP -Po '\d+(?!.*\d)'  `        #extract digits portion

container_ip=`docker inspect $fullhostname| $GREP IPAddress |$GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1  ` 
#cluster_label=`docker exec -ti $fullhostname $GREP cluster_label /opt/splunk/etc/system/local/server.conf | awk '{print $3}' `
#cluster_label=`cat $PROJ_DIR/web.conf.tmp | $GREP -Po 'cluster.* (.*_LABEL)'| cut -d">" -f3`
if [ -z "$cluster_label" ]; then
        cluster_label="--"
fi
#LINE1="<font color=\"#867979\">name:    </font><font color=\"#FF9033\"> $hosttxt</font><font color=\"#FFB833\">$hostnum</font>"
LINE1="<font color=\"#867979\">name:    </font><font color=\"#FF9033\"> $fullhostname</font>"
LINE2="<font color=\"#867979\">cluster: </font><font color=\"#FF9033\"> $cluster_label</font>"
LINE3="<font color=\"#867979\">IP:      </font><font color=\"#FF9033\"> $vip</font>"

LINE4="<font color=\"#867979\">User: </font> <font color=\"red\">$USERADMIN</font> &nbsp&nbsp<font color=\"#867979\">Password:</font> <font color=\"red\"> $USERPASS</font></H3><H2></font>"
LINE5="<font color=\"green\">SPLUNK LAB (docker infrastructure )</font>"

custom_web_conf="[settings]\nlogin_content =<div align=\"right\" style=\"border:1px solid green\"><CENTER><H1> $LINE1 <BR> $LINE2<BR> $LINE3 </H1><H3> $LINE4 <BR><BR> $LINE5 </H2></CENTER> </div> <p>This data is auto-generated at reboot time  (container internal IP=$container_ip)  .</p>\n"

printf "$custom_web_conf" > $PROJ_DIR/web.conf
CMD=`docker cp $PROJ_DIR/web.conf $fullhostname:/opt/splunk/etc/system/local/web.conf`

#restarting splunkweb may not work with 6.5+
CMD=`docker exec -ti $fullhostname /opt/splunk/bin/splunk restart splunkweb -auth $USERADMIN:$USERPASS`

printf "\t->Customizing web.conf!${Green} Done!${NC}\n" >&4

return 0
}  #end custom_login_screen ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
assign_server_role () {		 ####### NOT USED YET ########

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#EXAMPLE:
#mhassan:~> docker exec -ti SITE01-DMC01 cat /opt/splunk/etc/apps/splunk_management_console/lookups/assets.csv
#peerURI,serverName,host,machine,"search_group","_mkv_child","_timediff","__mv_peerURI","__mv_serverName","__mv_host","__mv_machine","__mv_search_group","__mv__mkv_child","__mv__timediff"
#"10.0.0.101:8089","SITE01-LM01","SITE01-LM01","SITE01-LM01","dmc_group_license_master",0,,,,,,,,
#"10.0.0.102:8089","SITE01-CM01","SITE01-CM01","SITE01-CM01","dmc_group_cluster_master",0,,,,,,,,
#"10.0.0.102:8089","SITE01-CM01","SITE01-CM01","SITE01-CM01","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.107:8089","SITE01-DEP01","SITE01-DEP01","SITE01-DEP01","dmc_group_deployment_server",0,,,,,,,,
#"10.0.0.108:8089","SITE01-SH01","SITE01-SH01","SITE01-SH01","dmc_group_search_head",0,,,,,,,,
#"10.0.0.108:8089","SITE01-SH01","SITE01-SH01","SITE01-SH01","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.108:8089","SITE01-SH01","SITE01-SH01","SITE01-SH01","dmc_searchheadclustergroup_LABEL1",2,,,,,,,,
#"10.0.0.109:8089","SITE01-SH02","SITE01-SH02","SITE01-SH02","dmc_group_search_head",0,,,,,,,,
#"10.0.0.109:8089","SITE01-SH02","SITE01-SH02","SITE01-SH02","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.109:8089","SITE01-SH02","SITE01-SH02","SITE01-SH02","dmc_searchheadclustergroup_LABEL1",2,,,,,,,,
#"10.0.0.110:8089","SITE01-SH03","SITE01-SH03","SITE01-SH03","dmc_group_search_head",0,,,,,,,,
#"10.0.0.110:8089","SITE01-SH03","SITE01-SH03","SITE01-SH03","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.110:8089","SITE01-SH03","SITE01-SH03","SITE01-SH03","dmc_searchheadclustergroup_LABEL1",2,,,,,,,,
#localhost,"SITE01-DMC01","SITE01-DMC01","SITE01-DMC01","dmc_group_search_head",0,,,,,,,,

#docker exec -ti SITE01-DEP01 cat /opt/splunk/etc/apps/splunk_management_console/lookups/assets.csv
#peerURI,serverName,host,machine,"search_group","__mv_peerURI","__mv_serverName","__mv_host","__mv_machine","__mv_search_group"
#localhost,"SITE01-DEP01","SITE01-DEP01","SITE01-DEP01","dmc_group_license_master",,,,,
#localhost,"SITE01-DEP01","SITE01-DEP01","SITE01-DEP01","dmc_group_search_head",,,,,

name=$1; role=$2
echo peerURI,serverName,host,machine,"search_group","_mkv_child","_timediff","__mv_peerURI","__mv_serverName","__mv_host","__mv_machine","__mv_search_group","__mv__mkv_child","__mv__timediff" > assets.csv.tmp	
echo "localhost,"$name","$name","$name","$role,,,,,"" > assets.csv.tmp

# $MOUNTPOINT/$name/etc/apps/splunk_management_console/lookups/assets.csv
#Roles:
#dmc_group_indexer
#dmc_group_license_master
#dmc_group_search_head
#dmc_group_kv_store
#dmc_group_license_master
return 0
}
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
make_dmc_search_peer () {
#Always check if $dmc exist before processing

dmc=$1; host=$2
#adding search peer in DMC
if [ -n "$dmc" ]; then
	bind_ip_host=`docker inspect --format '{{ .HostConfig }}' $host| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	CMD="docker exec -ti $dmc /opt/splunk/bin/splunk add search-server -host $bind_ip_host:8089 -auth $USERADMIN:$USERPASS -remoteUsername $USERADMIN -remotePassword $USERPASS"
        OUT=`$CMD`
        OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
        printf "\t->Adding [$host] to DMC:[$dmc] " >&3 ; display_output "$OUT" "Peer added" "3"
        printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$dmc"
fi
        
return 0
} 	#make_dmc_search_peer()
#---------------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------
create_splunk_container () {
#This function creates single splunk container using $vip and $hostname
#inputs: $1: container's IP to use (nated IP aka as bind IP)
#	 $2: fullhostname:  container name (may include site and host number sequence)
#	 $3: lic_master
#	 $4: cluster_label
#
#output: -create single host. will not prompt user for any input data
#	 -reset password and setup splunk's login screen
#        -configure container's OS related items if needed

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
START1=$(date +%s);
	vip=$1;  fullhostname=$2;lic_master=$3; cluster_label=$4; 
	fullhostname=`echo $fullhostname| tr -d '[[:space:]]'`	#trim white space if they exist

	check_load		#throttle back if high load

	#echo "fullhostname[$fullhostname]"
	#rm -fr $MOUNTPOINT/$fullhostname
	mkdir -m 777 -p $MOUNTPOINT/$fullhostname
        
	CMD="docker run -d --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER  -p $vip:$SPLUNKWEB_PORT:$SPLUNKWEB_PORT -p $vip:$MGMT_PORT:$MGMT_PORT -p $vip:$SSHD_PORT:$SSHD_PORT -p $vip:$RECV_PORT:$RECV_PORT -p $vip:$REPL_PORT:$REPL_PORT -p $vip:$APP_SERVER_PORT:$APP_SERVER_PORT -p $vip:$APP_KEY_VALUE_PORT:$APP_KEY_VALUE_PORT --env SPLUNK_START_ARGS="--accept-license" --env SPLUNK_ENABLE_LISTEN=$RECV_PORT --env SPLUNK_SERVER_NAME=$fullhostname --env SPLUNK_SERVER_IP=$vip $SPLUNK_IMAGE"
        
	printf "[${LightGreen}$fullhostname${NC}:${Green}$vip${NC}] ${LightBlue}Creating new splunk docker container ${NC} " 
	OUT=`$CMD` ; display_output "$OUT" "" "2"
	#CMD=`echo $CMD | sed 's/\t//g' `; 
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$fullhostname"
	
	if [ "$os" == "Darwin" ]; then
		pausing "30"
	else
		pausing "15"
	fi

	#check if bind IP is used by new container (indications its running)
	ip=`docker port $fullhostname| awk '{print $3}'| cut -d":" -f1|head -1`
	printf "\t->Verifying that container is running..." >&3
	if [ -n "$ip" ]; then 
		printf "${Green}OK!${NC}\n" >&3
	else
		printf "\t->{Red}Not runing. Attempting to restart [$fullhostname]!${NC}\n" >&3
		CMD='docker start $fullhostname'; OUT=`CMD`
		printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$fullhostname"
	fi

        #set home screen banner in web.conf & change default admin password
	printf "\t->Splunk initialization (pass change, licenses, login screen)..." >&3
	custom_login_screen "$vip" "$fullhostname"

	add_license_file $fullhostname

	#Misc OS stuff
	if [ -f "$PROJ_DIR/containers.bashrc" ]; then
        	CMD=`docker cp $PROJ_DIR/containers.bashrc $fullhostname:/root/.bashrc`
	fi
        #install stuff you will need in  background
        #CMD=`docker exec -it $fullhostname apt-get update > /dev/null >&1`
        #CMD=`docker exec -it $fullhostname apt-get install -y vim net-tools telnet dnsutils > /dev/null >&1`

#DNS stuff to be used with dnsmasq. Need to revisit for OSX  9/29/16
#Enable for Linux at this point
if [ "$os" == "Linux" ]; then
	printf "\t->Updating dnsmasq records[$vip  $fullhostname]..." >&3
	if [ ! -f $HOSTSFILE ]; then
		touch $HOSTSFILE
	fi
	if [ $(cat $HOSTSFILE | $GREP $fullhostname | wc -l | sed 's/^ *//g') != 0 ]; then
        	printf "\t${Red}[$fullhostname] is already in the hosts file. Removing...${NC}\n" >&4
        	cat $HOSTSFILE | $GREP -v $vip | sort > tmp && mv tmp $HOSTSFILE
	fi
	printf "${Green}OK!${NC}\n" >&3
	printf "$vip\t$fullhostname\n" >> $HOSTSFILE
	sudo killall -HUP dnsmasq	#must refresh to read $HOSTFILE file
fi

return 0

}  #end create_splunk_container ()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
create_generic_splunk () {
#This function creates generic splunk containers. Role is assigned later
#inputs: $1:basehostname: (ex IDX, SH,HF) just the base (no numbers)
#	 $2:hostcount:     how many containers to create from this host type (ie name)
#	 $3:lic_master		if provided dont copy license, make host license-slave	
# 	 $4:cluster_label	cluster label in web.conf, use if provided
#outputs: $gLIST:  global var compare the list of hostname just got created
#	  $host_num :  last host number sequence just got created
#	-calculate host number sequence
#	 -calculate next IP sequence (octet4)

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

basename=$1; hostcount=$2; lic_master=$3; cluster_label=$4
count=0;starting=0; ending=0;basename=$BASEHOSTNAME;  octet4=0
gLIST=""   #build global list of hosts created by this session. Used somewhere else

#Another method to figure out the starting octet4 
# OCTET4FILE=`iptables -t nat -L |$GREP DNAT | awk '{print $5}'  | sort -u|tail -1|cut -d"." -f4`
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}  basename[$basename]  hostcount[$hostcount] ${NC}\n" >&5

#---Prompt user for host basename (if not in auto mode) -----
if [ -z "$1" ]; then
        read -p ">>>> Enter BASE HOSTNAME (default: $BASEHOSTNAME)?: " basename
else
        basename=$1
fi
if [ -z "$basename" ]; then
        basename=$BASEHOSTNAME
        last_host_name=""
        #printf "First time to use this host_base_name ${Green}[$basename]${NC}\n"
fi
#always convert to upper case before creating
basename=`echo $basename| tr '[a-z]' '[A-Z]'`	

#---Prompt user for host count (if not in auto mode) -----
if [ -z "$2" ]; then
        read -p ">>>> How many hosts to create (default 1)? " count
else
        count=$2
fi
if [ -z "$count" ]; then count=1;  fi
#----------------------------------------

#---- calculate count range -----------
last_host_num=`docker ps -a --format "{{.Names}}"|$GREP "^$basename"|head -1| $GREP -P '\d+(?!.*\d)' -o`;  #last digit from last created
if [ -z "$last_host_num" ]; then    					#no previous hosts with this name exists
        printf "${DarkGray}[$basename] New basename. ${NC}" >&4
	starting=1
        ending=$count
	last_host_num=0
else
       	starting=`expr $last_host_num + 1`
       	ending=`expr $starting + $count - 1`
       	printf "${DarkGray}Last hostname created:${NC}[${Green}$basename${NC}${Yellow}$last_host_num${NC}] " >&4
fi
#fix single digit issue if < 2-digits
if [ "$starting" -lt "10" ]; then
                startx="0"$starting
        else
                startx=$starting
        fi
        if [ "$ending" -lt "10" ]; then
                endx="0"$ending
        else
                endx=$ending
        fi
printf "${DarkGray}Next sequence:${NC} [${Green}$basename${Yellow}$startx${NC} --> ${Green}$basename${Yellow}$endx${NC}]\n"  >&4

#--generate fullhostname (w/ seq numbers) and VIP------------------------

#--------Find last IP used. This is not hostname or site dependent-------
base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `;  #base_ip=$base_ip"."

#get last octet4 used ----
if [ $(docker ps -aq | wc -l) = 0 ]; then
        last_used_octet4=`echo $START_ALIAS | cut -d"." -f4 `
        last_ip_used="$base_ip.$start_octet4"
        printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} No hosts exists [will start@$last_ip_used][last_octet4:$last_used_octet4]\n" >&5

else    #Find last container created IP
        last_ip_used=`docker inspect --format '{{ .HostConfig }}' $(docker ps -aql)|$GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
        last_used_octet4=`echo $last_ip_used |cut -d"." -f4`
        printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}Some hosts exists [last used:$last_ip_used][last_octet4:$last_used_octet4]\n" >&5
fi
#-------------------------------------------------------------------------

octet4=$last_used_octet4
#Loop to create $count total hosts ----
for (( x=${starting}; x <= ${ending}; x++)) 
do
	#fix the digits size first
     	if [ "$x" -lt "10" ]; then
      		host_num="0"$x         		 #always reformat number to 2-digits if less than 2-digits
     	else
                host_num=$x             	#do nothing
     	fi
     	fullhostname="$basename"$host_num  	#create full hostname (base + 2-digits)

     	# VIP processing
     	octet4=`expr $octet4 + 1`       	#increment octet4
     	vip="$base_ip.$octet4"            	#build new IP to be assigned
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}fulhostname:[$fullhostname] vip:[$vip] basename:[$basename] count[$count] ${NC}\n" >&5
	
	create_splunk_container $vip $fullhostname $lic_master $cluster_label
	gLIST="$gLIST""$fullhostname "

done  #end for loop
	gLIST=`echo $gLIST |sed 's/;$//'`	#remove last space (causing host to look like "SH "
#--------------------------

return $host_num
}  #end of create_generic_splunk ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_single_shc () {
#This function creates single Search Head Cluster. Details is passed using $1
#inputs: $1: pass all components (any order) needed and how many to create. The names the counts will be extracted
#example : create_single_shc "$site-SH:$SHcount $cm:1 $lm:1"
#outputs: -adjust hostname with sitename if used
#	  -always convert hostnames to upper case (to avoid lookup/compare issues)
#	  -create single deployer and as many SH hosts required
#	  -if param $1 is "AUTO" skip all user prompts and create standard cluster 3SH/1DEP
#-----------------------------------------------------------------------------------------------------
#$1 AUTO or MANUAL mode
display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

if [ "$1" == "AUTO" ]; then  mode="AUTO"; else mode="MANUAL"; fi

server_list=""    #used by STEP#3
START1=$(date +%s);

#Extract parms from $1, if not we will prompt user later
lm=`echo $1| $GREP -Po '(\s*\w*-*LM\d+)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
cm=`echo $1| $GREP -Po '(\s*\w*-*CM\d+)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
label=`echo $1| $GREP -Po '(\s*\w*-*LABEL):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
DEPname=`echo $1| $GREP -Po '(\s*\w*-*DEP)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
DEPcount=`echo $1| $GREP -Po '(\s*\w*-*DEP):\K(\d+)'| tr -d '[[:space:]]' `
SHname=`echo $1| $GREP -Po '(\s*\w*-*SH)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' ` 
SHcount=`echo $1| $GREP -Po '(\s*\w*-*SH):\K(\d+)'| tr -d '[[:space:]]' `

#generate all global lists
dep_list=`docker ps -a --filter name="$DEPname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
sh_list=`docker ps -a --filter name="$SHname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
lm_list=`docker ps -a --filter name="LM|lm" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'` 
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'` 

if [ "$mode" == "AUTO" ]; then
        #DEPname="DEP"; DEPcount="1"; SHname="SH"; SHcount="$STD_SHC_COUNT"; 
	label="$SHCLUSTERLABEL"
	printf "\n${Yellow}[$mode]>>BUILDING SEARCH HEAD CLUSTER!${NC}\n\n"
	printf "${Yellow}==>Starting PHASE1: Creating generic SH hosts${NC}\n"
	printf "${DarkGray}Using DMC:[$DMC_BASE] LM:[$LM_BASE] CM:[$CM_BASE] LABEL:[$label] DEP:[$DEP_BASE:($DEP_SHC_COUNT)] SHC:[$SH_BASE:($STD_SHC_COUNT)]${NC}\n"
	printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"

	#Basic services. Sequence is very important!
        create_generic_splunk "$DMC_BASE" "1" ; dmc=$gLIST
        create_generic_splunk "$LM_BASE" "1" ; lm=$gLIST
        make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
        create_generic_splunk "$DEP_BASE" "$DEP_SHC_COUNT" ; dep="$gLIST"
        make_lic_slave $lm $dep ; make_dmc_search_peer $dmc $dep

	#The rest of SHs
        create_generic_splunk "$SH_BASE" "$STD_SHC_COUNT" ; members_list="$gLIST"
else
	#Error checking (values should already have been passed at this point)
	if [ -z "$label" ]; then
                read -p "Need to know SH cluster label ($SHCLUSTERLABEL)> " label ;
                label=`echo $label| tr '[a-z]' '[A-Z]'`; if [ -z "$label" ]; then label="$SHCLUSTERLABEL"; fi
        fi
        if [ -z "$DEPname" ] || [ -z "$DEPcount" ]; then 
		read -p "Need to know DEP basename (default $DEP_BASE)> " DEPname ;
        	DEPname=`echo $DEPname| tr '[a-z]' '[A-Z]'` ; if [ -z "$DEPname" ]; then DEPname="$DEP_BASE"; fi
	fi
        if [ -z "$SHname" ] || [ -z "$SHcount" ]; then 
		read -p "Need to know SH basename (default $SH_BASE)> " SHname ;
        	SHname=`echo $SHname| tr '[a-z]' '[A-Z]'` 
                if [ -z "$SHname" ]; then SHname="$SH_BASE"; fi
		read -p "Need to know how many SH's to create (default $STD_SHC_COUNT)>  " SHcount
                if [ -z "$SHcount" ]; then SHcount="$STD_SHC_COUNT"; fi
	fi
	if [ -z "$lm" ]; then
		printf "Current list of LMs: [$lm_list]\n"
		read -p "Choose LM from existing list or hit <ENTER> to create new one (default $LM_BASE)? " lm 
		lm=`echo $lm| tr '[a-z]' '[A-Z]'`
                if [ -z "$lm" ]; then 
			lm="$LM_BASE"; build_lm=1; 
		else 
			build_lm=0; 
		fi
	fi
	if [ -z "$dmc" ]; then
                read -p "Need to know DMC basename (default $DMC_BASE)> " dmc ;
                dmc=`echo $dmc| tr '[a-z]' '[A-Z]'`
                if [ -z "$dmc" ]; then
                       dmc="$DMC_BASE"; build_dmc=1;
                else
                       build_dmc=0;
                fi
        fi
	printf "\n${Yellow}[$mode]>>BUILDING SEARCH HEAD CLUSTER!${NC}\n\n"
	printf "${Yellow}==>Starting PHASE1: Creating generic SH hosts${NC}\n"
	printf "${DarkGray}Using DMC[$dmc] LM:[$lm] CM:[$cm] LABEL:[$label] DEP:[$DEPname:($DEP_SHC_COUNT)] SHC:[$SHname:($SHcount)]${NC}\n"
        printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"
	 if [ "$build_dmc" == "1" ]; then
                create_generic_splunk "$dmc" "1"; dmc=$gLIST
        fi
	if [ "$build_lm" == "1" ]; then	
        	create_generic_splunk "$lm" "1" ; lm="$gLIST"
		make_lic_slave $lm $dmc  #for previous step since lm was not ready yet
                make_dmc_search_peer $dmc $lm
	fi
	
        create_generic_splunk "$DEPname" "$DEP_SHC_COUNT" ; dep="$gLIST"
	make_lic_slave $lm $dep
        make_dmc_search_peer $dmc $dep
        create_generic_splunk "$SHname" "$SHcount" ; members_list="$gLIST"
fi
printf "${LightBlue}___________ Finished creating hosts __________________________${NC}\n"

printf "${Yellow}==>Starting PHASE2: Converting generic SH hosts into SHC${NC}\n"

printf "${LightBlue}___________ Starting STEP#1 (deployer configuration) ____________________________${NC}\n" >&3

## from this point on all hosts should be created and ready. Next steps are SHCluster configurations ##########
#DEPLOYER CONFIGURATION: (create [shclustering] stanza; set SecretKey and restart) -----
printf "${DarkGray}Configuring SHC with created hosts: DEPLOYER[$dep]  MEMBERS[$members_list] ${NC}\n" >&3

#--------- 
printf "[${Purple}$dep${NC}]${LightBlue} Configuring Deployer ... ${NC}\n"
bind_ip_dep=`docker inspect --format '{{ .HostConfig }}' $dep| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
txt="\n #-----Modified by Docker Management script ----\n [shclustering]\n pass4SymmKey = $MYSECRET \n shcluster_label = $label\n"
#printf "%b" "$txt" >> $MOUNTPOINT/$dep/etc/system/local/server.conf	#cheesy fix!
printf "%b" "$txt" > server.conf.append
CMD="docker cp server.conf.append $dep:/tmp/server.conf.append"; OUT=`$CMD`
CMD=`docker exec -ti $dep  bash -c "cat /tmp/server.conf.append >> /opt/splunk/etc/system/local/server.conf" `; #OUT=`$CMD`

printf "\t->Adding stanza [shclustering] to server.conf!" >&3 ; display_output "$OUT" "" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$dep"

restart_splunkd "$dep"

printf "${LightBlue}___________ Finished STEP#1 __________________________${NC}\n" >&3

printf "${LightBlue}___________ Starting STEP#2 (members configs) ________${NC}\n" >&3
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}After members_list loop> parm2:[$2] members_list:[$members_list] sh_list:[$sh_list]${NC}\n" >&5
for i in $members_list ; do
	check_load	#throttle during SHC build

	#-------member config---
 	printf "[${Purple}$i${NC}]${LightBlue} Making cluster member...${NC}\n"
        bind_ip_sh=`docker inspect --format '{{ .HostConfig }}' $i| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	CMD="docker exec -ti $i /opt/splunk/bin/splunk init shcluster-config -auth $USERADMIN:$USERPASS -mgmt_uri https://$bind_ip_sh:$MGMT_PORT -replication_port $REPL_PORT -replication_factor $RFACTOR -register_replication_address $bind_ip_sh -conf_deploy_fetch_url https://$bind_ip_dep:$MGMT_PORT -secret $MYSECRET -shcluster_label $label"
	OUT=`$CMD`
	OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
	printf "\t->Initiating shcluster-config " >&3 ; display_output "$OUT" "clustering has been initialized" "3"
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$i"
	#-------
		
	#-------auto discovery---
	# if cm exist (passed to us); configure search peers for idx auto discovery
	if [ -n "$cm" ]; then
		#another method of getting bind IP (showing published ports:IPs).Container must be RUNNING!
		cm_ip=`docker port  $cm| awk '{print $3}'| cut -d":" -f1|head -1`
        	CMD="docker exec -ti $i /opt/splunk/bin/splunk edit cluster-config -mode searchhead -master_uri https://$cm_ip:$MGMT_PORT -secret $MYSECRET -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
		printf "\t->Integrating with Cluster Master (for idx auto discovery) [$cm] " >&3 ; display_output "$OUT" "property has been edited" "3"
		printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$i"
        fi
	#-------

        make_dmc_search_peer $dmc $i	
	make_lic_slave $lm $i
	restart_splunkd "$i" "b"

	#assign_server_role "$i" "dmc_group_search_head"
	server_list="$server_list""https://$bind_ip_sh:$MGMT_PORT,"   #used by STEP#3

done
server_list=`echo ${server_list%?}`  # remove last comma in string
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} server_list:[$server_list]________${NC}\n" >&5
printf "${LightBlue}___________ Finished STEP#2 __________________________${NC}\n" >&3
 
printf "${LightBlue}___________ Starting STEP#3 (configuring captain) ____${NC}\n" >&3
printf "[${Purple}$i${NC}]${LightBlue} Configuring as Captain (last SH created)...${NC}\n"

restart_splunkd "$i"  #last SH (captain) may not be ready yet, so force restart again

CMD="docker exec -ti $i /opt/splunk/bin/splunk bootstrap shcluster-captain -servers_list "$server_list" -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "\t->Captain bootstraping (may take time) " >&3 ; display_output "$OUT" "Successfully"  "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$i"
printf "${LightBlue}___________ Finished STEP#3 __________________________${NC}\n" >&3

printf "${LightBlue}___________ Starting STEP#4 (cluster status)__________${NC}\n" >&3
printf "[${Purple}$i${NC}]${LightBlue}==> Checking SHC status (on captain)...${NC}"

CMD="docker exec -ti $i /opt/splunk/bin/splunk show shcluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
display_output "$OUT" "Captain" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4 
logline "$CMD" "$i"
printf "${LightBlue}___________ Finished STEP#4 (cluster status)__________${NC}\n\n" >&3

END=$(date +%s);
TIME=`echo $((END-START1)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Total execution time for ${FUNCNAME}(): [$TIME]${NC}\n"
count=`wc -w $CMDLOGBIN| awk '{print $1}' `
printf "${DarkGray}Total Splunk config commands executed [%s]\n\n" "$count"

return 0
}   #create_single_shc()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_single_idxc () {
#This function creates single IDX cluster. Details are parsed from $1
#example call: create_single_idxc "$site-IDX:$IDXcount $cm:1 $lm $label"
#$1 AUTO or MANUAL mode

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

if [ "$1" == "AUTO" ]; then  mode="AUTO"; else mode="MANUAL"; fi

START2=$(date +%s);
#$1 CMbasename:count   $2 IDXbasename:count  $3 LMbasename:count

#Extract values from $1 if passed to us!
lm=`echo $1| $GREP -Po '(\s*\w*-*LM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
cm=`echo $1| $GREP -Po '(\s*\w*-*CM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
label=`echo $1| $GREP -Po '(\s*\w*-*LABEL):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
IDXname=`echo $1| $GREP -Po '(\s*\w*-*IDX)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
IDXcount=`echo $1| $GREP -Po '(\s*\w*-*IDX):\K(\d+)'| tr -d '[[:space:]]' `
CMname=`echo $1| $GREP -Po '(\s*\w*-*CM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
CMcount=`echo $1| $GREP -Po '(\s*\w*-*CM):\K(\d+)'| tr -d '[[:space:]]' `

cm_list=`docker ps -a --filter name="$CMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
lm_list=`docker ps -a --filter name="$LMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'` #global list
idx_list=`docker ps -a --filter name="$IDXname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`


if [ "$1" == "AUTO" ]; then
	#CMname="CM"; DMCname="DMC"; LMname="LM";  IDXname="IDX"; IDXcount="$STD_IDXC_COUNT"; 
	label="$IDXCLUSTERLABEL"
	printf "${Yellow}[$mode]>>BUILDING INDEX CLUSTER${NC}\n"
	printf "${Yellow}==>Starting PHASE1: Creating generic IDX hosts${NC}\n"
	printf "${DarkGray}Using basenames DMC:[$DMC_BASE] LM:[$LM_BASE] CM:[$CM_BASE] LABEL:[$IDXCLUSTERLABEL] IDXC:[$IDX_BASE:($STD_IDXC_COUNT)]${NC}\n\n"
        printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"

	#Basic services. Sequence is very important!
	create_generic_splunk "$DMC_BASE" "1" ; dmc=$gLIST
	create_generic_splunk "$LM_BASE" "1" ; lm=$gLIST
	make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
	create_generic_splunk "$CM_BASE" "1" ; cm=$gLIST
	make_lic_slave $lm $cm ; make_dmc_search_peer $dmc $cm

	#The rest of IDXs
        create_generic_splunk "$IDX_BASE" "$STD_IDXC_COUNT" ; members_list="$gLIST"
else
	#Anything passed to function; user will NOT be prompted for it!
	if [ -z "$label" ]; then
                read -p "Need to know IDX cluster label (default $SHCLUSTERLABEL)> " label ;
                label=`echo $label| tr '[a-z]' '[A-Z]'`; if [ -z "$label" ]; then label="$SHCLUSTERLABEL"; fi
        fi
	if [ -z "$IDXname" ] || [ -z "$IDXcount" ]; then
                read -p "Need to know IDX basename (default $IDX_BASE)> " IDXname ;
                IDXname=`echo $IDXname| tr '[a-z]' '[A-Z]'` ; if [ -z "$IDXname" ]; then IDXname="$IDX_BASE"; fi
		read -p "IDX count (default 3)> " IDXcount;
                if [ -z "$IDXcount" ]; then IDXcount="$STD_IDXC_COUNT"; fi
        fi
        if [ -z "$lm" ]; then
                printf "Current list of LMs: [$lm_list]\n"
                read -p "Choose LM from existing list or hit <ENTER> to create new one (default $LM_BASE)? " lm
		lm=`echo $lm| tr '[a-z]' '[A-Z]'`
                if [ -z "$lm" ]; then
                        lm="$LM_BASE"; build_lm=1;
                else
                        build_lm=0;
                fi
        fi
        if [ -z "$cm" ]; then
               	printf "Current list of CMs: [$cm_list]\n"
               	read -p "Choose CM from existing list or hit <ENTER> to create new one (default $CM_BASE)? " cm ;
		cm=`echo $cm| tr '[a-z]' '[A-Z]'`
               	if [ -z "$cm" ]; then
                       cm="$CM_BASE"; build_cm=1;
               	else
                       build_cm=0;
               	fi
       	fi
	if [ -z "$dmc" ]; then
                read -p "Need to know DMC basename (default $DMC_BASE)> " dmc ;
                dmc=`echo $dmc| tr '[a-z]' '[A-Z]'`
                if [ -z "$dmc" ]; then
                       dmc="$DMC_BASE"; build_dmc=1;
                else
                       build_dmc=0;
                fi
        fi
	printf "\n${Yellow}[$mode]>>BUILDING INDEX CLUSTER${NC}\n"
	printf "${Yellow}==>Starting PHASE1: Creating generic IDX hosts${NC}\n"
	printf "${DarkGray}Using DMC:[$dmc] LM:[$lm] CM:[$cm] LABEL:[$label] IDXC:[$IDXname:($IDXcount)]${NC}\n"
	printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"
	if [ "$build_dmc" == "1" ]; then
                create_generic_splunk "$dmc" "1"; dmc=$gLIST
        fi
        if [ "$build_lm" == "1" ]; then
                create_generic_splunk "$lm" "1" ; lm=$gLIST
		make_lic_slave $lm $dmc  #for previous step since lm was not ready yet
		make_dmc_search_peer $dmc $lm
        fi
       	if [ "$build_cm" == "1" ]; then
                create_generic_splunk "$cm" "1"; cm=$gLIST
		make_lic_slave $lm $cm
		make_dmc_search_peer $dmc $cm
        fi
	
	#create the remaining IDXs 
        create_generic_splunk "$IDXname" "$IDXcount" ; members_list="$gLIST"

fi
printf "${LightBlue}___________ Finished creating hosts __________________________${NC}\n"

printf "${Yellow}==>Starting PHASE2: Converting generic IDX hosts into IDXC${NC}\n"

printf "${LightBlue}____________ Starting STEP#1 (Configuring IDX Cluster Master) __${NC}\n" >&3
printf "[${Purple}$cm${NC}]${LightBlue} Configuring Cluster Master... ${NC}\n"

#-------CM config---
bind_ip_cm=`docker inspect --format '{{ .HostConfig }}' $cm| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
CMD="docker exec $cm /opt/splunk/bin/splunk edit cluster-config  -mode master -replication_factor $RFACTOR -search_factor $SFACTOR -secret $MYSECRET -cluster_label $label -auth $USERADMIN:$USERPASS "
OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 
logline "$CMD" "$cm"
printf "\t->Configuring CM [RF:$RFACTOR SF:$SFACTOR] and cluster label[$label] " >&3 ; display_output "$OUT" "property has been edited" "3"
#-------
restart_splunkd "$cm"
#assign_server_role "$i" ""
printf "${LightBlue}____________ Finished STEP#1 __________________________${NC}\n" >&3

printf "${LightBlue}____________ Starting STEP#2 (configuring IDXC nodes) ___${NC}\n" >&3
for i in $members_list ; do
	check_load	#throttle during IDXC build

	printf "[${Purple}$i${NC}]${LightBlue} Making search peer... ${NC}\n"
        bind_ip_idx=`docker inspect --format '{{ .HostConfig }}' $i| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	
	#-------member config----
        CMD="docker exec $i /opt/splunk/bin/splunk edit cluster-config -mode slave -master_uri https://$bind_ip_cm:$MGMT_PORT -replication_port $REPL_PORT -register_replication_address $bind_ip_idx -cluster_label $label -secret $MYSECRET -auth $USERADMIN:$USERPASS "
	OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
	printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$i"
	printf "\t->Make a cluster member " >&3 ; display_output "$OUT" "property has been edited" "3"
	#-------
	#-------tcp/9997---
        CMD="docker exec $i /opt/splunk/bin/splunk enable listen $RECV_PORT -auth $USERADMIN:$USERPASS "
        OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
        printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
        logline "$CMD" "$i"
        printf "\t->Enabling recieving port [$RECV_PORT] " >&3 ; display_output "$OUT" "Listening for" "3"
        #-------
	
	#We dont need to add IDXCs to DMC, just add their CM (which is already done)

	make_lic_slave $lm $i
	restart_splunkd "$i" "b"

	#assign_server_role "$i" "dmc_group_indexer"
done
printf "${LightBlue}____________ Finished STEP#2 __________________________${NC}\n" >&3

printf "${LightBlue}____________ Starting STEP#3 (IDXC status) ____________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${LightBlue}==> Checking IDXC status...${NC}"
CMD="docker exec -ti $cm /opt/splunk/bin/splunk show cluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`; display_output "$OUT" "Replication factor" "2"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "${LightBlue}____________ Finished STEP#3 __________________________${NC}\n\n" >&3

END=$(date +%s);
TIME=`echo $((END-START2)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Total execution time for ${FUNCNAME}(): [$TIME]${NC}\n"
count=`wc -w $CMDLOGBIN| awk '{print $1}' `
printf "${DarkGray}Total Splunk config commands executed [%s]\n\n" "$count"

return 0
}  #end create_single_idxc()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
build_single_site () {
#This function will build 1 CM and 1 LM then calls create_generic_splunk()
# Expected parameters: "$cm $lm $site-IDX:$IDXcount $site-SH:$SHcount $site-DEP:1"
#$1 AUTO or MANUAL mode

display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

START2=$(date +%s);
#extract these values from $1 if passed to us!
lm=`echo $1| $GREP -Po '(\s*\w*-*LM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
cm=`echo $1| $GREP -Po '(\s*\w*-*CM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
CMname=`echo $1| $GREP -Po '(\s*\w*-*CM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
CMcount=`echo $1| $GREP -Po '(\s*\w*-*CM):\K(\d+)'| tr -d '[[:space:]]' `

#cm_list=`docker ps -a --filter name="$CMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`

if [ "$1" == "AUTO" ]; then  
	mode="AUTO"
	IDXcount="$STD_IDXC_COUNT"
	SHcount="$STD_SHC_COUNT"
	shc_label="$SHCLUSTERLABEL"
	idxc_label="$IDXCLUSTERLABEL"
	site="SITE01"
else
	mode="MANUAL"
	read -p "Enter SH cluster label (default $SHCLUSTERLABEL): " shc_label
        shc_label=`echo $shc_label| tr '[a-z]' '[A-Z]'`; if [ -z "$shc_label" ]; then shc_label="$SHCLUSTERLABEL";  fi
	
	read -p "Enter IDX cluster label (default $IDXCLUSTERLABEL): " idxc_label
        idxc_label=`echo $idxc_label| tr '[a-z]' '[A-Z]'`; if [ -z "$idxc_label" ]; then idxc_label="$IDXCLUSTERLABEL";  fi

	read -p "Enter site name (default site01): " site
	site=`echo $site| tr '[a-z]' '[A-Z]'`		#convert to upper case 
	if [ -z "$site" ]; then site="SITE01";  fi

        read -p "How many IDX's (default $STD_IDXC_COUNT)>  " IDXcount
        if [ -z "$IDXcount" ]; then IDXcount="$STD_IDXC_COUNT"; fi
        read -p "How many SH's (default $STD_SHC_COUNT)>  " SHcount
        if [ -z "$SHcount" ]; then SHcount="$STD_SHC_COUNT"; fi
fi

#assign_server_role "$lm" "dmc_group_license_master"
echo

printf "${Yellow}==>[$mode] Building single-site ($site)...${NC}\n\n"
printf "${LightBlue}____________ Building basic services [LM, DMC, CM] ___________________${NC}\n" >&3
#Basic services
#Sequence is very important!
create_generic_splunk "$site-DMC" "1" ; dmc=$gLIST
create_generic_splunk "$site-LM" "1" ; lm=$gLIST
make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
create_generic_splunk "$site-CM" "1" ; cm=$gLIST
make_lic_slave $lm $cm ; make_dmc_search_peer $dmc $cm

#testing HF ****************************************
create_generic_splunk "$site-HF" "1" ; hf=$gLIST
make_lic_slave $lm $hf ; #make_dmc_search_peer $dmc $hf

printf "${LightBlue}____________ Finished building basic serivces ___________________${NC}\n\n" >&3

create_single_idxc "$site-IDX:$IDXcount $dmc $cm:1 $lm LABEL:$idxc_label"
create_single_shc "$site-SH:$SHcount $site-DEP:1 $dmc $cm $lm LABEL:$shc_label"

END=$(date +%s);
TIME=`echo $((END-START2)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Total execution time for ${FUNCNAME}(): [$TIME]${NC}\n"
count=`wc -w $CMDLOGBIN| awk '{print $1}' `
printf "${DarkGray}Total Splunk config commands executed [%s]\n\n" "$count"


return 0
} #build_single_site
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
build_multi_site_cluster () {
#This function creates site-2-site cluster
#http://docs.splunk.com/Documentation/Splunk/6.4.3/Indexer/Migratetomultisite
display_debug  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

mode=$1		#either "AUTO" or "MANUAL"
START3=$(date +%s);

s=""; sites_str=""     			#used with "splunk edit cluster-config" on CM
SITEnames=""

printf "One DEP server per SHC will be automatically created.\n"
printf "One CM server will be automatically created for the entire site-2-site cluster.\n"

if [ "$mode" == "AUTO" ]; then
	count=3;
        IDXcount="$STD_IDXC_COUNT"; SHcount="$STD_SHC_COUNT"; shc_label="$SHCLUSTERLABEL"; idxc_label="$IDXCLUSTERLABEL"
	#SITEnames="$DEFAULT_SITES_NAMES"
        SITEnames="STL LON HKG"
        sites_str="site1,site2,site3"
	first_site=`echo $SITEnames|awk '{print $1}'`		#where basic services CM,LM resides
	cm="$first_site-CM01"
else
	read -p "How many LOCATIONS to build (default 3)?  " count
        if [ -z "$count" ]; then count=3; fi
	
	#loop thru site count to capture site details
	for (( i=1; i <= ${count}; i++));
        do
		printf "\n"
                read -p "Enter site$i fullname (default SITE0$i)>  " site
                if [ -z "$site" ]; then site="site0$i"; fi
                read -p "How many IDX's (default $STD_IDXC_COUNT)>  " IDXcount
                if [ -z "$IDXcount" ]; then IDXcount="$STD_IDXC_COUNT"; fi
                read -p "How many SH's (default $STD_SHC_COUNT)>  " SHcount
                if [ -z "$SHcount" ]; then SHcount="$STD_SHC_COUNT"; fi

                SITEnames="$SITEnames ""$site"
		SITEnames=`echo $SITEnames| tr '[a-z]' '[A-Z]' `	#upper case
                s="site""$i"
                sites_str="$sites_str""$s,"               #spaces causes error with "-available_sites" switch
                #echo "$s [$sites_str]"
        done
	sites_str=`echo ${sites_str%?}`  			#remove last comma
	first_site=`echo $SITEnames|awk '{print $1}'`			#where basic services CM,LM resides
	printf "\n"
	read -p "site-to-site cluster must have one CM. Enter CM fullname (default $first_site-CM01)> " cm
        cm=`echo $cm| tr '[a-z]' '[A-Z]' `
        if [ -z "$cm" ]; then cm="$first_site-CM01"; fi
fi

#------- Finished capturing sites names/basic services names ------------------

printf "\n\n${BoldYellowBlueBackground}[$mode] Building site-to-site cluster...${NC}\n"
printf "${DarkGray}Using Locations:[$SITEnames] sites_str:[$sites_str] CM:[$cm] First_site:[$first_site] ${NC}\n"

printf "\n\n${Yellow}Creating cluster basic services [only in $first_site]${NC}\n"
#Sequence is very important!
create_generic_splunk "$first_site-DMC" "1" ; dmc=$gLIST
create_generic_splunk "$first_site-LM" "1" ; lm=$gLIST
make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
create_generic_splunk "$first_site-CM" "1" ; cm=$gLIST
make_lic_slave $lm $cm ; make_dmc_search_peer $dmc $cm

#Loop thru list of sites & build generic SH/IDX hosts on each site
counter=0
for site in $SITEnames; do
	let counter++
	#printf "counter=[$counter] [$SITEnames]\n"
	printf "\n${BoldYellowBlueBackground}Building site$counter >> $site ${NC}\n"
	create_single_idxc "$site-IDX:$IDXcount $cm $lm LABEL:$IDXCLUSTERLABEL"
	create_single_shc "$site-SH:$SHcount $site-DEP:1 $cm $lm LABEL:$SHCLUSTERLABEL"
done

idx_list=`docker ps -a --filter name="IDX|idx" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
sh_list=`docker ps -a --filter name="SH|sh" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
site_list=`echo $cm_list | sed 's/\-[a-zA-Z0-9]*//g' `

printf "${BoldYellowBlueBackground}Migrating existing IDXCs & SHCs to site-2-site cluster: LM[$lm] CM[$cm] sites[$SITEnames] sites_str[$sites_str]${NC}\n"

#echo "list of sites[$SITEnames]   cm[$cm]"

printf "${Cyan}____________ Starting STEP#1 (Configuring one CM for all locations) _____________________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${Cyan} Configuring Cluster Master... ${NC}\n"
cm_ip=`docker port $cm| awk '{print $3}'| cut -d":" -f1|head -1 `
CMD="docker exec -ti $cm /opt/splunk/bin/splunk edit cluster-config -mode master -multisite true -available_sites $sites_str -site site1 -site_replication_factor origin:2,total:3 -site_search_factor origin:1,total:2 -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "\t->Setting multisite to true... " >&3 ; display_output "$OUT" "property has been edited" "3"

CMD="docker exec -ti $cm /opt/splunk/bin/splunk enable maintenance-mode --answer-yes -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "\t->Enabling maintenance-mode... " >&3 ; display_output "$OUT" "maintenance mode set" "3"

restart_splunkd "$cm"
printf "${Cyan}____________ Finished STEP#1 __________________________________________________${NC}\n" >&3

printf "${Cyan}____________ Starting STEP#2 (Configuring search peers in [site:"$site""$seq" location:$str]) _____________________${NC}\n" >&3

seq=1
for str in $SITEnames; do
	site="site""$seq"
	site_idx_list=`echo $idx_list | $GREP -Po '('$str'-\w+\d+)' | tr -d '\r' | tr  '\n' ' '  `
	site_sh_list=`echo $sh_list | $GREP -Po '('$str'-\w+\d+)' | tr -d '\r' | tr  '\n' ' '  `
	for i in $site_idx_list; do
		printf "[${Purple}$i${NC}]${Cyan} Migrating Indexer (restarting takes time)... ${NC}\n"
		CMD="docker exec -ti $i /opt/splunk/bin/splunk edit cluster-config -site $site -master_uri https://$cm_ip:$MGMT_PORT -replication_port $REPL_PORT  -auth $USERADMIN:$USERPASS "
		OUT=`$CMD`
        	OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up

		printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$i"
		printf "\t->Configuring multisite clustering for [site:$site location:$str] " >&3 
		display_output "$OUT" "property has been edited" "3"
		restart_splunkd "$i" "b"
	done
	printf "${Cyan}____________ Finished STEP#2 __________________________________________________${NC}\n" >&3

	printf "${Cyan}____________ Starting STEP#3 (Configuring SHs in [site:$site location:$str]) ___${NC}\n" >&3
	for i in $site_sh_list; do
		printf "[${Purple}$i${NC}]${Cyan} Migrating Search Head... ${NC}\n"
	    	CMD="docker exec -ti $i /opt/splunk/bin/splunk edit cluster-master https://$cm_ip:$MGMT_PORT -site $site -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
                OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
		printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$i"
		printf "\t->Pointing to CM[$cm] for [site:$site location:$str]" >&3 
		display_output "$OUT" "property has been edited" "3"
		restart_splunkd "$i" "b"
	done
	printf "${Cyan}____________ Finished STEP#3 __________________________________________________${NC}\n" >&3

seq=`expr $seq + 1`
done  #looping thru the sites list

printf "${Cyan}____________ Starting STEP#4 (CM maintenance-mode) _____________________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${Cyan} Disabling maintenance-mode... ${NC}\n"
CMD="docker exec -ti $cm /opt/splunk/bin/splunk disable maintenance-mode -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "\t->Disabling maintenance-mode..." >&3 ; display_output "$OUT" "No longer"  "3"
#restart_splunkd "$i"
printf "${Cyan}____________ Finished STEP#4 __________________________________________________${NC}\n" >&3

END=$(date +%s);
TIME=`echo $((END-START3)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Total execution time for ${FUNCNAME}(): [$TIME]${NC}\n"
count=`wc -w $CMDLOGBIN| awk '{print $1}' `
printf "${DarkGray}Total Splunk config commands executed [%s]\n\n" "$count"

return 0
}  #build_multi_site_cluster ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_menu2 () {
	clear
	printf "${Green}Docker Splunk Infrastructure Management -> Clustering Menu:${NC}${LightBlue}[$dockerinfo]${NC}\n"
	printf "=====================[$dockerinfo2] [OS:$os FreeMem:$max_mem GB MaxLoad:$MAXLOADAVG] [LogLevel:$loglevel]==\n\n"
	printf "${Yellow}B${NC}) Go back to MAIN menu\n\n"

	printf "${Purple}AUTO BUILDS (fixed: R3/S2 1-CM 1-DEP 3-SHC 1-CM 3-IDXC):\n"
        printf "${Purple}1${NC}) Create Stand-alone Index Cluster (IDXC)\n";
        printf "${Purple}2${NC}) Create Stand-alone Search Head Cluster (SHC)\n"
        printf "${Purple}3${NC}) Build Single-site Cluster\n"
        printf "${Purple}4${NC}) Build Multi-site Cluster (3 sites)${NC} \n";echo
	
	printf "${LightBlue}MANUAL BUILDS (specify base hostnames and counts)\n"
        printf "${LightBlue}5${NC}) Create Manual Stand-alone Index cluster (IDXC)\n";
	printf "${LightBlue}6${NC}) Create Manual Stand-alone Search Head Cluster (SHC)\n"
        printf "${LightBlue}7${NC}) Build Manual Single-site Cluster\n"
        printf "${LightBlue}8${NC}) Build Manual Multi-site Cluster${NC} \n";echo 
return 0
} #display_menu2()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
clustering_menu () {
#This function captures user selection for clustering_menu
while true;
do
        dockerinfo=`docker info|head -5| tr '\n' ' '|sed 's/: /:/g'`
        display_menu2
        choice=""
        read -p "Select a number: " choice
                case "$choice" in
	        B|b) return 0;;

		1 ) create_single_idxc "AUTO"; read -p $'\033[1;32mHit <ENTER> to continue...\e[0m' ;;
                2 ) create_single_shc  "AUTO"; read -p $'\033[1;32mHit <ENTER> to continue...\e[0m' ;;
                3 ) build_single_site "AUTO"; read -p $'\033[1;32mHit <ENTER> to continue...\e[0m' ;;
                4 ) build_multi_site_cluster "AUTO"; read -p $'\033[1;32mHit <ENTER> to continue...\e[0m' ;;

                5 ) 	printf "${White} **Please remember to follow host naming convention**${NC}\n";
			create_single_idxc; 
			read -p $'\033[1;32mHit <ENTER> to continue...\e[0m' ;;
		6 ) 	printf "${White} **Please remember to follow host naming convention**${NC}\n";
			create_single_shc; 
			read -p $'\033[1;32mHit <ENTER> to continue...\e[0m' ;;
                7 ) 	printf "${White} **Please remember to follow host naming convention**${NC}\n";
			build_single_site; 
			read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'  ;;
                8 ) 	printf "${White} **Please remember to follow host naming convention**${NC}\n";
			build_multi_site_cluster; 
			read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'  ;;

		q|Q ) echo "Exit!" ;break ;;
                *) read -p $'\033[1;32mHit <ENTER> to continue...\e[0m' ;;
        esac  #end case ---------------------------
        echo "------------------------------------------------------";echo
done
return 0
}  #clustering_menu()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_menu () {
#This function displays user options for the main menu
	clear
	printf "${Yellow}Docker Splunk Infrastructure Management Main Menu:${NC}${LightBlue}[$dockerinfo]${NC}\n"
	printf "=====================[$dockerinfo2] [OS:$os FreeMem:$max_mem GB MaxLoad:$MAXLOADAVG] [LogLevel:$loglevel]==\n\n"
	printf "${Red}C${NC}) CREATE containers ${DarkGray}[docker run ...]${NC}\n"
	printf "${Red}D${NC}) DELETE all containers ${DarkGray}[docker rm -f \$(docker ps -aq)]${NC}\n"
	printf "${Red}R${NC}) REMOVE all volumes to recover diskspace ${DarkGray}[docker volume rm \$(docker volume ls -qf 'dangling=true')]${NC}\n"
	printf "${Red}Q${NC}) Quit${NC}\n"
	echo
	printf "${Yellow}1${NC}) SHOW all containers OR launch in a browser ${DarkGray}[custom view]${NC} \n"
	printf "${Yellow}2${NC}) START all stopped containers ${DarkGray}[docker start \$(docker ps -a --format \"{{.Names}}\")]${NC}\n"
	printf "${Yellow}3${NC}) STOP all running containers ${DarkGray}[docker stop \$(docker ps -aq)]${NC}\n"
	printf "${Yellow}4${NC}) Show hosts by hostname groups ${DarkGray}[works only if you followed the host naming rules]${NC}\n"
	echo
	printf "${LightBlue}5${NC}) RESET all splunk passwords [changeme --> $USERPASS] ${DarkGray}[splunkd must be running]${NC}\n"
	printf "${LightBlue}6${NC}) ADD splunk licenses ${DarkGray}[splunkd must be running]${NC}\n"
	printf "${LightBlue}7${NC}) Splunkd status ${DarkGray}[docker -exec -it hostname /opt/splunk/bin/splunk status]${NC}\n"
	printf "${LightBlue}8${NC}) Remove IP aliases on the Ethernet interface${NC}\n"
	printf "${LightBlue}9${NC}) RESTART all splunkd instances\n\n"
	printf "${Green}10${NC}) Clustering Menu \n"
	echo
return 0
}    #end display_menu()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------
### MAIN BEGINS #####

#The following must start at the beginning for the code since we use I/O redirection for logging
#--------------------
#http://stackoverflow.com/questions/8455991/elegant-way-for-verbose-mode-in-scripts/8456046
loglevel=2
maxloglevel=7 #The highest loglevel we use / allow to be displayed. 

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.
output_file=""
while getopts "h?v:f:" opt; do
    case "$opt" in
    h|\?)
        echo "HELP!"
        exit 0
        ;;
    v)  loglevel=$OPTARG
        ;;
    f)  output_file=$OPTARG
       ;;
    esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
#echo "loglevel='$loglevel'   output_file='$output_file'    Leftovers: $@"
#echo "1------[$opt][$OPTARG] [${loglevel}]-----maxloglevel[$maxloglevel]"

#Start counting at 2 so that any increase to this will result in a minimum of file descriptor 3.  You should leave this alone.
#Start counting from 3 since 1 and 2 are standards (stdout/stderr).
for v in $(seq 3 $loglevel); do
    (( "$v" <= "$maxloglevel" )) && eval exec "$v>&2"  #Don't change anything higher than the maximum loglevel allowed.
done

#From the loglevel level one higher than requested, through the maximum;
for v in $(seq $(( loglevel+1 )) $maxloglevel ); do
    (( "$v" > "2" )) && eval exec "$v>/dev/null" #Redirect these to bitbucket, provided that they don't match stdout and stderr.
done
#DEBUG
#printf "%s\n" "This message is seen at verbosity level 3 and above." >&3
#printf "%s\n" "This message is seen at verbosity level 4 and above." >&4
#printf "%s\n" "This message is seen at verbosity level 5 and above." >&5
#exit
#------------------

rm  -fr $CMDLOGBIN $CMDLOGTXT
printf "\n--------------- Starting new script run. Color changes when hostname changes -------------------\n" > $CMDLOGBIN
printf "\n--------------- Starting new script run. Color changes when hostname changes -------------------\n" > $CMDLOGTXT

clear
#house keeping functions
check_shell
detect_os
setup_ip_aliases
while true;  
do
	dockerinfo=`docker info|head -5| tr '\n' ' '|sed 's/: /:/g'`
	dockerinfo2=`docker info| $GREP -Po 'Server Version:\s+(\d+\.\d+\d+\.\d+).*|\n*CPUs:\s+(\d+).*|\n*Total Memory:\s+(\d+)'| sed 's/Server Version/Docker/'|sed 's/Total Memory/TotalMem/g'| sed 's/ //g' `
	dockerinfo2=`echo $dockerinfo2 | tr -d '\n' `
	display_menu 
	choice=""
	read -p "Select a number: " choice
       		case "$choice" in
		c|C) create_generic_splunk  ;; 
		d|D ) echo "Deleting all containers: " ; 
			docker rm -f $(docker ps -a --format "{{.Names}}");
			rm -fr $HOSTSFILE;;
		r|R ) echo "Removing all volumes (to recover disk-space): "; 
			#disk1=`df -kh /var/lib/docker/| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
			#disk1=`df -kh $MOUNTPOINT| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
			docker volume rm $(docker volume ls -qf 'dangling=true') 
			#rm -fr $MOUNTPOINT
			#disk2=`df -kh $MOUNTPOINT| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
			#freed=`expr $disk2 - $disk1`
			#printf "Disk space freed [$freed] GB\n"
			rm -fr $HOSTSFILE
			;;

		1 ) show_all_containers ;;
		2 ) echo "Starting all containers: "; docker start $(docker ps -a --format "{{.Names}}") ;;
		3 ) echo "Stopping all containers (graceful): "; 
		   for i in `docker ps --format "{{.Names}}"`; do
			printf "${Purple}$i${NC} "
                        docker exec $i /opt/splunk/bin/splunk stop ;
		    	docker stop -t30 $i;
                        done;;
		4 ) show_groups ;;
		5 ) for i in `docker ps --format "{{.Names}}"`; do reset_splunk_passwd $i; done ;;
		6 ) for i in `docker ps --format "{{.Names}}"`; do add_license_file $i; done ;;

		7 ) splunkd_status_all ;;
		8 ) remove_ip_aliases ;;
		9) for i in `docker ps --format "{{.Names}}"`; do
			restart_splunkd "$i"
	        	done;;

		10 ) clustering_menu ;;

		q|Q ) echo;
		      echo -e "Quitting... Please send feedback to mhassan@splunk.com! \0360\0237\0230\0200";
		      break ;;
	esac  #end case ---------------------------
	
	read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
	echo "------------------------------------------------------";echo

done  #end of while(true) loop

##### EOF #######


