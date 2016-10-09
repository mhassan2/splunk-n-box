#!/bin/bash
#################################################################################
# Discription:	This script is inteded to enable you to create number of Splunk infrastructure
# 	elements on the fly. A perfect tool to setup a quick splunk lab for training
# 	or testing purposes.
#
# List of capabilities:
#	-Extensive Error checking
#	-Load control (throttling) if exceeds 4xcores
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
# Licenses: 	Licensesed under GPL v3 <link>
# Author:    	mhassan@splunk.com
# Version:	1.0
#
#Usage :  create-slunk.sh -v[3 4 5] 
#		v1-2	default setting (recommended for ongoing usage)
#		-v3	recommended for inital testing
#		-v4	increase verbosity
#		-v5	even more verbosity
# MAC OSX : must install ggrep to get PCRE regrex matching working 
# -for Darwin http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html
# -mount point must be under /User/${USER}
#
# TODO: -add routines for UF and HF containers with eventgen.py
#	-add DS containers with default serverclass.conf
#	-ability to adjust RF and SF
#################################################################################

#Network stuff
ETH_OSX="lo0"			#default interface to use with OSX laptop
ETH_LINUX="eno1"		#default interface to use with Linux server
GREP_OSX="/usr/local/bin/ggrep"	#you MUST install Gnu grep on OSX
GREP_LINUX="/bin/grep"		#default grep for Linux

#IP aliases range to create. Must use routed network if you want reach host from outside
#LINUX is routed and hosts can be reached from anywhere in the network
START_ALIAS_LINUX="192.168.1.100";  	END_ALIAS_LINUX="192.168.1.254"

#OSX space will not be routed, and host reached from the laptop only
START_ALIAS_OSX="10.0.0.100";  		END_ALIAS_OSX="10.0.0.254"

DNSSERVER="192.168.1.19"		#if running dnsmasq. Set to docker-host machine IP

#Full PATH is dynamic based on OS type, see detect_os()
FILES_DIR="splunk_docker_script_github" #place anything needs to copy to container here
LIC_FILES_DIR="licenses_files"		#place all your license file here
VOL_DIR="docker-volumes"		#directory name for volumes mount point.Full path is dynamic based on OS type

#The following are set in detect_os()
#MOUNTPOINT=
#ETH=
#GREP=

#more can be found http://hub.docker.com
SPLUNK_IMAGE="mhassan/splunk"		#my own built image
#SPLUNK_IMAGE="outcoldman/splunk:6.4.2"	#taken offline by outcoldman
#SPLUNK_IMAGE="splunk/splunk"		#official image -recommended-
#SPLUNK_IMAGE="splunk/splunk:6.5.0"	#official image
#SPLUNK_IMAGE="btorresgil/splunk"
#SPLUNK_IMAGE="xeor/splunk"
BASEHOSTNAME="IDX"			#default hostname to create
SPLUNKNET="splunk-net"			#default name for splunk docker network (host-to-host comm)

#Set the local splunkd path if you're runnig splunk on this docker-host (ex laptop).
#Used in validation_check() routine to detect local instance and kill it, otherwise it will interfer with this script operation
LOCAL_SPLUNKD="/opt/splunk/bin/splunk"	#dont run local splunkd instance on docker-host

#Splunk standard ports
SSHD_PORT="8022"	#in case we need to enable sshd, not recommended
SPLUNKWEB_PORT="8000"
MGMT_PORT="8089"
KV_PORT="8191"
IDX_PORT="9997"
REPL_PORT="9887"
HEC_PORT="8081"
USERADMIN="admin"
USERPASS="hello"

#default cluster configurations
RFACTOR="3"
SFACTOR="2"
SHCLUSTERLABEL="shcluster1"
IDXCLUSTERLABEL="idxcluster1"
MYSECRET="mysecret"
STD_IDXC_COUNT="3"	#default IDXC size
STD_SHC_COUNT="3"	#default SHC size

#Misc
LOGFILE="${0##*/}.log"   #log file will be this_script_name.log
HOSTSFILE="/etc/docker-hosts.dnsmasq"  #optional if dns caching is used

#Load control
MAXLOADTIME=10		#seconds increments for timer
MAXLOADAVG=4		#Not used
LOADFACTOR=3            #allow (3 x cores) of load on docker-host
LOADFACTOR_OSX=1        #allow (1 x cores) for the MAC (testing..)

#Using colors to make it user friendly -:)
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

# *** Let the fun begin ***

#Log level is controlled with I/O redirection. Must be first thing executed in a bash script
# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
exec >> >(tee -i $LOGFILE)
exec 2>&1

#---------------------------------------------------------------------------------------------------------
check_shell () {
# Check that we're in a BASH shell
if test -z "$BASH" ; then
  echo "This script ${0##*/} must be run in the BASH shell... Aborting."; echo;
  exit 192
fi
}    #end check_shell()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
echo_logline() {    #### NOT USED YET ####
    echo -e `date +'%b %e %R '` "$@"
}
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
remove_ip_aliases () {
#Delete ip aliases on the interface (OS dependant)

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

printf "Checking if last IP alias is configured on any NIC [$END_ALIAS]..."
last_alias=`ifconfig | $GREP $END_ALIAS `
if [ -n "$last_alias" ]; then
	printf "${Green} Ok!\n"
else
	printf "${Red}No IP aliases configured${NC}\n"
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
read -p "Hit <ENTER> to continue..."
return 0
}  #setup_ip_aliases()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_load () {
#We need to throttle back host creation if running on low powerd server. Set to 4 x num of cores
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
	#echo "OS:[$os] MAX ALLOWED LOAD:[$MAXLOADAVG] current load:[$loadavg]"
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

#----------
printf "${Yellow}Checking xcode commandline tools:${NC} "
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
printf "${Yellow}Checking brew package management:${NC} "
condition=$(which brew 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${Yellow}Running [/usr/bin/ruby -e \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)\" ]${NC}\n"
	#cd ~
 	/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
	printf "${Green}Already installed${NC}\n"
fi
#----------
printf "${Yellow}Checking pcre package:${NC} "
cmd=$(brew ls pcre --versions)
if [ -n "$cmd" ]; then
	printf "${Green}Already installed${NC}\n"
else
	printf "${Yellow}Running [brew install pcre]${NC}\n"
 	brew install pcre
fi
#----------
printf "${Yellow}Checking ggrep package:${NC} "
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
read -p "Hit <ENTER> to continue..."
echo
return 0
}  #end install gnu_grep
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
validation_check () {

if [ "$os" == "Darwin" ]; then
	printf "Checking if GNU grep is installed [$GREP]..."
        condition=$(which $GREP_OSX 2>/dev/null | grep -v "not found" | wc -l)
        if [ $condition -eq 0 ] ; then
                printf "${Red}$GREP not installed${NC}\n"
                printf "GNU grep is needed for this script to work. We use PCRE regex in ggrep! \n"
		printf "http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html \n"
		read -p "Install Gnu grep ggrep? [Y/n]? " answer
        	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
			install_gnu_grep
		else
			printf "${LightRed}This scrip will not work withouth Gnu grep${NC}\n"
			printf "http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html \n"
			exit
		fi
        else
                printf "${Green} Ok!${NC}\n"
        fi
fi

#-----------
printf "Checking if we have enough memory free..."
if [ "$os" == "Linux" ]; then
        max_mem=`free -mg|grep -i mem|awk '{print $2}' `
        if [ "$max_mem" -le "30" ]; then
		printf "[$max_mem GB]  ${BrownOrange}WARNING!${NC}\n"
		printf "Suggestions:\n"
                printf "1-Recomending 32GB or more for smooth operation\n"
                printf "2-Some of the cluster automated builds may fail!\n"
                printf "3-Try limiting your builds to 15 containers!\n"
		printf "4-Restart EXISTED container manually\n\n"
		printf " ----------------------------------------------\n\n"
	else
                printf "[$max_mem GB]${Green} Ok!${NC}\n"
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
		printf "[$max_mem GB]  ${BrownOrange}WARNING!${NC}\n"
		printf "Suggestions:\n"
		printf "1-Remove legacy boot2docker if installed (starting docker 1.12 no longer needed)\n" 
                printf "2-Recomending 32GB or more for smooth operation\n"
                printf "3-Some of the cluster automated builds may fail if we dont have enough memory/cpu!\n"
                printf "4-Try limiting your builds to 15 containers!\n"
		printf "5-Restart EXISTED containers manually\n"
		printf "${White}4-Change docker default settings! From docker icon ->Preference->General->Choose max CPU/MEM available${NC}\n" 
		printf " ----------------------------------------------\n\n"
	else
                printf "[$max_mem GB]${Green} Ok!${NC}\n"
	fi
fi
#-----------

#-----------
printf "Checking if docker daemon is running..."
is_running=`docker info|grep Images`
if [ -z "$is_running" ]; then
	printf "${Red}docker is not running or not installed${NC}.\n"
	if [ "$os" == "Darwin" ]; then
                printf "See this link for MAC OSX installtion: https://docs.docker.com/v1.10/mac/step_one/ \n"
	elif [ "$os" == "Linux" ]; then
                printf "See this link for Linux installtion: https://docs.docker.com/engine/installation/ \n"
	fi
        exit
else
        printf "${Green} Ok!${NC}\n"
fi
#-----------

#-----------
printf "Checking if splunk image is available [$SPLUNK_IMAGE]..."
image_ok=`docker images|grep $SPLUNK_IMAGE`
if [ -z "$image_ok" ]; then
	printf "${Red}NOT FOUND!${NC}\n\n"
        printf "I will attempt to download this image. If that doesn't work you can try: \n"
	printf "  1-link: https://github.com/outcoldman/docker-splunk \n"
	printf "  2-link: https://github.com/splunk/docker-splunk/tree/master/enterprise \n"
	printf "  3-Search for splunk images https://hub.docker.com/search/?isAutomated=0&isOfficial=0&page=1&pullCount=0&q=splunk&starCount=0\n\n"
	printf "${Yellow}"
	read -p "Hit <ENTER> to download... [$SPLUNK_IMAGE]"	
	printf "${Yellow}Running [docker pull $SPLUNK_IMAGE]...(may take time)${NC}\n\n"
	docker pull $SPLUNK_IMAGE
	docker images
	#out="$(docker pull $SPLUNK_IMAGE 2>&1)"
	#if ( contains "$out" "error" ); then
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
        printf "${Green} Ok!${NC}\n"
fi
#-----------

#-----------
printf "Checking if docker network is created [$SPLUNKNET]..."
net=`docker network ls | grep $SPLUNKNET `
if [ -z "$net" ]; then 
	printf "${Green} Creating...${NC}\n"
        docker network create -o --iptables=true -o --ip-masq -o --ip-forward=true $SPLUNKNET
else
       printf "${Green} Ok!${NC}\n"
fi
#-----------
#-----------
printf "Checking if non-docker splunkd proces is running on this host [$LOCAL_SPLUNKD]..."
PID=`ps aux | $GREP 'splunkd' | $GREP 'start' | head -1 | awk '{print $2}' `  	#works on OSX & Linux
if [ "$os" == "Darwin" ]; then
	splunk_is_running="$PID"
elif [ "$os" == "Linux" ]; then
	splunk_is_running=`cat /proc/$PID/cgroup|head -n 1|grep -v docker`	#works on linux only
fi
#echo "PID[$PID]"
#echo "splunk_is_running[$splunk_is_running]"
if [ -n "$splunk_is_running" ]; then
	printf "${Red}Running [$PID]${NC}\n"
	read -p "Kill it? [Y/n]? " answer
       	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		sudo $LOCAL_SPLUNKD stop
	else
		printf "${Red}WARNING! Runing local splunkd may prevent containers from binding to interfaces!${NC}\n\n"	
	fi
else
	printf "${Green} Ok!${NC}\n"
fi
#-----------

#check dnsmasq
#check $USER
return 0
}     #end validation_check()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
detect_os () {	
#Set global vars based on OS type:
# ETH to use
# GREP command. Must install ggrep utililty on OSX 
# MOUNTPOINT   (OSX is strict about permissions)

#FILES_DIR="splunk_docker_script_github"  #place anything needs to copy to container here
#LIC_FILES_DIR="license_files"
#VOL_DIR="docker-volumes"

uname=`uname -a | awk '{print $1}'`	
if [ "$(uname)" == "Darwin" ]; then
    	os="Darwin"
	START_ALIAS=$START_ALIAS_OSX
	END_ALIAS=$END_ALIAS_OSX
	ETH=$ETH_OSX
	GREP=$GREP_OSX		#for Darwin http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html
	MOUNTPOINT="/Users/${USER}/$VOL_DIR"
	PROJ_DIR="/Users/${USER}/$FILES_DIR"  #anything that needs to copied to container

	printf "Detected MAC OSX...\n"
	validation_check

elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    	os="Linux"
	START_ALIAS=$START_ALIAS_LINUX
        END_ALIAS=$END_ALIAS_LINUX
	GREP=$GREP_LINUX
	ETH=$ETH_LINUX
	MOUNTPOINT="/home/${USER}/$VOL_DIR"
	PROJ_DIR="/home/${USER}/$FILES_DIR"

	printf "Detected LINUX...\n"
	validation_check

elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    	os="Windows"
fi
return 0
}	#end detect_os ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
contains() {
# String comparision routine.
# usage:   contains(string, substring)
# Returns 0 if the specified string contains the specified substring,otherwise return 1
    string="$1"
    substring="$2"
    if test "${string#*$substring}" != "$string"
    then
        return 0    # $substring is in $string
    else
        return 1    # $substring is not in $string
    fi
} #end ontains()
#---------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------
add_license_file () {
#This function will just copy the lincense file. Later on if the container get configured
#as a license-slave; then this file become irrelevant
# $1=fullhostname
#Little tricky see: https://docs.docker.com/engine/reference/commandline/cp/
CMD="docker cp $PROJ_DIR/$LIC_FILES_DIR  $1:/opt/splunk/etc/licenses/enterprise"; OUT=`$CMD`
printf "\t->Copying license file(s). Will override if later became license-slave " >&3 ; display_output "$OUT" "" "n" "3"
printf " ${DarkGray}CMD:[$CMD]${NC}\n" >&3

if ( contains "$1" "LM" ); then
	printf "\t->*LM* host! Forcing splunkd restart " >&3
	docker exec -ti $1  /opt/splunk/bin/splunk restart > /dev/null >&1
	printf "${Green} Done! ${NC}\n" >&3
fi
return 0
} #end add_license_file()
#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------
reset_splunk_passwd () {
# $1=fullhostname
docker exec -ti $1 touch /opt/splunk/etc/.ui_login	#prevent first time changeme password screen
docker exec -ti $1 rm -fr /opt/splunk/etc/passwd	#remove any exisiting users (include admin)

#reset passwod to "$USERADMIN:$USERPASS"
CMD="docker exec -ti $1 /opt/splunk/bin/splunk edit user admin -password hello -roles admin -auth admin:changeme"
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
printf "${Purple}$1${NC}: > $CMD\n"

if ( contains "$CMD" "failed" ); then
   echo "\t->Trying default password "
   CMD="docker exec -ti $1 /opt/splunk/bin/splunk edit user admin -password changeme -roles admin -auth $USERADMIN:$USERPASS"
   printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
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

} #end pausing()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
restart_splunkd () {
#1: hostname 
#$2=b Execute in the background and dont wait to return.This will speed up eveything but load the CPU

if [ "$2" == "b" ]; then
	printf "\t->Restarting splunkd in the background " >&3
        CMD="docker exec -d $1 /opt/splunk/bin/splunk restart "
        OUT=`$CMD`; display_output "$OUT" "Starting splunk server daemon" "n" "3"
   	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
else
	printf "\t->Restarting splunkd. Please wait! " >&3
	CMD="docker exec -ti $1 /opt/splunk/bin/splunk restart "
        OUT=`$CMD`; display_output "$OUT" "Starting splunk server daemon" "n" "3"
   	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
fi

return 0
} #end restart_splunkd()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_output () {
#This function displays the output from CMD (docker command executed)
#$1  Actuall message after executing docker command
#$2  The expected "good" message returned if docker command executed ok. Otherwise everthing would be an error
#$3  if set; always force the output regardless if good or bad. Used for debugging
#$4  The loglevel (I/O redirect) to display the message (good for verbosity settings)

outputmsg=$1; OKmsg=$2; debug=$3; loglevel=$4
OKmsg=`echo $OKmsg| tr '[a-z]' '[A-Z]'`				#convert to upper case 
outputmsg=`echo $outputmsg| tr '[a-z]' '[A-Z]'`				#convert to upper case 
size=${#outputmsg}

if [ "$debug" == "d" ]; then
        printf "\n${LightRed}FORCED DEBUG> outputmsg:[%s] ${NC} \n" "$1"
fi
#also display returned msg if log level is high
printf "\n${LightRed}D5> outputmsg:[%s]${NC}\n" "$1"  >&5
#echo "resutlt[$1]"
        if ( contains "$outputmsg" "$OKmsg" ) || [ "$size" == 64 ] || [ "$size" == 0 ] ; then
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

hoststate=`docker ps -a --filter name=$1 --format "{{.Status}}" | awk '{print $1}'`
splunkstate=`docker exec -ti $1 /opt/splunk/bin/splunk status| $GREP splunkd| awk '{ print $3}'`
#printf "$D1:host_status(): host:[$1] hoststate:[$hoststate] splunkstate:[$splunkstate] ${NC}\n"

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
#---------------------------------------------------------------------------------------------------------------
make_lic_slave () {
# This function designated $hostname as license-slave using LM (License Manager)

hostname=$1; lm=$2
#echo "hostname[$hostname]  lm[$lm] _____________";exit
lm_ip=`docker port  $lm| awk '{print $3}'| cut -d":" -f1|head -1`
  if [ -n "$lm_ip" ]; then
        CMD="docker exec -ti $hostname /opt/splunk/bin/splunk edit licenser-localslave -master_uri https://$lm_ip:$MGMT_PORT -auth $USERADMIN:$USERPASS"
	printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
        printf "\t->Make a license-slave [license master:$lm] " >&3 ; display_output "$OUT" "object has been edited" "n" "3"
        fi
return
} 	#end make_lic_slave()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_host_exist () {		 ####### NOT USED YET ########
#$1=hostname (may include digits sequence)   $2=list_to_check_against
#Check if host exist in list; if not create it using basename only . The new host seq is returned by function

printf "$D1 ___________check_host_exist(): Parmeters passed hostname:[$1]   list:[$2]______________${NC}\n";
printf "${Purple}[$1] Host check >>> "
basename=$(printf '%s' "$1" | tr -d '0123456789')  #strip numbers
if [ -z "$2" ]; then
        printf "${LightPurple}Group is empty >>> creating host ${NC}\n";
        create_generic_splunk $basename 1
else if ( contains "$2" "$1" ); then
                printf "${Purple}Found in group. No action. ${NC}\n";
                return 0
        else
                printf "${LightPurple}Not found in group >>> Using basename to create next in sequence ${NC}\n";
                create_generic_splunk $basename 1
                num=`echo $?`    #last host seq number created
                return $num
        fi
fi
}  #end check_host_exist ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
show_all_containers () {
#This function diplays containers groups by role (role is determined using hostname ex: SH, DS, IDX, CM,...etc)

count=`docker ps -aq|wc -l`
if [ $count == 0 ]; then
	echo "No containers to list"
	return 0
fi
for id in $(docker ps -aq); do
    internal_ip=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $id`
    bind_ip=`docker inspect --format '{{ .HostConfig }}' $id| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
    hoststate=`docker ps -a --filter id=$id --format "{{.Status}}" | awk '{print $1}'`
    hostname=`docker ps -a --filter id=$id --format "{{.Names}}"`
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
    if ( contains "$splunkstate" "running" ); then
		splunkstate="${Green}$splunkstate${NC}"
    else
		splunkstate="${Red}$splunkstate${NC}"
    fi
    if ( contains "$hostname" "DEP" ); then
    	printf "${LightBlue}%-15s%-20b${NC} Splunkd:%-20b Bind:${LightBlue}%-10s${NC} Internal:${DarkGray}%-10s${NC}\n" "[$hostname]:" "$hoststate" "$splunkstate" "$bind_ip" "$internal_ip"
    elif ( contains "$hostname" "CM" ); then
    	printf "${LightBlue}%-15s%-20b${NC} Splunkd:%-20b Bind:${LightBlue}%-10s${NC} Internal:${DarkGray}%-10s${NC}\n" "[$hostname]:" "$hoststate" "$splunkstate" "$bind_ip" "$internal_ip"
   else
    	printf "${Purple}%-15s%-20b${NC} Splunkd:%-20b Bind:${LightGray}%-10s${NC} Internal:${DarkGray}%-10s${NC}\n" "[$hostname]:" "$hoststate" "$splunkstate" "$bind_ip" "$internal_ip"
   fi
done

echo  "count: $count"
return 0
}  #end  show_all_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
splunkd_status_all () {
#This functinos displays splunkd status on all containers

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
	if ( contains "$sh_cluster" "$prev_list" );  then
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
#This function creates custom login screen with some useful data (hostnam, IP, cluster lable)
vip=$1;  fullhostname=$2

#reset passwod to "$USERADMIN:$USERPASS"
CMD="docker exec -ti $fullhostname touch /opt/splunk/etc/.ui_login"      #prevent first time changeme password screen
OUT=`$CMD`;   #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
CMD="docker exec -ti $fullhostname rm -fr /opt/splunk/etc/passwd"        #remove any exisiting users (include admin)
OUT=`$CMD`;   #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
CMD="docker exec -ti $fullhostname /opt/splunk/bin/splunk edit user admin -password $USERPASS -roles $USERADMIN -auth admin:changeme"
OUT=`$CMD`;   display_output "$OUT" "ser admin edited" "n" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4

if ( contains "$CMD" "failed" ); then
        echo "Trying default password"
   #     docker exec -ti $fullhostname rm -fr /opt/splunk/etc/passwd        #remove any exisiting users (include admin)
        CMD="docker exec -ti $fullhostname touch /opt/splunk/etc/.ui_login"      #prevent first time changeme password screen
	OUT=`$CMD` ; display_output "$OUT" "ser admin edited" "n" "5"
	#printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5

        CMD="/opt/splunk/bin/splunk edit user $USERADMIN -password changeme -roles admin -auth $USERADMIN:$USERPASS"
	OUT=`$CMD` ; #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
	display_output "$OUT" "ser admin edited" "n" "5"
	#printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
fi

#set home screen banner in web.conf
hosttxt=`echo $fullhostname| $GREP -Po '\d+(?!.*\d)'  `        #extract string portion
hostnum=`echo $fullhostname| $GREP -Po '\d+(?!.*\d)'  `        #extract digits portion

container_ip=`docker inspect $fullhostname| $GREP IPAddress |$GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1  ` 
#cluster_label=`docker exec -ti $fullhostname $GREP cluster_label /opt/splunk/etc/system/local/server.conf | awk '{print $3}' `
cluster_label=`cat $PROJ_DIR/web.conf.tmp | $GREP -Po 'cluster.* (.*_LABEL)'| cut -d">" -f3`
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
printf "\t->Customizing web.conf!${Green} Done!${NC}\n" >&3 

return 0
}  #end custom_login_screen ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
assign_server_role () {		 ####### NOT USED YET ########
name=$1; role=$2
	
echo "localhost,"$name","$name","$name","$role",,,,," >  $MOUNTPOINT/$name/etc/apps/splunk_management_console/lookups/assets.csv
#dmc_group_indexer
#dmc_group_license_master
#dmc_group_search_head
#dmc_group_kv_store
return 0
}
#---------------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------
create_single_splunkhost () {
#This function creates single splunk container using $vip and $hostname
#inputs: $1: container's IP to use (nated IP aka as bind IP)
#	 $2: fullhostname:  container name (may include site and host number sequence)
#output: -create single host. will not prompt user for any input data
#	 -reset password and setup splunk's login screen
#        -configure container's OS related items if needed
START1=$(date +%s);
	vip=$1  fullhostname=$2
	fullhostname=`echo $fullhostname| tr -d '[[:space:]]'`	#trim whitespace if they exist

	check_load		#throttle back if high load

	#echo "fullhostname[$fullhostname]"
	#rm -fr $MOUNTPOINT/$fullhostname
	mkdir -m 777 -p $MOUNTPOINT/$fullhostname

        CMD="docker run -d --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER  -p $vip:$SPLUNKWEB_PORT:$SPLUNKWEB_PORT -p $vip:$MGMT_PORT:$MGMT_PORT -p $vip:$SSHD_PORT:$SSHD_PORT -p $vip:$KV_PORT:$KV_PORT -p $vip:$IDX_PORT:$IDX_PORT -p $vip:$REPL_PORT:$REPL_PORT --env SPLUNK_START_ARGS="--accept-license" --env SPLUNK_ENABLE_LISTEN=$IDX_PORT --env SPLUNK_SERVER_NAME=$fullhostname --env SPLUNK_SERVER_IP=$vip $SPLUNK_IMAGE"
        
	printf "[${Purple}$fullhostname${NC}:${DarkGray}$vip${NC}] ${LightBlue}Creating new splunk docker container ${NC} " 
	OUT=`$CMD` ; display_output "$OUT" "Error" "" "2"
	#CMD=`echo $CMD | sed 's/\t//g' `; 
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	#echo_logline "[${Purple}$fullhostname${NC}:${Cyan}$vip${NC}] Creating new splunk container..." >> ${LOGFILE}
	
	if [ "$os" == "Darwin" ]; then
		pausing "30"
	else
		pausing "15"
	fi
        #set home screen banner in web.conf & change default admin password
	printf "\t->Splunk initiliazation (pass change, licenses, login screen)..." >&3
	custom_login_screen "$vip" "$fullhostname"

	add_license_file $fullhostname

	#Misc OS stuff
        CMD=`docker cp $PROJ_DIR/screenfetch/screenfetch  $fullhostname:/usr/local/bin`
        CMD=`docker exec -ti $fullhostname bash -c "echo screenfetch >> /root/.bashrc"`		#cool ssh login banner
        CMD=`docker cp $PROJ_DIR/containers.bashrc $fullhostname:/root/.bashrc`
        #install sutff you will need in  background
        CMD=`docker exec -it $fullhostname apt-get update > /dev/null >&1`
        CMD=`docker exec -it $fullhostname apt-get install -y vim net-tools telnet dnsutils > /dev/null >&1`
        #docker exec -it $fullhostname apt-get install -y  net-tools > /dev/null >&1

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
	killall -HUP dnsmasq	#must referesh to read $HOSTFILE file
fi

return 0

}  #end create_single_splunkhost ()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
create_generic_splunk () {
#This function creates generic splunk containers. Role is assigned later
#inputs: $1:basehostname: (ex IDX, SH,HF) just the base (no numbers)
#	 $2:hostcount:     how many containers to create from this host type (ie name)
#outputs: $gLIST:  global var contains the list of hostname just got created
#	  $host_num :  last host number sequence just got created
#	-calcuate host number sequence
#	 -calculate next IP sequence (octet4)

count=0;starting=0; ending=0;basename=$BASEHOSTNAME; basesite=$3; octet4=0
gLIST=""   #build global list of hosts created by this session. Used somewhere else

#Another method to figure out the starting octet4 
# OCTET4FILE=`iptables -t nat -L |$GREP DNAT | awk '{print $5}'  | sort -u|tail -1|cut -d"." -f4`
#printf "$D1 _________create_generic_splunk():  basename[$1]  hostcount[$2]  site[$3]__________${NC}\n"

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
if [ -z "$last_host_num" ]; then    					#no previouse hosts with this name exists
        printf "\n${DarkGray}[$basename] New basename. ${NC}" >&3
	starting=1
        ending=$count
	last_host_num=0
else
       	starting=`expr $last_host_num + 1`
       	ending=`expr $starting + $count - 1`
       	printf "${DarkGray}Last hostname created:${NC}[${Green}$basename${NC}${Purple}$last_host_num${NC}] " >&3
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
printf "${DarkGray}Next sequence:${NC} [${Purple}$basename${Yellow}$startx${NC} --> ${Purple}$basename${Yellow}$endx${NC}]\n"  >&3

#--generate fullhostname (w/ seq numbers) and VIP------------------------

#--------Find last IP used. This is not hostname or site dependant-------
base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `;  #base_ip=$base_ip"."

#get last octet4 used ----
if [ $(docker ps -aq | wc -l) = 0 ]; then
        last_used_octet4=`echo $START_ALIAS | cut -d"." -f4 `
        last_ip_used="$base_ip.$start_octet4"
        #printf "DEBBUG: No hosts exists [will start@$last_ip_used][last_octet4:$last_used_octet4]\n";

else    #Find last container created IP
        last_ip_used=`docker inspect --format '{{ .HostConfig }}' $(docker ps -aql)|$GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
        last_used_octet4=`echo $last_ip_used |cut -d"." -f4`
        #printf "DEBUGG: Some hosts exists [last used:$last_ip_used][last_octet4:$last_used_octet4]\n";
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
	#printf "$D1:creat_generic_linux():fulhostname:[$fullhostname] vip:[$vip] basename:[$basename] count[$count] ${NC}\n";
	
	create_single_splunkhost $vip $fullhostname
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
#inputs: $1: pass all compnents (any order) needed and how many to create. The names the counts will be extracted
#example : create_single_idxc "$site-IDX:$IDXcount $cm:1 $lm:1"
#outputs: -adjust hostname with sitename if used
#	  -always convert hostnames to upper case (to avoid lookup/compair issues)
#	  -create single deployer and as many SH hosts required
#	  -if param $1 is "AUTO" skip all user prompts and create standarad cluster 3SH/1DEP
#-----------------------------------------------------------------------------------------------------
#$1 AUTO or MANUAL mode
if [ "$1" == "AUTO" ]; then  mode="AUTO"; else mode="MANUAL"; fi

server_list=""    #used by STEP#3
START1=$(date +%s);

#Extract parms from $1, if not we will prompt user later
lm=`echo $1| $GREP -Po '(\s*\w*-*LM\d+)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
cm=`echo $1| $GREP -Po '(\s*\w*-*CM\d+)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
DEPname=`echo $1| $GREP -Po '(\s*\w*-*DEP)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
DEPcount=`echo $1| $GREP -Po '(\s*\w*-*DEP):\K(\d+)'| tr -d '[[:space:]]' `
SHname=`echo $1| $GREP -Po '(\s*\w*-*SH)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' ` 
SHcount=`echo $1| $GREP -Po '(\s*\w*-*SH):\K(\d+)'| tr -d '[[:space:]]' `

#generate all global lists
dep_list=`docker ps -a --filter name="$DEPname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
sh_list=`docker ps -a --filter name="$SHname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
lm_list=`docker ps -a --filter name="LM|lm" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'` 
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'` 

printf "${LightBlue}___________ Creating hosts ____________________________________________________${NC}\n"
if [ "$1" == "AUTO" ]; then
	#echo "- $DEPname($DEPcount)  $LMname($LMcount)  $CMname($CMcount)  $SHname($SHount)"
        DEPname="DEP"; DEPcount="1"; SHname="SH"; SHcount="$STD_SHC_COUNT"
        create_generic_splunk "$DEPname" "$DEPcount" ; dep="$gLIST"
	if [ -n "$lm" ]; then make_lic_slave "$dep" "$lm"; fi
        create_generic_splunk "$SHname" "$SHcount" ; members_list="$gLIST"
else
	#Erro checking (values should already have been passed at this point)
        if [ -z "$DEPname" ] || [ -z "$DEPcount" ]; then 
		DEPcount=1
		read -p "DEP basename (default DEP)> " DEPname ;
        	DEPname=`echo $DEPname| tr '[a-z]' '[A-Z]'` 
        	if [ -z "$DEPname" ]; then DEPname="DEP"; fi
	fi
        if [ -z "$SHname" ] || [ -z "$SHcount" ]; then 
		read -p "SH basename (default SH)> " SHname ;
        	SHname=`echo $SHname| tr '[a-z]' '[A-Z]'` 
                if [ -z "$SHname" ]; then SHname="SH"; fi
		read -p "How many SH's (default $STD_SHC_COUNT)>  " SHcount
                if [ -z "$SHcount" ]; then SHcount="$STD_SHC_COUNT"; fi
	fi
        
	if [ -z "$lm" ]; then read -p "LM to use (optional) [$lm_list]> " lm ; fi
        if [ -z "$cm" ]; then read -p "CM to use (optional, used for auto discovery) [$cm_list]> " cm ; fi
	cm=`echo $cm| tr '[a-z]' '[A-Z]'`
	lm=`echo $lm| tr '[a-z]' '[A-Z]'`

        create_generic_splunk "$DEPname" "$DEPcount" ; dep="$gLIST"
	if [ -n "$lm" ]; then make_lic_slave "$dep" "$lm"; fi
        create_generic_splunk "$SHname" "$SHcount" ; members_list="$gLIST"
fi
printf "${LightBlue}___________ Finsihed creating hosts ___________________________________________${NC}\n" 

printf "${BrownOrange}[$mode]>>Building SHCluster: using LM:[$lm] CM:[$cm] DEP:[$DEPname:($DEPcount)] SHC:[$SHname:($SHcount)]${NC}\n"

printf "${LightBlue}___________ Starting STEP#1 (deployer configuration) ____________________________${NC} \n" >&3
## from this point on all hosts should be created and ready. Next steps are SHCluster configurations ##########
#DEPLOYER CONFIURATION: (create [shclustering] stanza; set SecretKey and restart) -----
printf "${DarkGray}Configuring SHC with created hosts: DEPLOYER[$dep]  MEMBERS[$members_list] ${NC}\n" >&3
 
printf "[${Purple}$dep${NC}]${LightBlue} Configuring Deployer ... ${NC}\n"
bind_ip_dep=`docker inspect --format '{{ .HostConfig }}' $dep| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`

#cluster_label=`cat web.conf.tmp | $GREP -Po 'cluster.* (.*_LABEL)'| cut -d">" -f3`
txt="\n #-----Modified by Docker Management script ----\n [shclustering]\n pass4SymmKey = $MYSECRET \n shcluster_label = $SHCLUSTERLABEL\n"
#printf "%b" "$txt" >> $MOUNTPOINT/$dep/etc/system/local/server.conf	#cheeze fix!
printf "%b" "$txt" > server.conf.append
CMD="docker cp server.conf.append $dep:/tmp/server.conf.append"; OUT=`$CMD`
CMD=`docker exec -ti $dep  bash -c "cat /tmp/server.conf.append >> /opt/splunk/etc/system/local/server.conf" `; #OUT=`$CMD`

printf "\t->Adding stanza [shclustering] to server.conf!" >&3 ; display_output "$OUT" "" "n" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4

if [ -n "$lm" ]; then make_lic_slave "$dep" "$lm"; fi
restart_splunkd "$dep"
printf "${LightBlue}___________ Finshed STEP#1 ____________________________________________________${NC}\n" >&3

printf "${LightBlue}___________ Starting STEP#2 (SH cluster members configurations) _______________${NC}\n" >&3
#printf "$D1:create_single_shc():After members_list loop> parm2:[$2] members_list:[$members_list] sh_list:[$sh_list]${NC}\n"
for i in $members_list ; do
	check_load	#throttle during SHC build
 	printf "[${Purple}$i${NC}]${LightBlue} Making cluster memeber...${NC}\n"
	bind_ip_sh=`docker inspect --format '{{ .HostConfig }}' $i| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
        bind_ip_sh=`docker inspect --format '{{ .HostConfig }}' $i| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`

	CMD="docker exec -ti $i /opt/splunk/bin/splunk init shcluster-config -auth $USERADMIN:$USERPASS -mgmt_uri https://$bind_ip_sh:$MGMT_PORT -replication_port $REPL_PORT -replication_factor $RFACTOR -register_replication_address $bind_ip_sh -conf_deploy_fetch_url https://$bind_ip_dep:$MGMT_PORT -secret $MYSECRET"
	OUT=`$CMD`
	OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
	printf "\t->Initiating shcluster-config " >&3 ; display_output "$OUT" "clustering has been initialized" "n" "3"
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	
	#configure search peers for idx auto discovery
	if [ -n "$cm" ]; then
		cm_ip=`docker port  $cm| awk '{print $3}'| cut -d":" -f1|head -1`
        	CMD="docker exec -ti $i /opt/splunk/bin/splunk edit cluster-config -mode searchhead -master_uri https://$cm_ip:$MGMT_PORT -secret $MYSECRET -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
		printf "\t->Integrating with CM (for idx auto discovery) [CM:$cm] " >&3 ; display_output "$OUT" "property has been edited" "n" "3"
		printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
        fi
	#adding as license slave
	if [ -n "$lm" ]; then 
		make_lic_slave "$i" "$lm"; 
	fi
	restart_splunkd "$i" "b"
	#assign_server_role "$i" "dmc_group_search_head"
	server_list="$server_list""https://$bind_ip_sh:$MGMT_PORT,"   #used by STEP#3

done
server_list=`echo ${server_list%?}`  # remove last comma in string
#printf "$D1 ___________create_single_shc(): server_list:[$server_list]________${NC}\n"
printf "${LightBlue}___________ Finished STEP#2 ___________________________________________________${NC}\n" >&3
 
printf "${LightBlue}___________ Starting STEP#3 (configuring captain) ______________________________${NC}\n" >&3
printf "[${Purple}$i${NC}]${LightBlue} Configuring as Captain (last SH created)...${NC}\n"

restart_splunkd "$i"  #last SH (captain) may not be ready yet, so force restart again

CMD="docker exec -ti $i /opt/splunk/bin/splunk bootstrap shcluster-captain -servers_list "$server_list" -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "\t->Captain bootstraping (may take time) " >&3 ; display_output "$OUT" "Successfully" "n" "3"
printf " ${DarkGray}CMD:[$CMD]${NC}\n" >&4
printf "${LightBlue}___________ Finshed STEP#3 ____________________________________________________${NC}\n" >&3

printf "${LightBlue}___________ Starting STEP#4 (Seach Head cluster status) __________________________________${NC}\n" >&3
printf "[${Purple}$i${NC}]${LightBlue} Checking SHC status (on captian)...${NC}"

CMD="docker exec -ti $i /opt/splunk/bin/splunk show shcluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
display_output "$OUT" "Captain" "n" "2"
printf " ${DarkGray}CMD:[$CMD]${NC}\n" >&4 
printf "${LightBlue}___________ Finshed STEP#4 (cluster status) ___________________________________${NC}\n" >&3

END=$(date +%s);
TIME=`echo $((END-START1)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Execution time for create_single_shc():  [$TIME] ${NC}\n\n"

return 0
}   #create_single_shc()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_single_idxc () {
#This function creates single IDX cluster. Details are parsed from $1
#$1 AUTO or MANUAL mode

if [ "$1" == "AUTO" ]; then  mode="AUTO"; else mode="MANUAL"; fi

START2=$(date +%s);
#$1 CMbasename:count   $2 IDXbasename:count  $3 LMbasename:count
#"$site01-CM:1"; "$site02-IDX:2" "$site03-LM:3"

#Extract values from $1 if passed to us!
lm=`echo $1| $GREP -Po '(\s*\w*-*LM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
cm=`echo $1| $GREP -Po '(\s*\w*-*CM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
IDXname=`echo $1| $GREP -Po '(\s*\w*-*IDX)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
IDXcount=`echo $1| $GREP -Po '(\s*\w*-*IDX):\K(\d+)'| tr -d '[[:space:]]' `
CMname=`echo $1| $GREP -Po '(\s*\w*-*CM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
CMcount=`echo $1| $GREP -Po '(\s*\w*-*CM):\K(\d+)'| tr -d '[[:space:]]' `

cm_list=`docker ps -a --filter name="$CMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
lm_list=`docker ps -a --filter name="$LMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'` #global list
idx_list=`docker ps -a --filter name="$IDXname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`

printf "${LightBlue}___________ Creating hosts ____________________________________________________${NC}\n"
if [ "$1" == "AUTO" ]; then
	#CM and LM should be passerd to function in AUTO mode
	CMname="CM";  IDXname="IDX"; IDXcount="$STD_IDXC_COUNT"
        #create_generic_splunk "$LMname" "1" ; lm="$gLIST"
        create_generic_splunk "$CMname" "1" ; cm="$gLIST"
	if [ -n "$lm" ]; then make_lic_slave "$cm" "$lm"; fi
        create_generic_splunk "$IDXname" "$IDXcount" ; members_list="$gLIST"
else
	#if CMname and LMname passed to function; user will NOT be prompted
	if [ -z "$IDXname" ] || [ -z "$IDXcount" ]; then read -p "IDX basename> " IDXname ; read -p "IDX count> " IDXcount; fi
	if [ -z "$lm" ]; then read -p "Enter LM hostname to use [$lm_list]> " lm; fi
	if [ -z "$cm" ]; then read -p "Enter CM hostname to use [$lm_list]> " lm; fi
	#CMname=`echo $CMname| tr '[a-z]' '[A-Z]'`
	IDXname=`echo $IDXname| tr '[a-z]' '[A-Z]'`
	lm=`echo $lm| tr '[a-z]' '[A-Z]'`
 	#create_generic_splunk "$CMname" "$CMcount" ; cm="$gLIST"
	if [ -n "$lm" ]; then make_lic_slave "$cm" "$lm"; fi
        create_generic_splunk "$IDXname" "$IDXcount" ; members_list="$gLIST"

fi
printf "${LightBlue}___________ Finished creating hosts ___________________________________________${NC}\n"

printf "${BrownOrange}[$mode]>>Building IDXCluster: using LM:[$lm] CM:[$cm] IDXC:[$IDXname:($IDXcount)]${NC}\n"

printf "${LightBlue}____________ Starting STEP#1 (Configuring IDX Cluster Master) _____________________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${LightBlue} Configuring Cluster Master... ${NC}\n"
bind_ip_cm=`docker inspect --format '{{ .HostConfig }}' $cm| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`

CMD="docker exec $cm /opt/splunk/bin/splunk edit cluster-config  -mode master -replication_factor $RFACTOR -search_factor $SFACTOR -secret $MYSECRET -cluster_label $IDXCLUSTERLABEL -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 
printf "\t->Configuring CM [RF:$RFACTOR SF:$SFACTOR] and cluster label[$IDXCLUSTERLABEL] " >&3 ; display_output "$OUT" "property has been edited" "n" "3"

restart_splunkd "$cm"
#assign_server_role "$i" ""
printf "${LightBlue}____________ Finished STEP#1 __________________________________________________${NC}\n" >&3

printf "${LightBlue}____________ Starting STEP#2 (configuring IDXC nodes) _________________${NC}\n" >&3
for i in $members_list ; do
	check_load	#throttle during IDXC build
	printf "[${Purple}$i${NC}]${LightBlue} Making search peer... ${NC}\n"
        bind_ip_idx=`docker inspect --format '{{ .HostConfig }}' $i| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`

        CMD="docker exec $i /opt/splunk/bin/splunk edit cluster-config -mode slave -master_uri https://$bind_ip_cm:$MGMT_PORT -replication_port $REPL_PORT -register_replication_address $bind_ip_idx -secret $MYSECRET -auth $USERADMIN:$USERPASS "
	OUT=`$CMD`
	OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
	printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
	printf "\t->Make a cluster member " >&3 ; display_output "$OUT" "property has been edited" "n" "3"

	#LM should not be license slave to itself
	if [ -n "$lm" ]; then 
		make_lic_slave "$i" "$lm"
	fi
	restart_splunkd "$i" "b"
	#assign_server_role "$i" "dmc_group_indexer"
done
printf "${LightBlue}____________ Finished STEP#2 __________________________________________________${NC}\n" >&3

printf "${LightBlue}____________ Starting STEP#3 (IDXC status) _________________________________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${LightBlue} Checking IDXC status...${NC}"
CMD="docker exec -ti $cm /opt/splunk/bin/splunk show cluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`; display_output "$OUT" "Replication factor" "n" "2"
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
printf "${LightBlue}____________ Finished STEP#3 __________________________________________________${NC}\n" >&3

END=$(date +%s);
TIME=`echo $((END-START2)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Execution time for create_single_idxc():  [$TIME] ${NC}\n\n" 

return 0
}  #end create_single_idxc()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
build_single_site () {
#This function will build 1 CM and 1 LM then calls create_generic_splunk()
# Expected paramaters: "$cm $lm $site-IDX:$IDXcount $site-SH:$SHcount $site-DEP:1"
#$1 AUTO or MANUAL mode

printf "Single-site cluster\n"
#extract these values from $1 if passed to us!
lm=`echo $1| $GREP -Po '(\s*\w*-*LM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
cm=`echo $1| $GREP -Po '(\s*\w*-*CM\d+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
CMname=`echo $1| $GREP -Po '(\s*\w*-*CM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
CMcount=`echo $1| $GREP -Po '(\s*\w*-*CM):\K(\d+)'| tr -d '[[:space:]]' `

#if CMname and LMname passed to function; user will NOT be prompted
#if [ -z "$lm" ]; then read -p "Enter LM hostname to use [$lm_list]> " lm; fi
#if [ -z "$CMname" ] || [ -z "$CMcount" ]; then read -p "CM basename> " CMname ; read -p "CM count> " CMcount; fi
#if [ -z "$IDXname" ] || [ -z "$IDXcount" ]; then read -p "IDX basename> " IDXname ; read -p "IDX count> " IDXcount; fi
#if [ -z "$DEPname" ] || [ -z "$DEPcount" ]; then read -p "DEP basename> " DEPname ; read -p "DEP count> " DEPcount; fi
#if [ -z "$SHname" ] || [ -z "$SHcount" ]; then read -p "SH basename> " SHname ; read -p "SH count> " SHcount; fi

#cm_list=`docker ps -a --filter name="$CMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`

if [ "$1" == "AUTO" ]; then  
	mode="AUTO"
	IDXcount="$STD_IDXC_COUNT"
	SHcount="$STD_SHC_COUNT"
	site="SITE01"
else
	mode="MANUAL"
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
SHCLUSTERLABEL="$site""_LABEL"
IDXCLUSTERLABEL="$site""_LABEL"
printf "${Yellow}[$mode] Building single-site ($site)...${NC}\n"
printf "Creating basic services for this site (LM,CM)...\n"
create_generic_splunk "$site-LM" "1" ; lm=$gLIST
create_generic_splunk "$site-CM" "1" ; cm=$gLIST

create_single_idxc "$site-IDX:$IDXcount $cm:1 $lm"
create_single_shc "$site-SH:$SHcount $site-DEP:1 $cm $lm"

return 0
} #build_single_site
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
build_multi_site_cluster () {
#This function creates site-2-site cluster
#http://docs.splunk.com/Documentation/Splunk/6.4.3/Indexer/Migratetomultisite

START3=$(date +%s);

s=""; SitesStr=""     			#used with "splunk edit cluster-config" on CM
SITEnames=""

printf "One DEP server per SHC will be automatically created.\n"
printf "One CM server will be automtically created for the entire site-2-site cluster.\n\n"

if [ "$1" != "AUTO" ]; then
	read -p "How many sites (locations) to build (default 3)?  " count
	if [ -z "$count" ]; then count=3; fi
	mode="MANUAL"
else
	count=3;
	mode="AUTO"
fi
for (( i=1; i <= ${count}; i++));  
do
	if [ "$1" != "AUTO" ]; then
		read -p "Enter site$i fullname (default SITE0$i)>  " site
		if [ -z "$site" ]; then site="site0$i"; fi
		read -p "How many IDX's (default $STD_IDXC_COUNT)>  " IDXcount
		if [ -z "$IDXcount" ]; then IDXcount="$STD_IDXC_COUNT"; fi
		read -p "How many SH's (default $STD_SHC_COUNT)>  " SHcount
                if [ -z "$SHcount" ]; then SHcount="$STD_SHC_COUNT"; fi

		SITEnames="$SITEnames ""$site"
        	s="site""$i"
        	SitesStr="$SitesStr""$s,"   		#spaces causes error with -available_sites for some reason
        	#echo "$s [$SitesStr]"
		mode="MANUAL"
	else
		SITEnames="STL LON HKG"
        	SitesStr="site1,site2,site3,"   		
		mode="AUTO"
	fi
done

#SitesStr=`echo -n $SitesStr | head -c -1`  		#remove last comma
SitesStr=`echo ${SitesStr%?}`  		#remove last comma

SITEnames=`echo $SITEnames| tr '[a-z]' '[A-Z]' `	#upper case
siteone=`echo $SITEnames|awk '{print $1}'`		#where CM,LM resides

#echo "list[$SITEnames]   SitesStr[$SitesStr] CM[$cm] siteone[$siteone]"

if [ "$1" != "AUTO" ]; then
	read -p "site-to-site cluster must have one CM. Enter CM fullname (default $siteone-CM01)> " cm
	cm=`echo $cm| tr '[a-z]' '[A-Z]' `
	if [ -z "$cm" ]; then cm="$siteone-CM01"; fi
	mode="MANUAL"
else
	cm="$siteone-CM01"
	IDXcount="$STD_IDXC_COUNT"
	SHcount="$STD_SHC_COUNT"
	mode="AUTO"
fi

SHCLUSTERLABEL="$site""_LABEL"
IDXCLUSTERLABEL="$site""_LABEL"

printf "\n\n${BoldYellowBlueBackground}[$mode] Building site-to-site cluster...${NC}\n"
printf "\n\n${Yellow}Creating cluster basic services [only in $siteone]${NC}\n"
create_generic_splunk "$siteone-LM" "1" ; lm=$gLIST
create_generic_splunk "$siteone-CM" "1" ; cm=$gLIST

i=0
for site  in $SITEnames; do
	let i=i+1
	printf "\n${BoldYellowBlueBackground}Building site$i >> $site ${NC}\n"
	#create_single_idxc "$cm $lm $site-IDX:$IDXcount $site-SH:$SHcount $site-DEP:1"
	create_single_idxc "$site-IDX:$IDXcount $cm $lm"
	create_single_shc "$site-SH:$SHcount $site-DEP:1 $cm $lm"
done

idx_list=`docker ps -a --filter name="IDX|idx" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
sh_list=`docker ps -a --filter name="SH|sh" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
site_list=`echo $cm_list | sed 's/\-[a-zA-Z0-9]*//g' `

printf "${BoldYellowBlueBackground}Migrating existing IDXCs & SHCs to site-2-site cluster: LM[$lm] CM[$cm] sites[$SITEnames] SitesStr[$SitesStr]${NC}\n"

#echo "list of sites[$SITEnames]   cm[$cm]"
cm_ip=`docker port $cm| awk '{print $3}'| cut -d":" -f1|head -1 `

printf "${Cyan}____________ Starting STEP#1 (Configuring one CM for all locations) _____________________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${Cyan} Configuring Cluster Master... ${NC}\n"

CMD="docker exec -ti $cm /opt/splunk/bin/splunk edit cluster-config -mode master -multisite true -available_sites $SitesStr -site site1 -site_replication_factor origin:2,total:3 -site_search_factor origin:1,total:2 -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
printf "\t->Setting multisite to true... " >&3 ; display_output "$OUT" "property has been edited" "n" "3"

CMD="docker exec -ti $cm /opt/splunk/bin/splunk enable maintenance-mode --answer-yes -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
printf "\t->Enabling maintenance-mode... " >&3 ; display_output "$OUT" "aintenance mode set" "n" "3"

restart_splunkd "$cm"
printf "${Cyan}____________ Finished STEP#1 __________________________________________________${NC}\n" >&3

seq=1
printf "${Cyan}____________ Starting STEP#2 (Configuring search peers in [site:"$site""$seq" location:$str]) _____________________${NC}\n" >&3

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
		printf "\t->Configuring mutltisite clustering for [site:$site location:$str] " >&3 
		display_output "$OUT" "property has been edited" "n" "3"
		restart_splunkd "$i" "b"
	done
printf "${Cyan}____________ Finished STEP#2 __________________________________________________${NC}\n" >&3

printf "${Cyan}____________ Starting STEP#3 (Configuring SHs in [site:$site location:$str]) _____________________${NC}\n" >&3
	for i in $site_sh_list; do
		printf "[${Purple}$i${NC}]${Cyan} Migrating Search Head... ${NC}\n"
	    	CMD="docker exec -ti $i /opt/splunk/bin/splunk edit cluster-master https://$cm_ip:$MGMT_PORT -site $site -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
                OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
		printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
		printf "\t->Pointing to CM[$cm] for [site:$site location:$str]" >&3 
		display_output "$OUT" "property has been edited" "n" "3"
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
printf "\t->Disabling maintenance-mode..." >&3 ; display_output "$OUT" "No longer" "n" "3"
#restart_splunkd "$i"
printf "${Cyan}____________ Finished STEP#4 __________________________________________________${NC}\n" >&3

END=$(date +%s);
TIME=`echo $((END-START3)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Execution time for build_multi_site_cluster():  [$TIME] ${NC}\n\n"

return 0
}  #build_multi_site_cluster ()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_menu2 () {
	clear
	printf "${Green}Docker Splunk Infrastructure Managment -> Clustering Menu:${NC}${LightBlue}[$dockerinfo]${NC}\n"
	echo "=====================================================================================[OS:$os][loglevel:$loglevel]=="
	printf "${Yellow}B${NC}) Go back to MAIN menu\n\n"

	printf "${Purple}AUTO BUILDS (fixed counts R3/S2 1-CM 1-DEP 3-SHC 1-CM 3-IDXC):\n"
        printf "${Purple}1${NC}) Create Stand-alone Index Cluster (IDXC)\n";
        printf "${Purple}2${NC}) Create Stand-alone Search Head Cluster (SHC)\n"
        printf "${Purple}3${NC}) Build Single-site Cluster\n"
        printf "${Purple}4${NC}) Build Multi-site Cluster (3 sites)${NC} \n";echo
	
	printf "${LightBlue}MANUAL BUILDS (specifiy base hostnames and counts)\n"
        printf "${LightBlue}5${NC}) Create Manual Stand-alone Index cluster (IDXC)\n";
	printf "${LightBlue}6${NC}) Create Maual Stand-alone Search Head Cluster (SHC)\n"
        printf "${LightBlue}7${NC}) Build Manul Single-site Cluster\n"
        printf "${LightBlue}8${NC}) Build Manul Multi-site Cluster${NC} \n";echo 
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

		1 ) create_single_idxc "AUTO"; read -p "Hit <ENTER> to continue..." ;;
                2 ) create_single_shc  "AUTO"; read -p "Hit <ENTER> to continue..." ;;
                3 ) build_single_site "AUTO"; read -p "Hit <ENTER> to continue..." ;;
                4 ) build_multi_site_cluster "AUTO"; read -p "Hit <ENTER> to continue..." ;;

                5 ) create_single_idxc; read -p "Hit <ENTER> to continue..." ;;
		6 ) create_single_shc; read -p "Hit <ENTER> to continue..." ;;
                7 ) build_single_site; read -p "Hit <ENTER> to continue..."  ;;
                8 ) build_multi_site_cluster; read -p "Hit <ENTER> to continue..."  ;;

		q|Q ) echo "Exit!" ;break ;;
                *) read -p "Hit <ENTER> to continue..." ;;
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
	printf "${Yellow}Docker Splunk Infrastructure Managment Main Menu:${NC}${LightBlue}[$dockerinfo]${NC}\n"
	echo "==================================================================================[OS:$os][loglevel:$loglevel]=="
	printf "${Red}C${NC}) CREATE containers ${DarkGray}[docker run ...]${NC}\n"
	printf "${Red}D${NC}) DELETE all containers ${DarkGray}[docker rm -f \$(docker ps -aq)]${NC}\n"
	printf "${Red}R${NC}) REMOVE all volumes to recover diskpace ${DarkGray}[docker volume rm \$(docker volume ls -qf 'dangling=true')]${NC}\n"
	echo
	printf "${Yellow}1${NC}) SHOW all containers details ${DarkGray}[custom view]${NC} \n"
	printf "${Yellow}2${NC}) START all stopped containers ${DarkGray}[docker start \$(docker ps -a --format \"{{.Names}}\")]${NC}\n"
	printf "${Yellow}3${NC}) STOP all running containers ${DarkGray}[docker stop \$(docker ps -aq)]${NC}\n"
	printf "${Yellow}4${NC}) Show hosts by hostname groups ${DarkGray}[works only if you followed the host naming rules]${NC}\n"
	echo
	printf "${LightBlue}5${NC}) RESET all splunk passwords [changeme --> $USERPASS] ${DarkGray}[splunkd must be running]${NC}\n"
	printf "${LightBlue}6${NC}) ADD splunk licenses ${DarkGray}[splunkd must be running]${NC}\n"
	printf "${LightBlue}7${NC}) Splunkd status ${DarkGray}[docker -exec -it hostname /opt/splunk/bin/splunk status]${NC}\n"
	printf "${LightBlue}8${NC}) Remove IP alises on the ethernet interface${NC}\n"
	printf "${LightBlue}9${NC}) RESTART all splunkd instances\n\n"
	printf "${Green}10${NC}) Clustering Menu \n"
	echo
return 0
}    #end display_menu()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------
### MAIN BEGINGS #####

#The following must start at the begining for the code since we use I/O redirection for logging
#--------------------
loglevel=2
maxloglevel=5 #The highest loglevel we use / allow to be displayed. 

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
#echo "1------[$opt][$OPTARG] [${loglevel}]-----"

#Start counting at 2 so that any increase to this will result in a minimum of file descriptor 3.  You should leave this alone.
#Start counting from 3 since 1 and 2 are standards (stdout/stderr).
for v in $(seq 3 $loglevel); do
    (( "$v" <= "$maxloglevel" )) && eval exec "$v>&2"  #Don't change anything higher than the maximum loglevel allowed.
done

#From the loglevel level one higher than requested, through the maximum;
for v in $(seq $(( loglevel+1 )) $maxloglevel ); do
    (( "$v" > "2" )) && eval exec "$v>/dev/null" #Redirect these to bitbucket, provided that they don't match stdout and stderr.
done
#------------------

#house keeping functions
check_shell
detect_os
setup_ip_aliases

while true;  
do
	dockerinfo=`docker info|head -5| tr '\n' ' '|sed 's/: /:/g'`
	display_menu 
	choice=""
	read -p "Select a number: " choice
       		case "$choice" in
		c|C) create_generic_splunk  ;; 
		d|D ) echo "Deleting all containers: " ; 
			docker rm -f $(docker ps -a --format "{{.Names}}");
			rm -fr $HOSTSFILE;;
		r|R ) echo "Removing all volumes (to recover diskspace): "; 
			#disk1=`df -kh /var/lib/docker/| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
			disk1=`df -kh $MOUNTPOINT| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
			docker volume rm $(docker volume ls -qf 'dangling=true') 
			rm -fr $MOUNTPOINT
			disk2=`df -kh $MOUNTPOINT| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
			freed=`expr $disk2 - $disk1`
			printf "Disk space freed [$freed] GB\n"
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

		q|Q ) echo "Exit!" ;break ;;
		#*) break ;;
	esac  #end case ---------------------------
	
	read -p "Hit <ENTER> to continue..."
	echo "------------------------------------------------------";echo

done  #end of while(true) loop
echo "Script terminated...!"

##### EOF #######


