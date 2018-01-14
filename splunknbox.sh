#!/bin/bash
#################################################################################
#	__VERSION: 4.5-14 $
#	__DATE: Sun Jan 14,2018 - 04:16:58PM -0600 $
#	__AUTHOR: mhassan2 <mhassan@splunk.com> $
#################################################################################

# Description:
#	This script is intended to enable you to create number of Splunk infrastructure
# 	elements on the fly. A perfect tool to setup a quick Splunk lab for training
# 	or testing purposes. https://github.com/mhassan2/splunk-n-box
#
# List of capabilities:
#	-Extensive Error and integrity checks
#	-Load control (throttling) if exceeds total vCPU
#	-Built-in dynamic host names and IP allocation
#	-Create and configure large number of Splunk hosts very fast
#	-Different logging levels (show docker commands executed)
#	-Complete multi and single site cluster builds including CM,LM,DMC and DEP servers
#	-Manual and auto modes (standard configurations)
#	-Modular design that can easily be converted to a higher-level language like python
#	-Custom login-screen (helpful for lab & Search Parties scenarios)
#	-Low resources requirements
#	-Eliminate the need to learn docker (but you should)
#	-OSX & Linux support
#	-Works with windows10 WSL (Windows Subsystem for Linux) Ubuntu bash.
#	-Automatic script upgrade (with version check).
#	-AWS EC2 aware
#
# Licenses:	Apache 2.0 https://www.apache.org/licenses/LICENSE-2.0
# Copyright [2017] [Mohamad Y. Hassan]

#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.
#
#
#Usage :  splunknbox -v[2 3 4 5 6]
#		v1-2 implied and cannot be changed
#		-v3	[default] show sub-steps under each host build
#		-v4	show remote CMD executed in docker container
#		-v5	more verbosity (debug)
#		-v6	even more verbosity (debug)
#################################################################################

#-------------Network stuff --------
ETH_OSX="lo0"			#default interface to use with OSX laptop (el captain)
ETH_LINUX="ens3"		#default interface to use with Linux server (Ubuntu 16.04

#-------------IP aliases --------
#LINUX is routed and hosts can be reached from anywhere in the network
#START_ALIAS_LINUX="192.168.1.100";  	END_ALIAS_LINUX="192.168.1.254"
START_ALIAS_LINUX="192.168.1.100";  	END_ALIAS_LINUX="192.168.1.250"

#OSX space will not be routed, and host reached from the laptop only
START_ALIAS_OSX="10.0.0.100";  		END_ALIAS_OSX="10.0.0.250"

DNSSERVER="192.168.1.19"		#if running dnsmasq. Set to docker-host machine IP
#---------------------------------
#----------PATHS-------------------
#Full PATH is dynamic based on OS type, see detect_os()

#The following are set in detect_os()
#MOUNTPOINT=
#ETH=
#GREP=
#-----------------------------------
#----------Images--------------------
#My builds posted on docker hub    -MyH
DEFAULT_SPLUNK_IMAGE="splunknbox/splunk_7.0.1"

#DEFAULT_SPLUNK_IMAGE="splunk/splunk"		#official image -recommended-
SPLUNK_DOCKER_HUB="registry.splunk.com"	#internal to splunk.Requires login

#Available splunk demos registry.splunk.com
REPO_DEMO_IMAGES="workshop-boss-of-the-soc demo-azure demo-dbconnect demo-pci demo-itsi demo-es demo-vmware demo-citrix demo-cisco demo-stream demo-pan demo-aws demo-ms demo-unix demo-fraud demo-oi demo-healthcare workshop-splunking-endpoint workshop-ransomware-splunklive-2017 demo-connected-cars workshop-elastic-stack-lab"
REPO_DEMO_IMAGES=$(echo "$REPO_DEMO_IMAGES" | tr " " "\n"|sort -u|tr "\n" " ")

#3rd party images will be renamed to 3rd-* after each docker pull
REPO_3RDPARTY_IMAGES="mysql oraclelinux sebp/elk sequenceiq/hadoop-docker caioquirino/docker-cloudera-quickstart"
REPO_3RDPARTY_IMAGES=$(echo "$REPO_3RDPARTY_IMAGES" | tr " " "\n"|sort -u|tr "\n" " ")


MYSQL_PORT="3306"
DOWNLOAD_TIMEOUT="480"	#how long before the progress_bar timeout (seconds)
#---------------------------------------
#----------Lunch & Learn stuff----------------
LL_APPS="splunk-datasets-add-on_10.tgz machine-learning-toolkit_210.tgz customer-search-party-app_10.tgz \
	splunk-enterprise-65-overview_13.tgz splunk-6x-dashboard-examples_60.tgz \
	splunk-common-information-model-cim_470.tgz eventgen.spl"
	#python-for-scientific-computing-for-linux-64-bit_12.tgz" #too large for github 63M
LL_DATASETS="http_status.csv tutorialdata.zip"
#---------------------------------------

#----------Cluster stuff----------------
MASTER_CONTAINER="MONITOR" 	#name of master container used to monitor ALL containers
BASEHOSTNAME="HOST"					#default hostname to create
CM_BASE="CM"
DMC_BASE="DMC"
LM_BASE="LM"
DEP_BASE="DEP"
IDX_BASE="IDX"
SH_BASE="SH"
HF_BASE="HF"
SPLUNKNET="splunk-net"				#default name for network (host-to-host comm)
#Splunk standard ports
SSHD_PORT="8022"					#in case we need to enable sshd, not recommended
SPLUNKWEB_PORT="8000"				#port splunkd is listing on
SPLUNKWEB_PORT_EXT="8000"			#port mapped during docker run (customer facing)
MGMT_PORT="8089"
#KV_PORT="8191"
RECV_PORT="9997"
REPL_PORT="9887"
HEC_PORT="8088"
APP_SERVER_PORT="8065"				#new to 6.5
APP_KEY_VALUE_PORT="8191"			#new to 6.5
USERADMIN="admin"
USERPASS="hello"

RFACTOR="3"							#default replication factor
SFACTOR="2"							#default search factor

SHCLUSTERLABEL="shcluster1"
IDXCLUSTERLABEL="idxcluster1"
LABEL="label1"
DEFAULT_SITES_NAMES="STL LON HKG"  	#used in auto-mode s-2-s

MYSECRET="mysecret"
STD_IDXC_COUNT="3"					#default IDXC count
STD_SHC_COUNT="3"					#default SHC count
DEP_SHC_COUNT="1"					#default DEP count
#------------------------------------------
#---------DIRECTORIES & Logs-----------------------------
LOGLEVEL=3
FILES_DIR="$PWD" 		#place anything needs to copy to container here
TMP_DIR="$PWD/tmp"	#used as scrach space
LOGS_DIR="$PWD/logs"		#store generated logs during run
CMDLOGBIN="$LOGS_DIR/splunknbox_bin.log"		#capture all docker cmds (with color)
CMDLOGTXT="$LOGS_DIR/splunknbox.log"			#capture all docker cmds (just ascii txt)
#LOGFILE="${0##*/}.log"   				#log file will be this_script_name.log
#SCREENLOGFILE="$LOGS_DIR/splunknbox_screens.log"  #capture all screen shots during execution
HOSTSFILE="$PWD/docker-hosts.dnsmasq"  	#local host file. optional if dns caching is used
SPLUNK_LIC_DIR="$PWD/splunk_licenses"		#place all your license file here
VOL_DIR="docker-volumes"	#volumes mount point.Full path is dynamic based on OS type
SPLUNK_APPS_DIR="$PWD/splunk_apps"
SPLUNK_DATASETS_DIR="$PWD/tutorial_datasets"
#-----------------------------------------
#--------Load control---------------------
MAXLOADTIME=10						#seconds increments for timer
MAXLOADAVG=4						#Not used
LOADFACTOR=3            			#allow (3 x cores) of load on docker-host
LOADFACTOR_OSX=1        			#allow (1 x cores) for the MAC (testing..)
#-----------------------------------------
#-------Misc------------------------------
GREP_OSX="/usr/local/bin/ggrep" 	#you MUST install Gnu grep on OSX
GREP_LINUX="/bin/grep"          	#default grep for Linux
PS4='$LINENO: '						#show line num when used bash -x ./script.sh
FLIPFLOP=0							#used to toggle color value in logline().Needs to be global
#Set the local splunkd path if you're running Splunk on this docker-host (ex laptop).
#Used in startup_checks() routine to detect local instance and kill it.
LOCAL_SPLUNKD="/opt/splunk/bin/splunk"  #don't run local splunkd instance on docker-host
LOW_MEM_THRESHOLD=6.0				#threshold of recommended free system memory in GB
DOCKER_MIN_VER=1.13.1				#min recommended docker version
#----------------------------------------
#--------COLORES ESCAPE CODES------------
#for i in `seq 1 100`; do printf "\033[48;5;${i}m${i} "; done
NC='\033[0m' # No Color
Black="\033[0;30m";             White="\033[1;37m"
Red="\033[0;31m";               LightRed="\033[1;31m"
Green="\033[0;32m";             LightGreen="\033[1;32m"
BrownOrange="\033[0;33m";       Yellow="\033[1;33m"
Blue="\033[0;34m";              LightBlue="\033[1;34m"
Purple="\033[0;35m";            LightPurple="\033[1;35m"
Cyan="\033[0;36m";              LightCyan="\033[1;36m"
LightGray="\033[0;37m";         DarkGray="\033[1;30m"
BlackOnGreen="\033[30;48;5;82m"
WhiteOnBurg="\033[30;48;5;88m"

BoldWhiteOnRed="\033[1;1;5;41m"
BoldWhiteOnGreen="\033[1;1;5;42m"
BoldWhiteOnYellow="\033[1;1;5;43m"
BoldWhiteOnBlue="\033[1;1;5;44m"
BoldWhiteOnPink="\033[1;1;5;45m"
BoldWhiteOnTurquoise="\033[1;1;5;46m"

BoldYellowOnBlue="\033[1;33;44m"
BoldYellowOnPurple="\033[1;33;44m"

DEFAULT_YES="\033[1;37mY\033[0m/n"
DEFAULT_NO="y/\033[1;37mN\033[0m"
#Emojis
ARROW_EMOJI="\xe2\x96\xb6"
ARROW_STOP_EMOJI="\xe2\x8f\xaf"
REPEAT_EMOJI="\xe2\x8f\xad"
CHECK_MARK_EMOJI="\xe2\x9c\x85"
OK_MARK_EMOJI="\xe2\x9c\x85"
OK_BUTTON_EMOJI="\xf0\x9f\x86\x97"
WARNING_EMOJI="\xe2\x9a\xa0\xef\xb8\x8f"
BULB_EMOJI="\xf0\x9f\x92\xa1"
DONT_ENTER_EMOJI="\xe2\x9b\x94"
DOLPHIN1_EMOJI="\xf0\x9f\x90\xb3"
DOLPHIN2_EMOJI="\xf0\x9f\x90\xac"
BATTERY_EMOJI="\xf0\x9f\x94\x8b"
OPTICALDISK_EMOJI="\xf0\x9f\x92\xbf"
YELLOWBOOK_EMOJI="\xf0\x9f\x93\x92"
YELLOW_LEFTHAND_EMOJI="\xf0\x9f\x91\x89"

#---------------------------------------


#**** Let the fun begin.I will see you 4000+ lines later! ***

#Log level is controlled with I/O redirection. Must be first thing executed in a bash script
# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
#exec >> >(tee -i $SCREENLOGFILE)
exec 2>&1

#---------------------------------------------------------------------------------------------------------------
function catimg() {

#this is cut & paste from imgcat package

# tmux requires unrecognized OSC sequences to be wrapped with DCS tmux;
# <sequence> ST, and for all ESCs in <sequence> to be replaced with ESC ESC. It
# only accepts ESC backslash for ST.
function print_osc() {
    if [[ $TERM == screen* ]] ; then
        printf "\033Ptmux;\033\033]"
    else
        printf "\033]"
    fi
}

# More of the tmux workaround described above.
function print_st() {
    if [[ $TERM == screen* ]] ; then
        printf "\a\033\\"
    else
        printf "\a"
    fi
}

# print_image filename inline base64contents print_filename
#   filename: Filename to convey to client
#   inline: 0 or 1
#   base64contents: Base64-encoded contents
#   print_filename: If non-empty, print the filename
#                   before outputting the image
function print_image() {
    print_osc
    printf '1337;File='
    if [[ -n "$1" ]]; then
      printf 'name='`printf "%s" "$1" | base64`";"
    fi

    VERSION=$(base64 --version 2>&1)
    if [[ "$VERSION" =~ fourmilab ]]; then
      BASE64ARG=-d
    elif [[ "$VERSION" =~ GNU ]]; then
      BASE64ARG=-di
    else
      BASE64ARG=-D
    fi

    printf "%s" "$3" | base64 $BASE64ARG | wc -c | awk '{printf "size=%d",$1}'
    printf ";inline=$2"
    printf ":"
    printf "%s" "$3"
    print_st
    printf '\n'
    if [[ -n "$4" ]]; then
      echo $1
    fi
}

function error() {
    echo "ERROR: $*" 1>&2
}

function show_help() {
    echo "Usage: imgcat [-p] filename ..." 1>& 2
    echo "   or: cat filename | imgcat" 1>& 2
}

## Main

if [ -t 0 ]; then
    has_stdin=f
else
    has_stdin=t
fi

# Show help if no arguments and no stdin.
if [ $has_stdin = f -a $# -eq 0 ]; then
    show_help
    exit
fi

# Look for command line flags.
while [ $# -gt 0 ]; do
    case "$1" in
    -h|--h|--help)
        show_help
        exit
        ;;
    -p|--p|--print)
        print_filename=1
        ;;
    -*)
        error "Unknown option flag: $1"
        show_help
        exit 1
      ;;
    *)
        if [ -r "$1" ] ; then
            has_stdin=f
            print_image "$1" 1 "$(base64 < "$1")" "$print_filename"
        else
            error "imgcat: $1: No such file or directory"
            exit 2
        fi
        ;;
    esac
    shift
done

# Read and print stdin
if [ $has_stdin = t ]; then
    print_image "" 1 "$(cat | base64)" ""
fi

return
}	#end catimg()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
logline() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
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

printf "${White}[$DATE]" >>$CMDLOGBIN
printf "[$DATE]" >> $CMDLOGTXT

#echo "[$DATE] $CMDLOGBIN
#sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" -i $CMDLOGBIN
prev_host=$curr_host

return 0
}	#end logline()
#---------------------------------------------------------------------------------------------------------------

##### OS ######

#---------------------------------------------------------------------------------------------------------
show_docker_system_prune() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${DONT_ENTER_EMOJI}${LightRed} WARNING!\n"
printf "This is a destructive command. May need to restart the script...${NC}\n"
docker system prune
echo
return
}	#end show_docker_system_prune()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------
show_docker_system_df() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
echo
docker system df
echo
return
}	#end show_docker_system_df()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------
restart_docker_mac() {    ### NOT USED YET ####
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
osascript -e 'quit app "Docker.app"'		#quit
open -a /Applications/Docker.app		#start
return 0
}	#end restart_docker_mac()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
start_docker_mac() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

read -p "    >> Should I attempt to start [may not work with all MacOS versions]? [Y/n]? " answer
if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
	open -a /Applications/Docker.app ; pausing 30
        is_running=`docker info|grep Images`
        if [ -z "$is_running" ]; then
                printf "${Red}Did not work! Please start docker from the UI...exiting...${NC}\n\n"
                printf "    ${Red}>>${NC} installation https://docs.docker.com/v1.10/mac/step_one/ ${NC}\n"
                exit
        fi
else
       printf "    ${Red}>>${NC} installation https://docs.docker.com/v1.10/mac/step_one/ ${NC}\n"
       printf "Exiting...\n" ; exit
fi
return 0
}	#end start_docker_mac()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
start_docker_liunx() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

read -p "    >> Should I attempt to start [may not work with all MacOS versions]? [Y/n]? " answer
if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
        start docker ; pausing 30
        is_running=`docker info|grep Images`
        if [ -z "$is_running" ]; then
                printf "${Red}Did not work! Please start docker from the UI... Exiting!${NC}\n\n"
		printf "    ${Red}>>${NC} installation: https://docs.docker.com/engine/installation/ ${NC}\n"
                exit
        fi
else
	printf "    ${Red}>>${NC} installation: https://docs.docker.com/engine/installation/ ${NC}\n"
       	printf "Exiting...\n" ; exit
fi
return 0
}	#end start_docker_linux()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------
check_root() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

# Check that we're in a BASH shell
if [[ $EUID -eq 0 ]]; then
  echo "This script must NOT be run as root" 1>&2
  exit 1
fi
}	#end check_root()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------
check_shell() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
# Check that we're in a BASH shell
if test -z "$BASH" ; then
  echo "This script ${0##*/} must be run in the BASH shell... Aborting."; echo;
  exit 192
fi
return 0
}	#end check_shell()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
remove_ip_aliases() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Delete ip aliases on the interface (OS dependent)

clear
printf "${BoldWhiteOnGreen}REMOVE IP ALIASES MENU ${NC}\n"
display_stats_banner
printf "\n"
#display_all_containers
echo
printf "${DONT_ENTER_EMOJI} ${LightRed}WARNING! \n"
printf "You are about to remove IP aliases. This will kill any container already binded to IP ${NC}\n"
echo
read -p "Are you sure you want to proceed? [y/N]? " answer
if [ "$answer" == "y" ] || [ "$answer" == "Y" ]; then
	base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `; # base_ip=$base_ip"."
	start_octet4=`echo $START_ALIAS | cut -d"." -f4 `
	docker_mc_start_octet4=`expr $start_octet4 - 1`
	end_octet4=`echo $END_ALIAS | cut -d"." -f4 `

	#---------
	if [ "$os" == "Darwin" ]; then
		read -p "Enter interface where IP aliases are binded to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_OSX"; fi
		sudo ifconfig  $eth  $base_ip.$docker_mc_start_octet4 255.255.255.0 -alias #special alias
		for i in `seq $start_octet4  $end_octet4`; do
			sudo ifconfig  $eth  $base_ip.$i 255.255.255.0 -alias
        		echo -ne "${NC}Removing: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
			done
			echo
			printf "\n${LightRed}You must restart the script to regain functionality!${NC}\n"
	elif  [ "$os" == "Linux" ]; then
			read -p "Enter interface where IP aliases are binded to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_LINUX"
                	sudo ifconfig $eth:$docker_mc_start_octet4 $base_ip.$docker_mc_start_octet4 down;  #special aliases
 			for  ((i=$start_octet4; i<=$end_octet4 ; i++))  do
                		echo -ne "${NC}Removing: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
                		sudo ifconfig $eth:$i "$base_ip.$i" down;
        		done
			echo
			printf "\n${LightRed}You must restart the script to regain functionality!${NC}\n"
	fi  #elif
	fi
	#---------

else
	printf "${NC}\n"
	return 0
fi  # answer
echo

return 0
}	#end remove_ip_aliases()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
setup_ip_aliases() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Check if ip aliases created, if not them bring up (tested on Ubuntu 16.04). Quick and dirty method. May need to change

base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `; # base_ip=$base_ip"."
start_octet4=`echo $START_ALIAS | cut -d"." -f4 `
end_octet4=`echo $END_ALIAS | cut -d"." -f4 `
docker_mc_start_octet4=`expr $start_octet4 - 1`

printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if last IP alias is configured on any NIC [$END_ALIAS]..."
last_alias=`ifconfig | $GREP $END_ALIAS `
if [ -n "$last_alias" ]; then
	printf "${Green}${OK_MARK_EMOJI} OK\n"
else
	printf "${Red}NOT FOUND!${NC}\n"
fi

if [ "$os" == "Darwin" ] && [ -z "$last_alias" ]; then
	#interfaces_list=`networksetup -listnetworkserviceorder|grep Hardware|sed 's/(Hardware Port: //g'|sed 's/)//g'`
	#interfaces_list=`ifconfig | pcregrep -M -o '^[^\t:]+:([^\n]|\n\t)*status: active'`
	#printf "   ${Red}>>${NC}List of active interfaces (loopback is recommend for MacOS):\n"
	#printf "Loopback, Device: lo\n$interfaces_list\n"
	#for nic in "$interfaces_list"; do printf "xxx   %-s4\n" "$nic"; done
	read -p "Enter interface to bind aliases to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_OSX"; fi
	printf "Building IP aliases for OSX...[$base_ip.$start_octet4-$end_octet4]\n"
	printf "Building special IP aliases for $MASTER_CONTAINER (used for docker monitoring only)...[$base_ip.$docker_mc_start_octet4]\n"
	sudo ifconfig  $eth  $base_ip.$docker_mc_start_octet4 255.255.255.0 alias  #special alias
        #to remove aliases repeat with -alias switch
        for i in `seq $start_octet4  $end_octet4`; do
		sudo ifconfig  $eth  $base_ip.$i 255.255.255.0 alias
        	echo -ne "${NC}Adding: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
	done
elif [ "$os" == "Linux" ] && [ -z "$last_alias" ]; then
	read -p "Enter interface to bind aliases to (default $ETH):  " eth; if [ -z "$eth" ]; then eth="$ETH_LINUX"; fi
	printf "Building IP aliases for LINUX...[$base_ip.$start_octet4-$end_octet4]\n"
	printf "Building special IP aliases for $MASTER_CONTAINER (used for docker monitoring only)...[$base_ip.$docker_mc_start_octet4]\n"
	sudo ifconfig $eth:$docker_mc_start_octet4 "$base_ip.$docker_mc_start_octet4" up   #special alias
	for  ((i=$start_octet4; i<=$end_octet4 ; i++))  do
        	echo -ne "${NC}Adding: >>  $eth:${Purple}$base_ip.${Yellow}$i\r"
		sudo ifconfig $eth:$i "$base_ip.$i" up;
	done
fi
printf "${NC}\n"
read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
return 0
}	#end setup_ip_aliases()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_load() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#We need to throttle back host creation if running on low powered server. Set to 4 x numb of cores

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
		os_free_mem=`top -l 1 | head -n 10 | grep PhysMem | awk '{print $2}' | sed 's/G//g' `
	else
        	loadavg=`cat /proc/loadavg |awk '{print $1}'|sed 's/,//g'`
        	os_free_mem=`free -g|grep -i mem|awk '{print $2}' `
	fi

	load=${loadavg%.*}
	MAXLOADAVG=`echo $cores \* $LOADFACTOR | bc -l `
	c=`echo " $load > $MAXLOADAVG" | bc `;
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} OS:[$os] MAX ALLOWED LOAD:[$MAXLOADAVG] current load:[$loadavg] cores[$cores]${NC}\n" >&5
	if [  "$c" == "1" ]; then
		echo
		for c in $(seq 1 $t); do
			echo -ne "${LightRed}High load avg [load:$loadavg max allowed:$MAXLOADAVG cores:$cores] Throttling! Pausing ${Yellow}$t${NC} seconds... ${Yellow}$c${NC}\033[0K\r"
        		sleep 1
		done
		t=`expr $t + $t`
	else
		break
	fi
done
return 0
}	#end check_load()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_for_ubuntu_pkgs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking [bc] package:${NC} "
condition=$(which bc 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [bc]${NC}:"
	progress_bar_pkg_download "sudo apt-get install bc -y"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking [wget] package:${NC} "
condition=$(which wget 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [wget]${NC}:"
	progress_bar_pkg_download "sudo apt-get install wget -y"
	brew link --overwrite wget
	#if brew link failed due to premission issue; run sudo chown -R `whoami` /usr/local
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [imgcat] package:${NC} "
condition=$(which imgcat 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [imgcat]${NC}:"
	#progress_bar_pkg_download "sudo apt-get install imgcat -y"
	progress_bar_pkg_download "sudo curl -o /usr/local/bin/imgcat -O https://raw.githubusercontent.com/gnachman/iTerm2/master/tests/imgcat"
    sudo chmod +x /usr/local/bin/imgcat
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [timeout] package:${NC} "
condition=$(which timeout 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [timeout]${NC}:"
	progress_bar_pkg_download "sudo apt-get install timeout -y"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
	alias timeout="gtimeout"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [graphviz] package:${NC} "
condition=$(which dot 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [graphviz]${NC}:"
	progress_bar_pkg_download "sudo apt-get install graphviz -y"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [tmux] package:${NC} "
condition=$(which tmux 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [tmux]${NC}:"
	progress_bar_pkg_download "sudo apt-get install tmux -y"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------

return 0
}	#end check_for_ubuntu_pkgs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_for_MACOS_pkgs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking Xcode commandline tools:${NC} "
cmd=$(xcode-select -p)
if [ -n $cmd ]; then
	printf "${Green}${CHECK_MARK_EMOJI} Installed\n${NC}"
else
	printf "${Yellow}Running [xcode-select --install]${NC}\n"
 	cmd=$(xcode-select --install)
fi

printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking brew package management:${NC} "
condition=$(which brew 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [brew]${NC}:"
	#get brew ruby install script
	curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install > install_brew.rb
	sed -ie 's/c = getc/c = 13/g' install_brew.rb   #remove prompt in install.rb script
	progress_bar_pkg_download "/usr/bin/ruby install_brew.rb"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking bc package:${NC} "
condition=$(which bc 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [bc]${NC}:"
	progress_bar_pkg_download "brew install bc"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------

printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking pcre package:${NC} "
cmd=$(brew ls pcre --versions)
if [ -n "$cmd" ]; then
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [pcre]${NC}:"
	progress_bar_pkg_download "brew install pcre"
 #	brew install pcre
fi
#--------------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking wget package:${NC} "
cmd=$(brew ls wget --versions)
if [ -n "$cmd" ]; then
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [wget]${NC}:"
	progress_bar_pkg_download "brew install wget"
fi
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking ggrep package:${NC} "
cmd=$(brew ls grep --versions|cut -d" " -f2)
if [ -n "$cmd" ]; then
        printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [ggrep]${NC}:"
	brew tap homebrew/dupes > /dev/null 2>&1
	progress_bar_pkg_download "brew install homebrew/dupes/grep"
#        printf "${BrownOrange}Running [sudo ln -s /usr/local/Cellar/grep/$cmd/bin/ggrep /usr/local/bin/ggrep]${NC}\n"
# 	sudo ln -s /usr/local/Cellar/grep/$cmd/bin/ggrep /usr/local/bin/ggrep
fi
#printf "${Yellow}Running [brew list]${NC}\n"
# brew list --versions
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [imagcat] package:${NC} "
cmd=$(brew ls imgcat --versions)
if [ -n "$cmd" ]; then
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [imgcat]${NC}:"
	progress_bar_pkg_download "brew tap eddieantonio/eddieantonio"
	progress_bar_pkg_download "brew install imgcat"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [gtimeout] package:${NC} "
cmd=$(brew ls coreutils --versions)
if [ -n "$cmd" ]; then
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [coreutils]${NC}:"
	progress_bar_pkg_download "brew install coreutils"
	alias timeout="gtimeout"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [graphviz] package:${NC} "
cmd=$(brew ls graphviz --versions)
if [ -n "$cmd" ]; then
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [graphviz]${NC}:"
	progress_bar_pkg_download "brew install graphviz"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [tmux] package:${NC} "
cmd=$(brew ls tmux --versions)
if [ -n "$cmd" ]; then
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [tmux]${NC}:"
	progress_bar_pkg_download "brew install tmux"
fi
#----------


echo
return 0
}	#end check_for_MACOS_pkgs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
startup_checks() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

printf "${BoldWhiteOnTurquoise}Splunk N' Box! Running startup validation checks...${NC}\n"

printf "${LightBlue}==> ${NC}$os_banner${NC}\n"
#-------------------sanity checks -------------------
check_root		#should not as root
check_shell		#must have bash
#Make sure working directories exist
mkdir -p $LOGS_DIR
mkdir -p $TMP_DIR
mkdir -p $SPLUNK_LIC_DIR
mkdir -p $SPLUNK_APPS_DIR
mkdir -p $SPLUNK_DATASETS_DIR
#----------------------------------------------------

#----------Gnu grep installed? MacOS only-------------
if [ "$os" == "Darwin" ]; then
	printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking for required MacOS packages...\n"
	check_for_MACOS_pkgs
fi
if [ "$os" == "Linux" ]; then
	printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking for required Ubuntu Linux packages...\n"
	check_for_ubuntu_pkgs
fi

#----------Gnu grep installed? MacOS only-------------

#-----------check for another copy of script running?---------
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if we have instances of this script running...${NC}"
this_script_name="${0##*/}"
pid_list=`ps -efa | grep $this_script_name | grep "/bin/bash" |grep -v $$ |awk '{printf $2" " }'`
#echo "running:  ps -efa | grep splunknbox.sh | grep \"/bin/bash\" |grep -v \$\$ |awk '{printf \$2\" \" }"
if [ -n "$pid_list" ]; then
	printf "\n"
        printf "    ${Red}>>${NC} Detected running instance(s) of $this_script_name [$pid_list]${NC}\n"
        read -p "    >> This script doesn't support multiple instances. Kill them? [Y/n]? " answer
        if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                sudo kill -9 $pid_list
		#kill any stray docker pull requests
		kill $(ps -ax|grep "docker pull"|grep -v "grep"|awk '{print $1}') >/dev/null 2>&1
        fi
	printf "\n"
else
        printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------other scripts running?---------

#-----------docker daemon running check----
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if docker daemon is running "

is_running=`docker info|grep Images 2>/dev/null `
if [ -z "$is_running" ] && [ "$os" == "Darwin" ]; then
        printf "${Red}NOT RUNNING!${NC}\n"
		start_docker_mac
elif [ -z "$is_running" ] && [ "$os" == "Linux" ]; then
        printf "${Red}NOT RUNNING!${NC}\n"
		start_docker_linux
fi
#expected to arrive at this point only if docker is running, therefore we can collect dockerinfo
if [ -n "$is_running" ]; then
		dockerinfo_ver=`docker info| $GREP 'Server Version'| awk '{printf $3}'| tr -d '\n' `
        dockerinfo_cpu=`docker info| $GREP 'CPU' | awk '{printf $2}'| tr -d '\n' `
        dockerinfo_mem1=`docker info| $GREP  'Total Memory'| awk '{printf $3}'|sed 's/GiB//g'| tr -d '\n' `
        dockerinfo_mem=`echo "$dockerinfo_mem1 / 1" | bc `
        #echo "DOCKER: ver:[$dockerinfo_ver]  cpu:[$dockerinfo_cpu]  totmem:[$dockerinfo_mem] ";exit
	printf "${Yellow}[ver:$dockerinfo_ver]${NC}..."
	#must use actuall escape code for emoji in awk
	awk -v n1=$dockerinfo_ver -v n2=$DOCKER_MIN_VER \
	'BEGIN {if (n1<n2) printf ("\033[0;33mWarning! Recommending %s+\n", n2); else printf ("\033[0;32m\xe2\x9c\x85 OK!\n");}'
      	#printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------docker daemon running check----

#-----------Gathering OS memory/cpu info---
if [ "$os" == "Linux" ]; then
        cores=`$GREP -c ^processor /proc/cpuinfo`
	os_used_mem=`free -g|grep -i mem|awk '{print $3}' `
        os_free_mem=`free -g|grep -i mem|awk '{print $4}' `
        os_total_mem=`free -g|grep -i mem|awk '{print $2}' `
        os_free_mem_perct=`echo "($os_free_mem * 100) / $os_total_mem"| bc`

elif [ "$os" == "Darwin" ]; then
        cores=`sysctl -n hw.ncpu`
        os_used_mem=`top -l 1 -s 0|grep PhysMem|tr -d '[[:punct:]]'|awk '{print $2}' `
	if ( compare "$os_used_mem" "M" ); then
		os_used_mem=`echo $os_used_mem | tr -d '[[:alpha:]]'`  #strip M
		os_used_mem=`printf "%0.1f\n" $(bc -q <<< scale=6\;$os_used_mem/1024)` #convert float from MB to GB
	else
		os_used_mem=`echo $os_used_mem | tr -d '[[:alpha:]]'`  #strip G
	fi
        os_wired_mem=`top -l 1 -s 0|grep PhysMem|tr -d '[[:punct:]]'|awk '{print $4}' `
	if ( compare "$os_wired_mem" "M" ); then
                os_wired_mem=`echo $os_wired_mem | tr -d '[[:alpha:]]'`  #strip M
		os_wired_mem=`printf "%0.1f\n" $(bc -q <<< scale=6\;$os_wired_mem/1024)` #convert float from MB to GB
        else
                os_wired_mem=`echo $os_wired_mem | tr -d '[[:alpha:]]'`  #strip G
        fi
        os_unused_mem=`top -l 1 -s 0|grep PhysMem|tr -d '[[:punct:]]'|awk '{print $6}' `
	if ( compare "$os_unused_mem" "M" ); then
                os_unused_mem=`echo $os_unused_mem | tr -d '[[:alpha:]]'`  #strip M
		os_unused_mem=`printf "%0.1f\n" $(bc -q <<< scale=6\;$os_unused_mem/1024)` #convert float from MB to GB
        else
                os_unused_mem=`echo $os_unused_mem | tr -d '[[:alpha:]]'`  #strip G
        fi
        #echo "MEM: used:[$os_used_mem] wired:[$os_wired_mem]  unused:[$os_unused_mem]"
		os_free_mem=$os_unused_mem
        #os_total_mem=`echo $os_used_mem + $os_wired_mem + $os_unused_mem | bc`
		os_total_mem=`hostinfo|grep "memory available"| awk '{print $4}'`
        os_free_mem_perct=`echo "($os_free_mem * 100) / $os_total_mem"| bc`
      #  echo "MEM: TOTAL:[$os_total_mem] UNUSED:[$os_unused_mem] %=[$os_free_mem_perct]     USED:[$os_used_mem] wired:[$os_wired_mem]"
fi
#exit
#-----------Gathering OS memory/cpu info---

#-----------OS memory check-------------------
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if we have enough free OS memory ${Yellow}%s%%${NC} [Free:%sgb Total:%sgb] " $os_free_mem_perct $os_free_mem $os_total_mem
#state=`echo "$os_free_mem < $LOW_MEM_THRESHOLD"|bc` #float comparison
#WARN if free mem is 20% or less of total mem
if [ "$os_free_mem_perct" -le "20" ]; then
	printf "${BrownOrange}${WARNING_EMOJI} (May not be a problem)${NC}\n"
	printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Recommended %sGB+ of free memory for large builds\n" $LOW_MEM_THRESHOLD
	printf "\t${BULB_EMOJI}${NC} Modern OSs do not always report unused memory as free\n\n" $os_free_mem $LOW_MEM_THRESHOLD
	#printf "${White}    7-Change docker default settings! Docker-icon->Preferences->General->pick max CPU/MEM available${NC}\n\n"
else
	printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------OS memory check-------------------

#-----------docker preferences/config check-------
docker_total_cpu_perct=`echo "($dockerinfo_cpu * 100) / $cores"| bc`
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking Docker configs for CPUs allocation ${Yellow}%s%%${NC} [Docker:%sgb  OS:%sgb]..." $docker_total_cpu_perct $dockerinfo_cpu $cores
#state=`echo "$os_free_mem < $LOW_MEM_THRESHOLD"|bc` #float comparison
if [ "$docker_total_cpu_perct" -lt "70" ]; then
	printf "${LightRed}${DONT_ENTER_EMOJI} ALERT${NC}\n"
	printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Docker is configured to use %s of the available system %s CPUs\n" $dockerinfo_cpu $cores
	printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Please allocate all available system CPUs to Docker (Preferences->Advance)\n\n"
elif [ "$docker_total_cpu_perct" -lt "80" ]; then
	printf "${BrownOrange}${WARNING_EMOJI} WARNING${NC}\n"
	printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Docker is configured to use %s of the available system %s CPUs\n" $dockerinfo_cpu $cores
	printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Please allocate all available system CPUs to Docker (Preferences->Advance)\n\n"
else

        printf " ${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
docker_total_mem_perct=`echo "($dockerinfo_mem * 100) / $os_total_mem"| bc`
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking Docker configs for MEMORY allocation ${Yellow}%s%%${NC} [Docker:%sgb OS:%sgb]..." $docker_total_mem_perct $dockerinfo_mem $os_total_mem

#WARN if ratio docker_configred_mem/os_total-mem < 80%
if [ "$docker_total_mem_perct" -lt "70" ]; then
	printf "${LightRed}${DONT_ENTER_EMOJI} ALERT${NC}\n" $dockerinfo_mem $os_total_mem
    printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Docker is configured to use %sgb of the available system %sgb memory\n" $dockerinfo_mem $os_total_mem
    printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Please allocate all available system memory to Docker (Preferences->Advance)\n\n"
elif [ "$docker_total_mem_perct" -lt "80" ]; then
	printf "${BrownOrange}${WARNING_EMOJI} WARNING${NC}\n" $dockerinfo_mem $os_total_mem
    printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Docker is configured to use %sgb of the available system %sgb memory\n" $dockerinfo_mem $os_total_mem
    printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Please allocate all available system memory to Docker (Preferences->Advance)\n\n"
else

    printf " ${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------docker preferences check-------

#-----------splunk image check-------------
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if Splunk image is available [$DEFAULT_SPLUNK_IMAGE]..."
image_ok=`docker images|grep "$DEFAULT_SPLUNK_IMAGE"`
if [ -z "$image_ok" ]; then
	printf "${Red}NOT FOUND!${NC}\n"
	read -p "    >> Downloading image [$DEFAULT_SPLUNK_IMAGE]? [Y/n]? " answer
        if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		#printf "    ${Red}>>${NC} Downloading from https://hub.docker.com/r/mhassan/splunk/\n"
		progress_bar_image_download "$DEFAULT_SPLUNK_IMAGE"
                printf "\n${NC}"
        else
			printf "    ${Red}>> ${WARNING_EMOJI}WARNNING! Many functions will fail without ($DEFAULT_SPLUNK_IMAGE). It is critical to download this splunk image....${NC}\n"
                printf "    See https://hub.docker.com/search/?isAutomated=0&isOfficial=0&page=1&pullCount=0&q=splunknbox&starCount=0\n"
		read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
        fi
else
        printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------splunk image check-------------

#-----------splunk-net check---------------
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if docker network is created [$SPLUNKNET]..."
net=`docker network ls | grep $SPLUNKNET `
if [ -z "$net" ]; then
	printf "${Green} Creating...${NC}\n"
        docker network create -o --iptables=true -o --ip-masq -o --ip-forward=true $SPLUNKNET
else
       printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------splunk-net check---------------

#-----------license files/dir check--------
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if we have license files *.lic in [$SPLUNK_LIC_DIR]..."
if [ ! -d $SPLUNK_LIC_DIR ]; then
    	printf "${Red} DIR DOESN'T EXIST!${NC}\n"
		printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Please create $SPLUNK_LIC_DIR and place all *.lic files there.\n"
		printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} Change the location of LICENSE dir in the config section of the script.${NC}\n\n"
elif  ls $SPLUNK_LIC_DIR/*.lic 1> /dev/null 2>&1 ; then
       	printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
	else
        printf "${Red}NO LIC FILE(S) FOUND!${NC}\n"
		printf "\t${YELLOW_LEFTHAND_EMOJI}${NC} If *.lic exist, make sure they are readable.${NC}\n\n"
fi
#-----------license files/dir check--------

#-----------local splunkd check------------
#Little tricky, local splunkd process running on docker-host is different than splunkd inside a container!
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if non-docker splunkd process is running [$LOCAL_SPLUNKD]..."
PID=`ps aux | $GREP 'splunkd' | $GREP 'start' | head -1 | awk '{print $2}' `  	#works on OSX & Linux

if [ "$os" == "Darwin" ] && [ -n "$PID" ]; then
	splunk_is_running="$PID"
elif [ "$os" == "Linux" ] && [ -n "$PID" ]; then
	splunk_is_running=`cat /proc/$PID/cgroup|head -n 1|grep -v docker`	#works on Linux only
fi
if [ -n "$splunk_is_running" ]; then
	printf "${Red}Running [$PID]${NC}\n"
	read -p "    >> Kill it? [Y/n]? " answer
       	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		sudo $LOCAL_SPLUNKD stop
	else
		printf "    ${LightRed}${WARNING_EMOJI}WARNING!${NC}\n"
		printf "    ${LightRed}>>${NC} Running local splunkd may prevent containers from binding to interfaces!${NC}\n\n"
	fi
else
	printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------local splunkd check------------

#-----------discovering DNS setting for OSX. Used for container build--
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking for dns server configuration "
if [ "$os" == "Darwin" ]; then
        DNSSERVER=`scutil --dns|grep nameserver|awk '{print $3}'|sort -u|tail -1`
	printf "[$DNSSERVER]...${Green}${OK_MARK_EMOJI} OK${NC}\n"
else
	printf "\n"
fi

#-----------discovering DNS setting for OSX. Used for container build--

#TO DO:
#check dnsmasq
#check $USER
#Your Mac must be running OS X 10.8 “Mountain Lion” or newer to run Docker software.
#https://docs.docker.com/engine/installation/mac/

#-------------Create IP aliases if they dont exist -----------
setup_ip_aliases
#-------------------------------------------------------------

return 0
}	#end startup_checks()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
detect_os() {
#Set global vars based on OS type:
# ETH to use
# GREP command. Must install ggrep utility on OSX
# MOUNTPOINT   (OSX is strict about permissions)

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

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
	os_banner="Detected MacOS [System:$sys_ver Kernel:${Yellow}$kern_ver${NC}]"

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
	os_banner="Detected LINUX [Release:$release Kernel:${Yellow}$kern_ver${NC}]"

elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    os="Windows"
fi

#is it AWS EC2 instance?
if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
	bios_ver=`sudo dmidecode -s bios-version`
	os_banner="Detected AWS EC2 instance [BIOS:${Yellow}$bios_ver${NC}]"
    AWS_EC2="YES"
	START_ALIAS=$START_ALIAS_OSX
	END_ALIAS=$END_ALIAS_OSX
else
    AWS_EC2="NO"
fi


return 0
}	#end detect_os()
#------------------------------------------------------------------------------------------------------

#-----------Detect script version ---------------------------
detect_ver() {
#Need to detect git version stuff as early as possible but after ggrep is installed

#Lines below  must be broked with "\" .Otherwise git clean/smudge scripts will
#screw up things if the $ sign is not the last char
GIT_VER=`echo "__VERSION: 4.5-14 $" | \
		$GREP -Po "\d+.\d+-\d+"`
GIT_DATE=`echo "__DATE: Sun Jan 14,2018 - 04:16:58PM -0600 $" | \
		$GREP -Po "\w+\s\w+\s\d{2},\d{4}\s-\s\d{2}:\d{2}:\d{2}(AM|PM)\s-\d{4}" `
GIT_AUTHOR=`echo "__AUTHOR: mhassan2 <mhassan@splunk.com> $" | \
		$GREP -Po "\w+\s\<\w+\@\w+.\w+\>"`
#echo [$GIT_VER]
#echo [$GIT_DATE]
#echo [$GIT_AUTHOR]
return 0
}
#-----------Detect script version ---------------------------


###### UTILITIES ######

#---------------------------------------------------------------------------------------------------------------
change_loglevel() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#-------
declare -a list=(2 3 4 5 6)
#echo ${list[@]}
i=0
#highlight the current loglevel number
for id in ${list[@]}; do
	#echo "$i:${list[$i]}"
	if [ "${list[$i]}" == "$loglevel" ]; then
		break
	fi
	let i++
done
list[$i]="${BoldWhiteOnPink}${list[$i]}${NC}"
var=${list[@]}
tput cup 16 15
echo -e -n "Enter new loglevel [$var${NC}]: "   # Display prompt in red
#read  loglevel

 # -- get input until Correct (within range)
unset get_num
read get_num
while [[ ! ${get_num} =~ ^[2-6]+$ ]]; do
	tput cup 16 15; echo -e -n "Enter new loglevel [$var]: "   # Display prompt in red
	read get_num
	tput cup 18 15; printf "${Red}${get_num} Invalid choice, try again...${NC}\n"
        ! [[ ${get_num} -ge 2 && ${get_num} -le 6  ]] && unset get_num
done
loglevel="${get_num}"
#echo This is a number within a range :  ${get_num}

#-------

for v in $(seq 3 $loglevel); do
    (( "$v" <= "$maxloglevel" )) && eval exec "$v>&2"  #Don't change anything higher than the maximum loglevel allowed.
done

#From the loglevel level one higher than requested, through the maximum;
for v in $(seq $(( loglevel+1 )) $maxloglevel ); do
    (( "$v" > "2" )) && eval exec "$v>/dev/null" #Redirect these to bit bucket, provided that they don't match stdout and stderr.
done
return 0
}	#end change_loglevel()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
compare() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
# String comparison routine.
# usage:   compare(string, sub-string)
# Returns 0 if the specified string compare the specified sub-string,otherwise return 1

string=$1 ; substring=$2


    if test "${string#*$substring}" != "$string"
    then
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} strings matching${NC}\n"  >&5
        return 0    # TRUE! $substring is in $string
    else
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} strings NOT matching!${NC}\n"  >&5
        return 1    # NOT TRUE! $substring is not in $string
    fi
return 0
}	#end compare()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
pausing() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#$1=seconds

for c in $(seq 1 $1); do
	echo -ne "${LightGray}	${Yellow}${ARROW_EMOJI}${NC}Pausing $1 seconds... ${Yellow}$c\r"  >&3
	sleep 1
done
printf "${LightGray}	${Yellow}${ARROW_EMOJI}${NC}Pausing $1 seconds... ${Green}Done!${NC}\n"  >&3

return 0
}	#end pausing()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_output() {
#This function displays the output from CMD (docker command executed)
#$1  Actual message after executing docker command
#$2  The expected "good" message returned if docker command executed OK. Otherwise everything would be an error
#$3  The logging (I/O redirect) to display the message (good for verbosity settings)

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

outputmsg=$1; OKmsg=$2; logging=$3
OKmsg=`echo $OKmsg| tr '[a-z]' '[A-Z]'`				#convert to upper case
outputmsg=`echo -n $outputmsg| tr '[a-z]' '[A-Z]' |sed -e 's/^M//g' | tr -d '\r' ` #cleanup & convert to upper case
size=${#outputmsg}

#also display returned msg if log level is high
#printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} vars outputmsg:[$outputmsg] OKmsg:[$OKmsg]${NC}\n"  >&5
#echo "result[$1]"
        if ( compare "$outputmsg" "$OKmsg" ) || [ "$size" == 64 ] || [ "$size" == 0 ] ; then
                printf "${Green}${OK_MARK_EMOJI} OK ${NC}\n"  >&$logging
        else
               # printf "\n${DarkGray}[%s] ${NC}" "$1"
                printf "${Red}[%s] ${NC}\n" "$1" >&$logging
                #restart_splunkd "$host"
        fi
return 0
}	#end display_output()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
_debug_function_inputs() {

func_name=$1; arg_num=$2; param_list=$3; calls=$4
calls_count=`echo $calls|wc -w|sed 's/ //g'`
calls=`echo $calls| sed 's/ / <- /g'`;
printf "\n${LightRed}DEBUG:=> CALLS($calls_count) =>${Yellow}[$calls]${NC}\n"  >&6
printf "${LightRed}DEBUG:=> STARTED  =>${Yellow}$func_name():=> ${Purple}args:[$arg_num] ${Yellow}(${LightGreen}$param_list${Yellow})${NC}\n" >&6

return 0
}	#end _debug_function_inputs()
#---------------------------------------------------------------------------------------------------------------


####### SPLUNKD ##########

#---------------------------------------------------------------------------------
is_splunkd_running() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

fullhostname=$1
check_load

#-----check if splunkd is running--------
if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ); then
	pausing 30;
fi #demo/workshop containers takes little longer to start

#splunkstate=`docker exec -ti $fullhostname /opt/splunk/bin/splunk status| $GREP -i "not running" `
splunkstate=`docker exec -ti $fullhostname sh -c "ps xa|$GREP '[s]plunkd -p'" `
#echo "splunkstate[$splunkstate]"
echo -ne "	${Yellow}${ARROW_EMOJI}${NC}Verifying that splunkd is running...\r" >&3
if [ -n "$splunkstate" ]; then
        echo -ne  "	${Yellow}${ARROW_EMOJI}${NC}Verifying that splunkd is running...${Green}${OK_MARK_EMOJI} OK${NC}                           \n" >&3
else
        	echo -ne "${NC}	${Yellow}${ARROW_EMOJI}${NC}Verifying that splunkd is running..${Red}Not running! Attempt ${Yellow}$i${Red} to restart\r${NC}" >&3
        	sleep 30        #pause between attempts to restart
        	CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk start "
        	#echo "cmd[$CMD]"
        	OUT=`$CMD`; display_output "$OUT" "Splunk web interface is at" "4"
        	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
        	#logline "$CMD" "$fullhostname"
        	#pausing "30"
			splunkstate=`docker exec -ti $fullhostname sh -c "ps xa|$GREP '[s]plunkd -p'" `
			if [ -z "$splunkstat" ]; then
        		echo -ne  "	${Yellow}${ARROW_EMOJI}${NC}Verifying that splunkd is running...${Green}${OK_MARK_EMOJI} OK${NC}                           \n" >&3
				return

			fi
fi

#if [ -z "$splunkstate" ]; then
# printf "${Green}${OK_MARK_EMOJI} OK${NC}\n" >&3
 #       echo -ne  "	${Yellow}${ARROW_EMOJI}${NC}Verifying that splunkd is running...${Green}${OK_MARK_EMOJI} OK${NC}                           \n" >&3
#else
 #       echo -ne  "	${Yellow}${ARROW_EMOJI}${NC}Verifying that splunkd is running...${Red}NOT${OK_MARK_EMOJI} OK${NC}                          \n" >&3
#fi

return 0
}	#end is_splunkd_running()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
change_default_splunk_image() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function will set the splunk version to use for building containers.

clear
printf "${BoldYellowOnBlue}Manage Images -> CHANGE DEFAULT SPLUNK IMAGE MENU ${NC}\n"
display_stats_banner
printf "\n"

#count=`wc -l $CMD`

printf "Retrieving list from: [https://hub.docker.com/u/splunknbox/]...\n"
CMD="docker search splunknbox"; OUT=`$CMD`
#printf "$OUT" #| awk '{printf $1}'

retrieved_images_list=`printf "$OUT"|grep -v NAME|awk '{print $1" "}'| sort | tr -d '\n' `
declare -a list=($retrieved_images_list)
#printf " ${BoldWhiteOnRed}  Host(container)%-5s State%-2s Splunkd   Ver    Internal IP%-3s       Image used%-10s     URL${NC}\n"
printf "${BoldWhiteOnRed}             IMAGE NAME%-22s CREATED%-7s SIZE%-15s AUTHOR%-20s${NC}\n"
printf "${White} -------------------------------------      ------------  --------   ---------------------------------------\n"
counter=1
#count=`docker images --format "{{.ID}}" | wc -l`
for image_name in $retrieved_images_list; do
	if [ "$image_name" == "$DEFAULT_SPLUNK_IMAGE" ]; then
    	printf "${Purple}%-2s${NC})${YELLOW_LEFTHAND_EMOJI} ${Purple}%-40s${NC}" "$counter" "$image_name"
	else
    	printf "${Purple}%-2s${NC})  ${Purple}%-40s${NC}" "$counter" "$image_name"
	fi
	created=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $7,$8}'`
    if [ -n "$created" ]; then
        author=`docker inspect $image_name |grep -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
        printf "%-12s %-7s %-10s ${NC}\n" "$created" "$size" "$author"
    else
        printf "${DarkGray}NOT CACHED! ${NC}\n"
    fi
    let counter++
done
#count=`docker images |grep -i "splunk_"|wc -l`
#if [ $count == 0 ]; then
#        printf "\nNo images to list!\n"
#        return 0
#fi
#display_all_images "DEMO"
count=0
echo
read -p "Select a number: " choice
if [ -n "$choice" ]; then
		START=$(date +%s)
		image_name=(${list[$choice - 1]})
		progress_bar_image_download "$image_name"
		DEFAULT_SPLUNK_IMAGE="$image_name"
		printf "${BrownOrange}${WARNING_EMOJI} Subsequent container builds (except DEMOs) will use the new splunk image ${Yellow}[$image_name]${NC}\n"
fi

return 0
}	#end change_default_splunk_image()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
splunkd_status_all() {
#This functions displays splunkd status on all containers

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
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
#-----------------------------------------------------------------------------
add_license_file() {
#This function will just copy the license file. Later on if the container get configured
#as a license-slave; then this file become irrelevant
# $1=fullhostname
#see: https://docs.docker.com/engine/reference/commandline/cp/

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

check_load
CMD="docker cp $SPLUNK_LIC_DIR  $1:/opt/splunk/etc/licenses/enterprise"; OUT=`$CMD`
printf "	${Yellow}${ARROW_EMOJI}${NC}Copying license file(s). Will override if later became license-slave " >&3 ; display_output "$OUT" "" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$1"

if ( compare "$1" "LM" ); then
	printf "	${Yellow}${ARROW_EMOJI}${NC}*LM* host! Forcing immediate splunkd restart.Please wait " >&3
	docker exec -u splunk -ti $1  /opt/splunk/bin/splunk restart > /dev/null >&1
	printf "${Green} Done! ${NC}\n" >&3
fi
return 0
}	#end add_license_file()
#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------
reset_splunk_passwd() {
fullhostname=$1

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

docker exec -u splunk -ti $fullhostname touch /opt/splunk/etc/.ui_login	#prevent first time changeme password screen
docker exec -u splunk -ti $fullhostname rm -fr /opt/splunk/etc/passwd	#remove any existing users (include admin)

#reset password to "$USERADMIN:$USERPASS"
CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk edit user admin -password hello -roles admin -auth admin:changeme"
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
logline "$CMD" "$fullhostname"
printf "${Purple}$fullhostname${NC}: > $CMD\n"  >&4

if ( compare "$CMD" "failed" ); then
   echo "	${Yellow}${ARROW_EMOJI}${NC}Trying default password "
   CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk edit user admin -password changeme -roles admin -auth $USERADMIN:$USERPASS"
   printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
   logline "$CMD" "$fullhostname"
   printf "${Purple}$fullhostname${NC}: $OUT\n"  >&4
fi
return 0
}	#end reset_splunk_passwd()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
reset_all_splunk_passwords() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnBlue}RESET SPLUNK INSTANCES PASSWORD MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers

for host_name in `docker ps --format "{{.Names}}"`; do
        if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) || ( compare "$host_name" "3RDP" ) ; then
                true
        else
                printf "${Purple}$host_name${NC}: Admin password reset to [hello]\n"
                reset_splunk_passwd $host_name
        fi
done
echo
return 0
}	#end reset_all_splunk_passwords()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
add_splunk_licenses() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnBlue}ADD SPLUNK LICENSE MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers

for host_name in `docker ps --format "{{.Names}}"`; do
        if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) || ( compare "$host_name" "3RDP" ) ; then
                true
        else
		printf "${Purple}$host_name${NC}:"
		add_license_file $host_name
        fi
done
return 0
}	#end add_splunk_licenses()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
restart_all_splunkd() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnBlue}RESTART SPLUNK MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers

for host_name in `docker ps --format "{{.Names}}"`; do
        if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) || ( compare "$host_name" "3RDP" ) ; then
                true
        else
		printf "${Purple}$host_name${NC}:"
     		restart_splunkd "$host_name"
        fi
done
return 0
}	#end restart_all_splunkd()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
restart_splunkd() {
fullhostname=$1
#$2=b Execute in the background and don't wait to return.This will speed up everything but load the CPU

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

if [ "$2" == "b" ]; then
	printf "	${Yellow}${ARROW_EMOJI}${NC}Restarting splunkd in the ${White}background${NC} " >&3
        CMD="docker exec -u splunk -d $fullhostname /opt/splunk/bin/splunk restart "
        OUT=`$CMD`; display_output "$OUT" "The Splunk web interface is at" "3"
   	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$fullhostname"
else
	printf "	${Yellow}${ARROW_EMOJI}${NC}Restarting splunkd. Please wait! " >&3
	CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk restart "
        OUT=`$CMD`; display_output "$OUT" "The Splunk web interface is at" "3"
   	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$fullhostname"
fi

return 0
}	#end restart_splunkd()
#---------------------------------------------------------------------------------------------------------------


#---------------------------------------------------------------------------------------------------------------
make_lic_slave() {
# This function designate $hostname as license-slave using LM (License Manager)
#Always check if $lm exist before processing

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

check_load
lm=$1; hostname=$2;
if [ -n "$lm" ]; then
	#echo "hostname[$hostname]  lm[$lm] _____________";exit
	lm_ip=`docker port  $lm| awk '{print $3}'| cut -d":" -f1|head -1`
  	if [ -n "$lm_ip" ]; then
        	CMD="docker exec -u splunk -ti $hostname /opt/splunk/bin/splunk edit licenser-localslave -master_uri https://$lm_ip:$MGMT_PORT -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
        	printf "	${Yellow}${ARROW_EMOJI}${NC}Making [$hostname] license-slave using LM:[$lm] " >&3 ; display_output "$OUT" "has been edited" "3"
		printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$hostname"
        	fi
fi

return 0
} 	#end make_lic_slave()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_host_exist() {		 ####### NOT USED YET ########
#$1=hostname (may include digits sequence)   $2=list_to_check_against
#Check if host exist in list; if not create it using basename only . The new host seq is returned by function

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

printf "${Purple}[$1] Host check >>> "
basename=$(printf '%s' "$1" | tr -d '0123456789')  #strip numbers
if [ -z "$2" ]; then
        printf "${LightPurple}Group is empty >>> creating host ${NC}\n";
        create_splunk_container $basename 1
else if ( compare "$2" "$1" ); then
                printf "${Purple}Found in group. No action. ${NC}\n";
                return 0
        else
                printf "${LightPurple}Not found in group >>> Using basename to create next in sequence ${NC}\n";
                create_splunk_container $basename 1
                num=`echo $?`    #last host seq number created
                return $num
        fi
fi
return 0
}	#end check_host_exist()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
add_os_utils_to_demos() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Add missing OS utils to all non-demo containers
clear
printf "${BoldWhiteOnGreen}ADD OS UTILS MENU ${NC}\n"
display_stats_banner
printf "\n"
printf "${BrownOrange}This option will add OS packages [vim net-tools telnet dnsutils] to all running demo containers only...\n"
printf "${BrownOrange}Might be useful if you will be doing a lot of manual splunk configuration, however, it will increase container's size! ${NC}\n"
printf "\n"
read -p "Are you sure you want to proceed? [Y/n]? " answer
if [ "$answer" == "y" ] || [ "$answer" == "y" ] || [ "$answer" == "" ]; then
	true  #do nothing
else
	return 0
fi

count=`docker ps -a|egrep -i "DEMO|WORKSHOP"| grep -v "IMAGE"| wc -l`
if [ $count == 0 ]; then
        printf "\nNo running demo containers found!\n"; printf "\n"
        return 0
fi;
for id in $(docker ps -a|egrep -i "DEMO|WORKSHOP"|grep -v "PORTS"|awk '{print $1}'); do
    	hostname=`docker ps -a --filter id=$id --format "{{.Names}}"`
	printf "${Purple}$hostname:${NC}\n"
	#install stuff you will need in  background
	docker exec -it $hostname apt-get update #> /dev/null >&1
	docker exec -it $hostname apt-get install -y vim net-tools telnet dnsutils # > /dev/null >&1
done
echo
return 0
}	#end add_os_utils_to_demos()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
list_all_hosts_by_role() {
#This functions shows all containers grouped by role (using base hostname)
#captain=`docker exec -u splunk -ti $i /opt/splunk/bin/splunk show shcluster-status|head -10 | $GREP -i label |awk '{print $3}'| sed -e 's/^M//g' | tr -d '\r' | tr  '\n' ' '`

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
idx_list=`docker ps -a --filter name="IDX|idx" --format "{{.Names}}"|sort `
sh_list=`docker ps -a --filter name="SH|sh" --format "{{.Names}}"|sort`
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort`
lm_list=`docker ps -a --filter name="LM|lm" --format "{{.Names}}"|sort`
dep_list=`docker ps -a --filter name="DEP|dep" --format "{{.Names}}"|sort`
ds_list=`docker ps -a --filter name="DS|ds" --format "{{.Names}}"|sort`
hf_list=`docker ps -a --filter name="HF|hf" --format "{{.Names}}"|sort`
uf_list=`docker ps -a --filter name="UF|uf" --format "{{.Names}}"|sort`
dmc_list=`docker ps -a --filter name="DMC|dmc" --format "{{.Names}}"|sort`
demo_list=`docker ps -a --filter name="DEMO|demo|WORKSHOP|workshop" --format "{{.Names}}"|sort`
rdparty_list=`docker ps -a --filter name="3RDP|3rdp" --format "{{.Names}}"|sort`

printf "${BoldWhiteOnYellow}ALL CONTAINERS GROUPED BY ROLE MENU ${NC}\n"
display_stats_banner
printf "\n"
#display_all_containers "DEMO"
printf "${LightBlue}LMs${NC}: " ;      	printf "%-5s " $lm_list;echo
printf "${Purple}CMs${NC}: " ;      	printf "%-5s " $cm_list;echo
printf "${Yellow}IDXs${NC}: ";      	printf "%-5s " $idx_list;echo
printf "${Green}SHs${NC}: ";        	printf "%-5s " $sh_list;echo
printf "${Cyan}DSs${NC}: ";         	printf "%-5s " $ds_list;echo
printf "${OrangeBrown}DEPs${NC}: "; 	printf "%-5s " $dep_list;echo
printf "${Blue}HFs${NC}: ";         	printf "%-5s " $hf_list;echo
printf "${LightBlue}UFs${NC}: ";    	printf "%-5s " $uf_list;echo
printf "${Green}DMCs${NC}: ";		printf "%-5s " $dmc_list;echo
printf "${Red}DEMOs${NC}: ";    	printf "%-5s " $demo_list;echo
printf "${Purple}3RDPARTYs${NC}: ";    	printf "%-5s " $rdparty_list;echo
echo

printf "Running Index clusters (Cluster Master in yellow):\n"
for i in $cm_list; do
	printf "${Yellow}$i${NC}: "
	docker exec -u splunk -ti $i /opt/splunk/bin/splunk show cluster-status -auth $USERADMIN:$USERPASS \
	| $GREP -i IDX | awk '{print $1}' | paste -sd ' ' -
done
echo

printf "Running Search Head Clusters (Deployer in yellow):\n"
prev_list=''
for i in $sh_list; do
	sh_cluster=`docker exec -u splunk -ti $i /opt/splunk/bin/splunk show shcluster-status -auth $USERADMIN:$USERPASS | $GREP -i label |awk '{print $3}'| sed -e 's/^M//g' | tr -d '\r' | tr  '\n' ' ' `
	if ( compare "$sh_cluster" "$prev_list" );  then
		true  #do nothing
	else
        	printf "${Yellow}$i${NC}: %s" "$sh_cluster"
		prev_list=$sh_cluster
	fi
	echo
done
echo
return 0
}	#end list_all_hosts_by_role()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
custom_login_screen() {
#This function creates custom login screen with some useful data (hostname, IP, cluster label)

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
vip=$1;  fullhostname=$2

check_load
#set -x
#----------- password stuff ----------
if ( compare "$fullhostname" "DEMO-ES" ) || ( compare "$fullhostname" "DEMO-ITSI" ) || ( compare "$fullhostname" "DEMO-VMWARE" ) ; then
	true #dont change pass for some demos.
	USERPASS="changeme"
        printf "${Green}OK${NC}\n"
else
	#reset password to "$USERADMIN:$USERPASS"
	CMD="docker exec -u splunk -ti $fullhostname touch /opt/splunk/etc/.ui_login"      #prevent first time changeme password screen
	OUT=`$CMD`;   #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
	logline "$CMD" "$fullhostname"
	CMD="docker exec -u splunk -ti $fullhostname rm -fr /opt/splunk/etc/passwd"        #remove any existing users (include admin)
	OUT=`$CMD`;   #printf "${DarkGray}CMD:[$CMD]${NC}\n" >&5
	logline "$CMD" "$fullhostname"
	CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk edit user admin -password $USERPASS -roles $USERADMIN -auth admin:changeme "
	OUT=`$CMD`;   display_output "$OUT" "user admin edited" "3"
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$fullhostname"

	if ( compare "$CMD" "failed" ); then
        	echo "Trying default password"
   #     	docker exec -u splunk -ti $fullhostname rm -fr /opt/splunk/etc/passwd        #remove any existing users (include admin)
        	CMD="docker exec -u splunk -ti $fullhostname touch /opt/splunk/etc/.ui_login"      #prevent first time changeme password screen
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
fi
#----------- password stuff ----------

#set home screen banner in web.conf
hosttxt=`echo $fullhostname| $GREP -Po '\d+(?!.*\d)'  `        #extract string portion
hostnum=`echo $fullhostname| $GREP -Po '\d+(?!.*\d)'  `        #extract digits portion

#-------cluster label stuff-------
container_ip=`docker inspect $fullhostname| $GREP IPAddress |$GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1  `
#cluster_label=`docker exec -ti $fullhostname $GREP cluster_label /opt/splunk/etc/system/local/server.conf | awk '{print $3}' `
#cluster_label=`cat $PROJ_DIR/web.conf.tmp | $GREP -Po 'cluster.* (.*_LABEL)'| cut -d">" -f3`
if [ -z "$cluster_label" ]; then
        cluster_label="--"
fi
#-------cluster label stuff-------

#Dont show pass if running in AWS EC2 (public instance)
if [ "$AWS_EC2" == "YES" ]; then
	SHOW_PASS="*****"
else
	SHOW_PASS=$USERPASS

fi
#-------web.conf stuff-------
LINE1="<CENTER><H1><font color=\"blue\"> SPLUNK LAB   </font></H1><br/></CENTER>"
#LINE1="<H1 style=\"text-align: left;\"><font color=\"#867979\"> SPLUNK LAB </font></H1>"
#&nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp;
LINE2="<H3 style=\"text-align: left;\"><font color=\"#867979\"> &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; Hostname: </font><font color=\"#FF9033\"> $fullhostname</font></H3>"
LINE3="<H3 style=\"text-align: left;\"><font color=\"#867979\"> &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; Host IP: </font><font color=\"#FF9033\"> $vip</font></H3></CENTER>"
LINE4="<H3 style=\"text-align: left;\"><font color=\"#867979\"> &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; Cluster Label: </font><font color=\"#FF9033\"> $cluster_label</font></H3><BR/></CENTER>"

LINE5="<H2><CENTER><font color=\"#867979\">User: </font> <font color=\"red\">$USERADMIN</font> &nbsp&nbsp<font color=\"#867979\">Password:</font> <font color=\"red\"> $SHOW_PASS</font></H2></font></CENTER><BR/>"
LINE6="<CENTER><font color=\"#867979\">Created using Splunk N' Box v$GIT_VER<BR/> Docker image [$SPLUNK_IMAGE]</font></CENTER>"

#configure the custom login screen and http access for ALL (no exception)
custom_web_conf="[settings]\nlogin_content=<div align=\"right\" style=\"border:1px solid blue;\"> $LINE1 $LINE2 $LINE3 $LINE4 $LINE5 $LINE6 </div> <p>This data is auto-generated at container build time (container internal IP=$container_ip)</p>\n\nenableSplunkWebSSL=0\n"

printf "$custom_web_conf" > $PROJ_DIR/web.conf
CMD=`docker cp $PROJ_DIR/web.conf $fullhostname:/opt/splunk/etc/system/local/web.conf`
#-------web.conf stuff-------

#make web.conf changes take effect!
if ( compare "$fullhostname" "DEMO-ES" ) || ( compare "$fullhostname" "DEMO-VMWARE" ) || ( compare "$fullhostname" "DEMO-PCI" ) ; then
	#pausing "30"
	restart_splunkd "$fullhostname"
        #printf "${Green}OK${NC}\n"
	#CMD=`docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk restart splunkweb -auth $USERADMIN:$USERPASS`
else
	#restarting splunkweb may not work with 6.5+
	CMD=`docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk restart splunkweb -auth $USERADMIN:$USERPASS`
fi

USERPASS="hello" #rest in case we just processed ES or VMWARE DEMOS
#set +x
return 0
}	#end custom_login_screen()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
assign_server_role() {		 ####### NOT USED YET ########

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#EXAMPLE:
#mhassan:~> docker exec -u splunk -ti SITE01-DMC01 cat /opt/splunk/etc/apps/splunk_management_console/lookups/assets.csv
#peerURI,serverName,host,machine,"search_group","_mkv_child","_timediff","__mv_peerURI","__mv_serverName","__mv_host","__mv_machine","__mv_search_group","__mv__mkv_child","__mv__timediff"
#"10.0.0.101:$MGMT_PORT","SITE01-LM01","SITE01-LM01","SITE01-LM01","dmc_group_license_master",0,,,,,,,,
#"10.0.0.102:$MGMT_PORT","SITE01-CM01","SITE01-CM01","SITE01-CM01","dmc_group_cluster_master",0,,,,,,,,
#"10.0.0.102:$MGMT_PORT","SITE01-CM01","SITE01-CM01","SITE01-CM01","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.107:$MGMT_PORT","SITE01-DEP01","SITE01-DEP01","SITE01-DEP01","dmc_group_deployment_server",0,,,,,,,,
#"10.0.0.108:$MGMT_PORT","SITE01-SH01","SITE01-SH01","SITE01-SH01","dmc_group_search_head",0,,,,,,,,
#"10.0.0.108:$MGMT_PORT","SITE01-SH01","SITE01-SH01","SITE01-SH01","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.108:$MGMT_PORT","SITE01-SH01","SITE01-SH01","SITE01-SH01","dmc_searchheadclustergroup_LABEL1",2,,,,,,,,
#"10.0.0.109:$MGMT_PORT","SITE01-SH02","SITE01-SH02","SITE01-SH02","dmc_group_search_head",0,,,,,,,,
#"10.0.0.109:$MGMT_PORT","SITE01-SH02","SITE01-SH02","SITE01-SH02","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.109:$MGMT_PORT","SITE01-SH02","SITE01-SH02","SITE01-SH02","dmc_searchheadclustergroup_LABEL1",2,,,,,,,,
#"10.0.0.110:$MGMT_PORT","SITE01-SH03","SITE01-SH03","SITE01-SH03","dmc_group_search_head",0,,,,,,,,
#"10.0.0.110:$MGMT_PORT","SITE01-SH03","SITE01-SH03","SITE01-SH03","dmc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.110:$MGMT_PORT","SITE01-SH03","SITE01-SH03","SITE01-SH03","dmc_searchheadclustergroup_LABEL1",2,,,,,,,,
#localhost,"SITE01-DMC01","SITE01-DMC01","SITE01-DMC01","dmc_group_search_head",0,,,,,,,,

#docker exec -u splunk -ti SITE01-DEP01 cat /opt/splunk/etc/apps/splunk_management_console/lookups/assets.csv
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
}	#end assign_server_role()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
make_dmc_search_peer() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Always check if $dmc exist before processing

dmc=$1; host=$2
#adding search peer in DMC
if [ -n "$dmc" ]; then
	bind_ip_host=`docker inspect --format '{{ .HostConfig }}' $host| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	CMD="docker exec -u splunk -ti $dmc /opt/splunk/bin/splunk add search-server -host $bind_ip_host:$MGMT_PORT -auth $USERADMIN:$USERPASS -remoteUsername $USERADMIN -remotePassword $USERPASS"
        OUT=`$CMD`
        OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
        printf "	${Yellow}${ARROW_EMOJI}${NC}Adding [$host] to DMC:[$dmc] " >&3 ; display_output "$OUT" "Peer added" "3"
        printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$dmc"
fi

return 0
} 	#end make_dmc_search_peer()
#---------------------------------------------------------------------------------------------------------------


###### CREATE CONTAINERS ########

#---------------------------------------------------------------------------------------------------------------
set_splunkweb_to_http() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function will reset splunkweb to http in case its https. Used with demos using https (ie ES)
fullhostname="$1"

custom_web_conf="[settings]\nenableSplunkWebSSL=0\n"

printf "$custom_web_conf" > $PROJ_DIR/web.conf.demo
CMD="docker cp $PROJ_DIR/web.conf.demo $fullhostname:/opt/splunk/etc/system/local/web.conf" ; OUT=`$CMD`
printf "${DarkGray}CMD:[$CMD]${NC}>>[$OUT]\n" >&4
printf "	${Yellow}${ARROW_EMOJI}${NC}Configuring demo to be viewed on http://$fullhostname:$SPLUNKWEB_PORT_EXT ${Green} Done!${NC}\n" >&3

#if ( compare "$fullhostname" "DEMO-ES" ) || ( compare "$fullhostname" "DEMO-ITSI" ) ;then
#	USERPASS="changeme"
#fi
pausing "30"
restart_splunkd "$fullhostname"

#restarting splunkweb may not work with 6.5+
#while splunkd is not running
#CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk restart -auth $USERADMIN:$USERPASS" ; OUT=`$CMD`; display_output "$OUT" "has been restarted" "3"


return 0
}	#end set_splunkweb_to_http()
#---------------------------------------------------------------------------------
#--------------------------------------------
is_container_running() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

check_load              #throttle back if high load
#-----check if container is running--------
#check if bind IP is used by new container (indicating it's running)
is_running=`docker ps --format '{{.Names}}' --filter status=running --filter name="$1" `
if [ -z "$is_running" ]; then   #check if not empty
    return 1    #empty / not running
else
    return 0    #not empty / container is running
fi
}   #end is_container_running()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
calc_next_seq_fullhostname_ip() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

basename=$1		#input
count=$2		#input
#vip			#output global
#fullhostname	#output global

#---- calculate sequence numbers -----------[in:basename out: startx, endx]
#get last seq used by last host created
last_host_num=`docker ps -a --format "{{.Names}}"|$GREP "^$basename"|head -1| $GREP -P '\d+(?!.*\d)' -o`;
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
if [ "$starting" -lt "10" ]; then  startx="0$starting"; else  startx="$starting";  fi
if [ "$ending" -lt "10" ]; then endx="0$ending"; else endx=$ending; fi

printf "${DarkGray}Next sequence:${NC} [${Green}$basename${Yellow}$startx${NC} --> ${Green}$basename${Yellow}$endx${NC}]\n"  >&4
#---- end calculate sequence numbers -----------

#---- calculate VIP numbers -----------
base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `;  #base_ip=$base_ip"."

#Find last container created IP (not hostname/sitename dependent).
#Returns value only if last container has bind IP assigned (which excludes containers not built by this script)
containers_count=`docker ps -aq | wc -l|awk '{print $1}' `
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} last ip used:[$last_ip_used]\n" >&5
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} containers_count:[$containers_count]\n" >&5

#get last octet4 used ----
if [ "$containers_count" == 0 ]; then       #nothing created yet!
        last_used_octet4=`echo $START_ALIAS | cut -d"." -f4 `
        last_ip_used="$base_ip.$start_octet4"
        printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} NO HOSTS EXIST! [containers_count:$containers_count] [last ip used:$last_ip_used][last_octet4:$last_used_octet4]\n" >&5

elif [ "$containers_count" -gt "0" ]; then
	#last_ip_used=`docker inspect --format '{{ .HostConfig }}' $(docker ps -aql)|$GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	#last_ip_used=`docker inspect --format='{{(index (index .NetworkSettings.Ports "8000/tcp") 0).HostIp}}' $(docker ps -aq) 2>/dev/null | sort -u |tail -1`
	last_ip_used=`docker inspect --format '{{ .HostConfig }}' $(docker ps -aq)| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+ 8000'|cut -d" " -f 1|sort -u|tail -1`

	if [ -n "$last_ip_used" ]; then
        	last_used_octet4=`echo $last_ip_used |cut -d"." -f4`
	else
		printf "${NC}\n"
		printf "Use option ${Yellow}1)${NC} SHOW all containers... ${Red}above to see the offending container(s). Exiting...${NC}\n"
	#	exit
	fi
        printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}SOME HOSTS EXIST. [containers_count:$containers_count][last ip used:$last_ip_used][last_octet4:$last_used_octet4]\n" >&5
fi
#---- calculate VIP numbers -----------

#---- build fullhostname (Base+seq & VIP) -----------
octet4=$last_used_octet4
x=${starting}
#fix the digits size first
if [ "$x" -lt "10" ]; then
   		host_num="0"$x         		 #always reformat number to 2-digits if less than 2-digits
else
    	host_num=$x             	#do nothing
fi
if ( compare "$basename" "DEMO" ) || ( compare "$basename" "WORKSHOP" ) ; then
	fullhostname="$basename""_"$host_num  	#demos user under score
else
	fullhostname="$basename"$host_num  	#create full hostname (base + 2-digits)
fi

#------ VIP processing ------
octet4=`expr $octet4 + 1`       	#increment octet4
vip="$base_ip.$octet4"            	#build new IP to be assigned
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}fulhostname:[$fullhostname] vip:[$vip] basename:[$basename] count[$count] ${NC}\n" >&5


#---- build fullhostname (Base+seq & VIP) -----------

return 0
}	#calc_next_seq_fullhostname_ip()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
create_splunk_container() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates generic splunk containers. Role is assigned later
#inputs:$1:basehostname: (ex IDX, SH,HF) just the base (no numbers)
#	 	$2:hostcount:     how many containers to create from this host type (ie name)
#	 	$3:lic_master		if provided dont copy license, make host license-slave
# 	 	$4:cluster_label	cluster label in web.conf, use if provided
#outputs: $gLIST:  global var compare the list of hostname just got created

basename=$1; hostcount=$2; lic_master=$3; cluster_label=$4
count=0;starting=0; ending=0;basename=$BASEHOSTNAME;  octet4=0
gLIST=""   #build global list of hosts created by this session. Used somewhere else

#Another method to figure out the starting octet4
# OCTET4FILE=`iptables -t nat -L |$GREP DNAT | awk '{print $5}'  | sort -u|tail -1|cut -d"." -f4`
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}  basename[$basename]  hostcount[$hostcount] ${NC}\n" >&5

#---If not passed; prompt user to get basename and count ----
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

if [ -z "$2" ]; then
        read -p ">>>> How many hosts to create (default 1)? " count
		if [ -z "$count" ]; then count=1;  fi  #user accepted default 1
else
        count=$2
fi
#---If not passed; prompt user to get basename and count ----

#--------------------
#Create master container (for docker monitoring). Created only once in the entire system
#master_container_exists=`docker ps -a| grep -i "$MASTER_CONTAINER" `
#Build MONITOR if does not exist
#if [ -z "$master_container_exists" ]; then
#	construct_splunk_container "$base_ip.$docker_mc_start_octet4" "$MASTER_CONTAINER"
#	bind_ip_monitor=`docker inspect --format '{{ .HostConfig }}' $MASTER_CONTAINER| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
#fi
#--------------------

for (( a = 1; a <= count; a++ ))  ; do
	calc_next_seq_fullhostname_ip "$basename" "$count"	#function will return global $vip
	construct_splunk_container $vip $fullhostname $lic_master $cluster_label $bindip_monitor
	gLIST="$gLIST""$fullhostname "		#append last host create to the global LIST
done

gLIST=`echo $gLIST |sed 's/;$//'`	#GLOBAL! remove last space (causing host to look like "SH "
#echo "gLIST[$gLIST]"; exit

return $host_num
}	#end of create_splunk_container()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
#build_dot_file() {
##### place holder for future use ####

#}	#end build_dot_file()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
construct_splunk_container() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates single splunk container using $vip and $hostname
#inputs:
#	$1: container's IP to use (nated IP aka as bind IP)
#	$2: fullhostname:  container name (may include site and host number sequence)
#	$3: lic_master
#	$4: cluster_label
#	$5: MONITOR-DOCKER container IP
#
#output:
#	-create single host. will not prompt user for any input data
#	-reset password and setup splunk's login screen
#   -configure container's OS related items if needed

START=$(date +%s);
vip=$1;  fullhostname=$2;lic_master=$3; cluster_label=$4;
fullhostname=`echo $fullhostname| tr -d '[[:space:]]'`	#trim white space if they exist

check_load		#throttle back if high load

#echo "fullhostname[$fullhostname]"
#rm -fr $MOUNTPOINT/$fullhostname
#mkdir -m 755 -p $MOUNTPOINT/$fullhostname
#note:volume bath is relative to VM not MacOS

#At this point fullhostname (w/ seq num) has been assigned. Use it to figure out what image to use!
#watch out for original names ending with numbers!
if ( compare "$fullhostname" "DEMO" ) || ( compare "$fullhostname" "WORKSHOP" ) ; then
	#extract image name from fullhostname  (ex: DEMO-OI_02, WORKSHOP-SPLUNKLIVE-2017_02)
	demo_image_name=$(printf '%s' "$fullhostname" | sed 's/_[0-9]*//g') #remove last _02
	demo_image_name=`echo $demo_image_name| tr '[A-Z]' '[a-z]'`		#conver to lower case
	full_image_name="$SPLUNK_DOCKER_HUB/sales-engineering/$demo_image_name"
else
	full_image_name="$DEFAULT_SPLUNK_IMAGE"
fi

#echo "fullhostname:[$fullhostname]    demo_image_name:[$demo_image_name]"
#CMD="docker run -d -v $MOUNTPOINT/$fullhostname/opt/splunk/etc -v $MOUNTPOINT/$fullhostname/opt/splunk/var --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER  -p $vip:$SPLUNKWEB_PORT:$SPLUNKWEB_PORT_EXT -p $vip:$HEC_PORT:$HEC_PORT -p $vip:$MGMT_PORT:$MGMT_PORT -p $vip:$SSHD_PORT:$SSHD_PORT -p $vip:$RECV_PORT:$RECV_PORT -p $vip:$REPL_PORT:$REPL_PORT -p $vip:$APP_SERVER_PORT:$APP_SERVER_PORT -p $vip:$APP_KEY_VALUE_PORT:$APP_KEY_VALUE_PORT --env SPLUNK_START_ARGS="--accept-license" --env SPLUNK_ENABLE_LISTEN=$RECV_PORT --env SPLUNK_SERVER_NAME=$fullhostname --env SPLUNK_SERVER_IP=$vip $full_image_name"
#CMD="docker run -d -v $MOUNTPOINT/$fullhostname/etc:/opt/splunk/etc -v  $MOUNTPOINT/$fullhostname/var:/opt/splunk/var \

CMD="docker run -d \
	--network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER \
	-p $vip:$SPLUNKWEB_PORT:$SPLUNKWEB_PORT_EXT -p $vip:$MGMT_PORT:$MGMT_PORT -p $vip:$SSHD_PORT:$SSHD_PORT -p $vip:$HEC_PORT:$HEC_PORT \
	-p $vip:$RECV_PORT:$RECV_PORT -p $vip:$REPL_PORT:$REPL_PORT -p $vip:$APP_SERVER_PORT:$APP_SERVER_PORT \
	-p $vip:$APP_KEY_VALUE_PORT:$APP_KEY_VALUE_PORT --env SPLUNK_START_ARGS="--accept-license" \
	--env SPLUNK_ENABLE_LISTEN=$RECV_PORT --env SPLUNK_SERVER_NAME=$fullhostname \
	--env SPLUNK_SERVER_IP=$vip --env SPLUNK_USER="splunk"  $full_image_name"

#-v $MOUNTPOINT/$fullhostname/etc:/opt/splunk/etc -v  $MOUNTPOINT/$fullhostname/var:/opt/splunk/var \

if [ "$fullhostname" == "$MASTER_CONTAINER" ]; then
	printf "[${LightGreen}$fullhostname${NC}:${Green}$vip${NC}] ${Yellow}Creating docker monitor container.This is created once in the entire system! ${NC} "
else
	printf "[${LightGreen}$fullhostname${NC}:${Green}$vip${NC}] ${LightBlue}Creating new splunk docker container ${NC} "
fi
OUT=`$CMD` ; display_output "$OUT" "" "2"
#CMD=`echo $CMD | sed 's/\t//g' `;
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$fullhostname"

if [ "$os" == "Darwin" ]; then
	pausing "30"
else
	pausing "15"
fi

#-----check if container is running--------
printf "	${Yellow}${ARROW_EMOJI}${NC}Verifying that container is running..." >&3
if ! ( is_container_running "$fullhostname" ); then
	printf "${Red}NOT RUNNING!${NC}\n" >&3
else
	printf "${Green}${OK_MARK_EMOJI} OK${NC}\n" >&3
fi

#-----check if splunkd is running--------
is_splunkd_running "$fullhostname"

#Do not add license file to DEMO containers. They are shipped with their own
if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) ; then
	true
else
	add_license_file $fullhostname
fi

#custom_login_screen() will not change pass for DEMO-ES* or DEMO-VMWARE*
printf "	${Yellow}${ARROW_EMOJI}${NC}Splunk initialization (password, licenses, custom screen, http)..." >&3
custom_login_screen "$vip" "$fullhostname"

#Misc OS stuff
if [ -f "$PWD/containers.bashrc" ]; then
	printf "	${Yellow}${ARROW_EMOJI}${NC}Copying $PWD/containers.bashrc to $fullhostname:/root/.bashrc\n" >&4
       	CMD=`docker cp $PWD/containers.bashrc $fullhostname:/root/.bashrc`
fi
if [ -f "$PWD/containers.vimrc" ]; then
	printf "	${Yellow}${ARROW_EMOJI}${NC}Copying $PWD/containers.vimrc to $fullhostname:/root/.vimrc\n" >&4
       	CMD=`docker cp $PWD/containers.vimrc $fullhostname:/root/.vimrc`
fi
#printf "	${Yellow}${ARROW_EMOJI}${NC}Building graphviz dot file ...\n" >&4
#build_dot_file
##clear
#dot -Gnewrank -Tpng  file.dot -o test.png
#open test.png
#sleep 1
#catimg test.png

#DNS stuff to be used with dnsmasq. Need to revisit for OSX  9/29/16
#Enable for Linux at this point
#if [ "$os" == "Linux" ]; then
#	printf "	${Yellow}${ARROW_EMOJI}${NC}Updating dnsmasq records[$vip  $fullhostname]..." >&3
#	if [ ! -f $HOSTSFILE ]; then
#		touch $HOSTSFILE
#	fi
#	if [ $(cat $HOSTSFILE | $GREP $fullhostname | wc -l | sed 's/^ *//g') != 0 ]; then
#        	printf "\t${Red}[$fullhostname] is already in the hosts file. Removing...${NC}\n" >&4
#        	cat $HOSTSFILE | $GREP -v $vip | sort > tmp && mv tmp $HOSTSFILE
#	fi
#	printf "${Green}${OK_MARK_EMOJI} OK${NC}\n" >&3
#	printf "$vip\t$fullhostname\n" >> $HOSTSFILE
#	sudo killall -HUP dnsmasq	#must refresh to read $HOSTFILE file
#fi

return 0
}	#end construct_splunk_container()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_demo_container_from_list() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
#-----------show images details
printf "${BoldYellowOnBlue}Manage containers -> CREATE & DOWNLOAD SPLUNK'S DEMO CONTAINERS MENU ${NC}\n"
display_stats_banner
printf "\n"
printf "Demo images available from $SPLUNK_DOCKER_HUB:\n"
printf "${Purple}     		IMAGE NAME${NC}		    CREATED	SIZE			AUTHOR\n"
printf "${Purple} -------------------------------------${NC}   ------------  --------   ---------------------------------------\n"

#---Scan demos images from $REPO_DEMO_IMAGES ---------
counter=1
#count=`docker images --format "{{.ID}}" | wc -l`
for image_name in $REPO_DEMO_IMAGES; do
        printf "${Purple}%-2s${NC}) ${Purple}%-40s${NC}" "$counter" "$image_name"
	image_name="$SPLUNK_DOCKER_HUB/sales-engineering/$image_name"
#	echo "cached[$cached]\n"
	created=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $7,$8}'`
        if [ -n "$created" ]; then
        	author=`docker inspect $image_name |grep -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
                printf "%-12s %-7s %-10s ${NC}\n" "$created" "$size" "$author"
        else
                printf "${DarkGray}NOT CACHED! ${NC}\n"
        fi
        let counter++
done
#---Scan demos images from $REPO_DEMO_IMAGES ---------


#build array of RUNNING demo containers
declare -a list=($REPO_DEMO_IMAGES)

echo
choice=""
read -p $'Choose number to create. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi
if [ -n "$choice" ]; then
	read -p "How many containers to create of selected demo [default 1]? " number
	if [ "$number" == "" ]; then  number=1; fi
        printf "     **PLEASE WATCH THE LOAD AVERAGE CLOSELY**\n\n"
        printf "${Yellow}Creating selected demo containers(s)...${NC}\n"
        for id in `echo $choice`; do
		image_name=(${list[$id - 1]})
        	if [ -z "$cached" ]; then
			progress_bar_image_download "$image_name"
        	fi
        	#echo "$id : ${list[$id - 1]}"
       		printf "${NC}Using ${Purple}[$id:$image_name]:${NC}"; display_stats_banner "short"
        	create_splunk_container "$image_name" "$number"
        done
else
	printf "${DONT_ENTER_EMOJI}${LightRed} WARNING! \n"
	printf "This operation will stress your system. Make sure you have enough resources...${NC}\n"
        read -p "Are you sure? [y/N]? " answer
        printf "         **PLEASE WATCH THE LOAD AVERAGE CLOSELY**\n\n"
        if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
        	printf "${Yellow}Creating all demo containers(s)...\n${NC}"
                for i in $REPO_DEMO_IMAGES; do
			progress_bar_image_download "$i"
                        printf "${NC}Using ${Purple}[$i${NC}]"; display_stats_banner "short"
                	create_splunk_container "$i" "1"
			pausing "30"
                done
	fi
fi
return 0
}	#end create_demo_container_from_list()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
construct_3rdp_container_from_image() {
#This function creates single 3rd party container using $vip and $hostname
image_name=$1      #example  johndoe/mysql

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
START=$(date +%s);

check_load              #throttle back if high load
mkdir -m 777 -p $MOUNTPOINT/$fullhostname

#extract basename from full image name
basename=`echo $image_name | sed 's/^.*\///g' | tr '[a-z]' '[A-Z]' `
basename="3RDP-$basename"

cached=`docker images|grep $image_name`
if [ -z "$cached" ]; then
        progress_bar_image_download "$image_name"
fi

calc_next_seq_fullhostname_ip "$basename" "1"	#returns fullhostname & vip
#echo "image:[$image_name]   base:[$basename]   full:[$fullhostname]   vip:[$vip]"

if ( compare "$basename" "MYSQL" ); then
#https://hub.docker.com/_/mysql/
	CMD="docker run -d --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname \
	--dns=$DNSSERVER -p $vip:$MYSQL_PORT:$MYSQL_PORT \
	--env MYSQL_DATABASE="mydatabase" --env MYSQL_USER="guest" --env MYSQL_PASSWORD="my-secret-pw" \
	--env MYSQL_ROOT_PASSWORD="my-secret-pw" $image_name"

#https://github.com/sequenceiq/hadoop-docker/blob/master/Dockerfile
elif ( compare "$basename" "HADOOP-DOCKER" ); then
	CMD="docker run -d --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER \
	-p $vip:50010:50010 -p $vip:50020:50020 -p $vip:50070:50070 -p $vip:50075:50075 -p $vip:50090:50090 \
	-p $vip:8020:8020 -p $vip:9000:9000 -p $vip:10020:10020 -p $vip:19888:19888 -p $vip:8030:8030 \
	-p $vip:8031:8031 -p $vip:8032:8032 -p $vip:8033:8033 -p $vip:8040:8040 -p $vip:8042:8042 \
	-p $vip:8088:8088 -p $vip:49707:49707 -p $vip:2122:2122 $image_name"
	HTTP_PORTS="Hadoop:50090 Hadoop:8042  Hadoop:8088"
#https://github.com/caioquirino/docker-cloudera-quickstart/blob/master/Dockerfile
elif ( compare "$basename" "DOCKER-CLOUDERA-QUICKSTART" ); then
	CMD="docker run -d --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER \
	 -p $vip:2181:2181 -p $vip:8020:8020 -p $vip:8888:8888 -p $vip:11000:11000 -p $vip:11443:11443 \
	 -p $vip:9090:9090 -p $vip:8088:8088 -p $vip:19888:19888 -p $vip:9092:9092 -p $vip:8983:8983 \
	 -p $vip:16000:16000 -p $vip:16001:16001 -p $vip:42222:22 -p $vip:8042:8042 -p $vip:60010:60010 \
	 -p $vip:8080:8080 -p $vip:7077:7077 $image_name"
	HTTP_PORTS="Hue:8888 Hadoop:8088 Cluster:8042 HBase:60010 Spark:8080"

elif ( compare "$basename" "ORACLE" ); then
	printf "${Red}*** not yet ***${NC}\n"
	#CMD="docker run -d --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER -p $vip:$MYSQL_PORT:$MYSQL_PORT --env MYSQL_DATABASE="mydatabase" --env MYSQL_USER="guest" --env MYSQL_PASSWORD="my-secret-pw" --env MYSQL_ROOT_PASSWORD="my-secret-pw" $image_name"
#http://elk-docker.readthedocs.io/
elif ( compare "$basename" "ELK" );  then
	CMD="docker run -d --network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER \
	-p $vip:5601:5601 -p $vip:9200:9200 -p $vip:5044:5044 -p $vip:9300:9300 $image_name"
	HTTP_PORTS="Kibana web:5601 Elasticsearch JSON:9200 Logstash Beats:5044"
else
	printf "${Red}*** No configuration for this 3rd party container yet ***${NC}\n"
	return 0
fi
printf "[${LightGreen}$fullhostname${NC}:${Green}$vip${NC}] ${LightBlue}Creating new 3rd party docker container ${NC} "
OUT=`$CMD` ; display_output "$OUT" "" "2"
#CMD=`echo $CMD | sed 's/\t//g' `;
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&2	#always show how 3rd party created. They are not not same
logline "$CMD" "$fullhostname"

if [ "$os" == "Darwin" ]; then
        pausing "30"
else
        pausing "15"
fi

#-----check if container is running--------
printf "	${Yellow}${ARROW_EMOJI}${NC}Verifying that container is running..." >&3
if ! ( is_container_running "$fullhostname" ); then
	printf "${Red}NOT RUNNING!${NC}\n" >&3
else
	printf "${Green}${OK_MARK_EMOJI} OK${NC}\n" >&3
fi

return 0
}	#end construct_3rdp_container_from_image()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_3rdp_container_from_list() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
#-----------show images details
printf "${BoldYellowOnBlue}Manage containers -> CREATE 3RD PARTY CONTAINER MENU ${NC}\n"
display_stats_banner
printf "\n"
printf "${BrownOrange}*Depending on the time of the day downloads may a take long time.Cached images are not downloaded! ${NC}\n"
printf "\n"
printf "3rd party images available from docker hub:\n"
printf "${Purple}     IMAGE\t\t\t${NC}    CACHED INFO\t\t\t\t CREATED BY\n"
printf "${Purple} -----------\t\t ${NC}---------------------------- \t\t ----------------------------- \n"
#display all 3rd party images---------
counter=1
for i in `echo $REPO_3RDPARTY_IMAGES ` ; do
        printf "${Purple}$counter${NC})${Purple} $i${DarkGray}\t\t"
        cached=`docker images|grep $i| awk '{print $4,$5,$6" "$7,$8}'`
        if [ -n "$cached" ]; then
                author=`docker inspect $i|grep -i author|cut -d":" -f1-3|sed 's/,//g'`
                printf "${White}$cached $author${NC}\n"
        else
                printf "${DarkGray}NOT CACHED!${NC}\n"
        fi
        let counter++
done

#build array of 3rd party images from disk [3rd-mysql 3rd-orcale 3rd-elk]
declare -a list=($REPO_3RDPARTY_IMAGES)
echo
choice=""
read -p $'Choose number to create. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
        printf "    **PLEASE WATCH THE LOAD AVERAGE CLOSELY**\n\n"
        printf "${Yellow}Creating selected 3rd party containers(s)...${NC}\n"
        for id in `echo $choice`; do
                image_name=(${list[$id - 1]})
                cached=`docker images|grep $image_name`
                if [ -z "$cached" ]; then
                printf "${NC}Using ${Purple}[$id:$image_name]:${NC}\n"
                        progress_bar_image_download "$image_name"
                fi
                #echo "$id : ${list[$id - 1]}"
                printf "${NC}Using ${Purple}[$id:$image_name]:${NC}"; display_stats_banner "short"
                construct_3rdp_container_from_image "$image_name" "1"
        done
else
		printf "${DONT_ENTER_EMOJI}${LightRed} WARNING! \n"
        printf "This operation will stress your system. Make sure you have enough resources...${NC}\n"
        read -p "Are you sure? [y/N]? " answer
        printf "    **PLEASE WATCH THE LOAD AVERAGE CLOSELY**\n\n"
        if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                printf "${Yellow}Creating all 3rd party containers(s)...\n${NC}"
                for image_name in $REPO_3RDPARTY_IMAGES; do
                       # progress_bar_image_download "$image_name"
                        printf "${NC}Using ${Purple}[$image_name${NC}]"; display_stats_banner "short"
                	construct_3rdp_container_from_image "$image_name" "1"
                done
        fi
fi
return 0
}	#end create_3rdp_container_from_list()
#---------------------------------------------------------------------------------------------------------------


##### MENUS HELP ####

#---------------------------------------------------------------------------------------------------------------
display_clustering_menu_help() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${White}CLUSTERING MENU HELP:\n\n${NC}"
printf "\n"
printf "Under construction!\n";echo
printf "Documentaion can be viewed here:\n\n"
printf "https://github.com/mhassan2/splunk-n-box\n";echo
return 0
}	#end display_clustering_menu_help()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_demos_menu_help() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${White}DEMO MENU HELP:\n\n${NC}"
printf "\n"
printf "Under construction!\n";echo
printf "Documentaion can be viewed here:\n\n"
printf "https://github.com/mhassan2/splunk-n-box\n";echo
return 0
}	#end display_demos_menu_help()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_3rdparty_menu_help() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${White}3RD PARTY MENU HELP:\n\n${NC}"
printf "\n"
printf "Under construction!\n";echo
printf "Documentaion can be viewed here:\n\n"
printf "https://github.com/mhassan2/splunk-n-box\n";echo
return 0
}	#end display_3rdparty_menu_help()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_splunk_menu_help() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${White}SPLUNK MENU HELP:\n\n${NC}"
printf "\n"
printf "Documentaion can be viewed here:\n\n"
printf "https://github.com/mhassan2/splunk-n-box\n";echo
return 0
}	#end display_splunk_menu_help()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_system_menu_help() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${White}SYSTEM MENU HELP:\n\n${NC}"
printf "\n"
printf "Documentaion can be viewed here:\n\n"
printf "https://github.com/mhassan2/splunk-n-box\n";echo
return 0
}	#end display_system_menu_help()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_main_menu_help() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${White}MAIN MENU HELP:\n\n${NC}"
printf "\n"
printf "Documentaion can be viewed here:\n\n"
printf "https://github.com/mhassan2/splunk-n-box\n";echo
read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
return 0
}	#end display_main_menu_help()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
docker_status() {
dockerinfo=`docker info|head -5|sed -e 's/^M//g'|tr -d '\r'|awk '{printf  "\033[1;1;5;46m" $1 "\033[1;31m" $2 "\033[1;1;5;46m " "\033[0m"}'`
dockerinfo_str="${LightRed}[$dockerinfo]    "
dockerinfo_str="      ${YELLOW}[${NC}$dockerinfo${BoldWhiteOnTurquoise}${Yellow}]${NC}\n"
printf "$dockerinfo_str"
}
#---------------------------------------------------------------------------------------------------------------

#### DISPLAY MENU OPTIONS #####

#---------------------------------------------------------------------------------------------------------------
display_main_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function displays user options for the main menu
clear
printf "${BoldWhiteOnTurquoise}Splunk n' Box v$GIT_VER: ${Yellow}MAIN MENU "; docker_status
display_stats_banner

tput cup 5 25
tput rev  # Set reverse video mode
printf "${BoldYellowOnWhite} M A I N - M E N U ${NC}\n"
tput sgr0

tput cup 7 15; printf "${LightCyan}1${NC}) ${LightCyan}Manage All Containers & Images ${NC}\n"
tput cup 8 15; printf "${LightCyan}2${NC}) ${LightCyan}Manage Lunch & Learn Containers ${NC}\n"
tput cup 9 15; printf "${LightCyan}3${NC}) ${LightCyan}Manage Splunk Clusters${NC}\n"
tput cup 10 15; printf "${LightCyan}4${NC}) ${LightCyan}Manage Splunk Demos ${DarkGray}[**internal use only**]${NC}\n"
tput cup 11 15; printf "${LightCyan}5${NC}) ${LightCyan}Manage 3Rd Party Containers & Images ${DarkGray}[**under construction**]${NC}\n"
tput cup 12 15; printf "${LightCyan}6${NC}) ${LightCyan}Manage System ${NC}\n"
tput cup 13 15; printf "${LightCyan}7${NC}) ${LightCyan}Change Log Level ${NC}\n"
tput cup 14 15; printf "${LightCyan}?${NC}) ${LightCyan}Help ${NC}\n"
tput cup 15 15; printf "${LightCyan}Q${NC}) ${LightCyan}Quit ${NC}\n"

# Set bold mode
tput bold
tput cup 16 15
#read -p "Enter your choice [1-5] " choice
#printf "Enter your choice [1-5] "

#tput clear
tput sgr0
#tput rc

return 0
}	#end display_main_menu_options()
#---------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------
display_splunk_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
dockerinfo=`docker info|head -5| tr '\n' ' '|sed 's/: /:/g'`
printf "${BoldWhiteOnTurquoise}Splunk n' Box v$GIT_VER: ${Yellow}MAIN MENU -> SPLUNK MENU"; docker_status
display_stats_banner
printf "\n\n"
printf "${BoldWhiteOnRed}Manage Images:${NC}\n"
printf "${Red}S${NC}) ${Red}S${NC}HOW all images details ${DarkGray}[custom view]${NC}\n"
printf "${Red}R${NC}) ${Red}R${NC}EMOVE image(s) to recover disk-space (will extend build times) ${DarkGray}[docker rmi --force \$(docker images)]${NC}\n"
printf "${Red}F${NC}) DE${Red}F${NC}AULT Splunk images ${DarkGray}[currently: $DEFAULT_SPLUNK_IMAGE]${NC}\n"
printf "\n"
printf "${BoldWhiteOnYellow}Manage Containers:${NC}\n"
printf "${Yellow}C${NC}) ${Yellow}C${NC}REATE generic Splunk container(s) ${DarkGray}[docker run ...]${NC}\n"
printf "${Yellow}L${NC}) ${Yellow}L${NC}IST all containers ${DarkGray}[custom view]${NC} \n"
printf "${Yellow}P${NC}) STO${Yellow}P${NC} container(s) ${DarkGray}[docker stop \$(docker ps -aq)]${NC}\n"
printf "${Yellow}T${NC}) S${Yellow}T${NC}ART container(s) ${DarkGray}[docker start \$(docker ps -a --format \"{{.Names}}\")]${NC}\n"
printf "${Yellow}D${NC}) ${Yellow}D${NC}ELETE container(s) & Volumes(s)${DarkGray} [docker rm -vf \$(docker ps -aq)]${NC}\n"
printf "${Yellow}H${NC}) ${Yellow}H${NC}OSTS grouped by role ${DarkGray}[works only if you followed the host naming rules]${NC}\n"
printf "\n"
echo
printf "${BoldWhiteOnGreen}Manage system:${NC}\n"
printf "${Green}B${NC}) ${Green}B${NC}ACK to MAIN menu\n"
printf "${Green}?${NC}) ${Green}H${NC}ELP!\n"

return 0
}	#end display_splunk_menu_options()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_system_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
dockerinfo=`docker info|head -5| tr '\n' ' '|sed 's/: /:/g'`
printf "${BoldWhiteOnTurquoise}Splunk n' Box v$GIT_VER: ${Yellow}MAIN MENU -> SYSTEM MENU"; docker_status
display_stats_banner
printf "\n\n"

printf "${BoldWhiteOnGreen}Manage System:${NC}\n"
printf "${Green}R${NC}) ${Green}R${NC}emove IP aliases on the Ethernet interface [${White}not recommended${NC}]${NC}\n"
printf "${Green}M${NC}) ${Green}M${NC}ONITOR SYSTEM resources [${White}CTRL-C to exit${NC}]${NC}\n"
printf "${Green}W${NC}) ${Green}W${NC}ipe clean any configurations/changes made by this script [${White}not recommended${NC}]${NC}\n"
printf "${Green}S${NC}) ${Green}S${NC}HOW docker disk space usage [need v1.13.1+]${NC}\n"
printf "${Green}C${NC}) ${Green}C${NC}LEAN docker disk space [need v1.13.1+]${NC}\n"
printf "\n"
printf "${Green}B${NC}) ${Green}B${NC}ACK to MAIN menu\n"
printf "${Green}?${NC}) ${Green}H${NC}ELP!\n"

return 0
}	#end display_system_menu_options()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_demos_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
printf "${BoldWhiteOnTurquoise}Splunk n' Box v$GIT_VER: ${Yellow}MAIN MENU -> DEMOs MENU"; docker_status
display_stats_banner
printf "\n"
echo
printf "${BoldWhiteOnRed}Manage Demo Images:${NC}\n"
printf "${Red}X${NC}) Download ONLY demo images [use this option to cache demo images] ${NC} \n"
printf "${Red}S${NC}) ${Red}S${NC}HOW all downloaded demo images ${NC} \n"
printf "${Red}R${NC}) ${Red}R${NC}EMOVE demo image(s)\n"
printf "\n"
printf "${BoldWhiteOnYellow}Manage Demo Containers:${NC}\n"
printf "${Yellow}C${NC}) ${Yellow}C${NC}REATE Splunk demo container from available list${NC}\n"
printf "${Yellow}L${NC}) ${Yellow}L${NC}IST demo container(s) ${NC}\n"
printf "${Yellow}P${NC}) STO${Yellow}P${NC} demo container(s) ${NC}\n"
printf "${Yellow}T${NC}) S${Yellow}T${NC}ART demo container(s) ${NC}\n"
printf "${Yellow}D${NC}) ${Yellow}D${NC}ELETE demo container(s)${NC}\n"
printf "${Yellow}A${NC}) ${Yellow}A${NC}DD common utils to demo container(s) [${White}useful if you need command line access${NC}]${NC}\n"
echo
printf "${BoldWhiteOnGreen}Manage system:${NC}\n"
printf "${Green}B${NC}) ${Green}B${NC}ACK to MAIN menu\n"
printf "${Green}?${NC}) ${Green}H${NC}ELP!\n"

return 0
}	#end display_demos_menu_options()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
display_3rdparty_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnTurquoise}Splunk n' Box v$GIT_VER: ${Yellow}MAIN MENU -> 3RD PARTY MENU"; docker_status
display_stats_banner
printf "\n"
echo
printf "${BoldWhiteOnRed}Manage 3rd Party Images:${NC}\n"
printf "${Red}X${NC}) Download ONLY 3rd party images [use this option to cache demo images] ${NC} \n"
printf "${Red}S${NC}) ${Red}S${NC}HOW all downloaded 3rd party images ${NC} \n"
printf "${Red}R${NC}) ${Red}R${NC}EMOVE 3rd party image(s)\n"
echo
printf "${BoldWhiteOnYellow}Manage 3rd Party containers:${NC}\n"
printf "${Yellow}C${NC}) ${Yellow}C${NC}REATE 3rd party container from available list${NC}\n"
printf "${Yellow}L${NC}) ${Yellow}L${NC}IST 3rd party container(s) ${NC}\n"
printf "${Yellow}P${NC}) STO${Yellow}P${NC} 3rd party container(s) ${NC}\n"
printf "${Yellow}T${NC}) S${Yellow}T${NC}ART 3rd party container(s) ${NC}\n"
printf "${Yellow}D${NC}) ${Yellow}D${NC}ELETE 3rd party container(s)${NC}\n"
#printf "${Yellow}A${NC}) ${Yellow}A${NC}DD common utils to 3rd party container(s) [${White}not recommended${NC}]${NC}\n"
echo
printf "${BoldWhiteOnGreen}Manage system:${NC}\n"
printf "${Green}B${NC}) ${Green}B${NC}ACK to MAIN menu\n"
printf "${Green}?${NC}) ${Green}H${NC}ELP!\n"

return 0
}	#end display_3rdparty_menu_options()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_clustering_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnTurquoise}Splunk n' Box v$GIT_VER: ${Yellow}MAIN MENU -> CLUSTERING MENU"; docker_status
display_stats_banner
printf "\n"
echo
printf "${BoldWhiteOnBlue}AUTOMATIC BUILDS (components: R3/S2 1-CM 1-DEP 1-DMC 1-UF 3-SHC 3-IDXC): ${NC}\n"
printf "${LightBlue}1${NC}) Create Stand-alone Index Cluster (IDXC)${NC}\n"
printf "${LightBlue}2${NC}) Create Stand-alone Search Head Cluster (SHC)${NC}\n"
printf "${LightBlue}3${NC}) Build Single-site Cluster${NC}\n"
printf "${LightBlue}4${NC}) Build Multi-site Cluster (3 sites)${NC} \n";echo

printf "${BoldWhiteOnYellow}MANUAL BUILDS (specify base host-names and counts): ${NC}\n"
printf "${Yellow}5${NC}) Create Manual Stand-alone Index cluster (IDXC)${NC}\n"
printf "${Yellow}6${NC}) Create Manual Stand-alone Search Head Cluster (SHC)${NC}\n"
printf "${Yellow}7${NC}) Build Manual Single-site Cluster${NC}\n"
printf "${Yellow}8${NC}) Build Manual Multi-site Cluster${NC} \n"
echo
printf "${Green}B${NC}) ${Green}B${NC}ACK to MAIN menu\n"
printf "${Green}?${NC}) ${Green}H${NC}ELP!\n"
echo
return 0
}	#end display_clustering_menu_options()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_ll_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnTurquoise}Splunk n' Box v$GIT_VER: ${Yellow}MAIN MENU -> LUNCH & LEARN MENU"; docker_status
display_stats_banner
printf "\n"
echo
printf "${BoldWhiteOnYellow}Files to install for Lunch & Learn: ${NC}\n"
printf "${Yellow}1${NC}) Install apps${NC}\n"
printf "${Yellow}2${NC}) Install tutorial datasets${NC}\n"
printf "${Yellow}3${NC}) Install apps & tutorial datasets${NC}\n"
echo
printf "${BoldWhiteOnBlue}Manage Splunk:${NC}\n"
printf "${LightBlue}E${NC}) R${LightBlue}E${NC}SET all splunk passwords [changme --> $USERPASS] ${DarkGray}[splunkd must be running]${NC}\n"
printf "${LightBlue}N${NC}) LICE${LightBlue}N${NC}SES reset ${DarkGray}[copy license file to all instances]${NC}\n"
printf "${LightBlue}U${NC}) SPL${LightBlue}U${NC}NK instance(s) restart\n"
echo
printf "${Green}B${NC}) ${Green}B${NC}ACK to MAIN menu\n"
printf "${Green}?${NC}) ${Green}H${NC}ELP!\n"
echo
return 0
}	#end display_ll_menu_options()
#---------------------------------------------------------------------------------------------------------------


#### MENU INPUTS ####

#---------------------------------------------------------------------------------
main_menu_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
while true;
do
	clear
        display_main_menu_options
        choice=""
	echo
	tput bold
	tput cup 16 15
	read -p "Enter your choice [1-6] " choice
#	read -p "Enter choice: " choice
 	case "$choice" in
           \? ) display_main_menu_help ;;
        	1 ) splunk_menu_inputs ;;
        	2 ) lunch_learn_menu_inputs ;;
			3 ) clustering_menu_inputs ;;
        	4 ) demos_menu_inputs ;;
        	5 ) 3rdparty_menu_inputs ;;
        	6 ) system_menu_inputs ;;
        	7 ) change_loglevel ;;

			q|Q ) clear;
				  display_goodbye_msg;
			      echo;
	      		  echo -e "Please send feedback to mhassan@splunk.com  \0360\0237\0230\0200";echo
	      	      exit ;;
	esac  #end case ---------------------------
done
return 0
}	#end main_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
splunk_menu_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function captures user selection for splunk_menu
while true;
do
	clear
        display_splunk_menu_options
        choice=""
	echo
        read -p "Enter choice (? for help) : " choice
                case "$choice" in
                \? ) display_splunk_menu_help;;

               #IMAGES -----------
                r|R ) remove_images;;
                s|S ) show_all_images;;
                f|F ) change_default_splunk_image;;

                #CONTAINERS ------------
                c|C) create_splunk_container  ;;
                d|D ) delete_containers;;
                v|V ) delete_all_volumes;;
                l|L ) list_all_containers ;;
                t|T ) start_containers;;
                p|P ) stop_containers;;
                h|H ) list_all_hosts_by_role ;;

				b|B) return 0;;

        esac  #end case ---------------------------
	read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
done
return 0
}	#end splunk_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
system_menu_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function captures user selection for splunk_menu
while true;
do
	clear
        display_system_menu_options
        choice=""
	echo
        read -p "Enter choice (? for help) : " choice
                case "$choice" in
		#SYSTEM
        \? ) display_system_menu_help;;
		r|R ) remove_ip_aliases ;;
		w|W ) wipe_entire_system ;;
		m|M ) display_docker_stats ;;
		s|S ) show_docker_system_df ;;
		c|C ) show_docker_system_prune ;;

        b|B ) return 0;;

        esac  #end case ---------------------------
	read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
done
return 0
}	#end system_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
demos_menu_inputs () {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function captures user selection for demos_menu
while true;
do
	clear
        display_demos_menu_options
        choice=""
	echo
        read -p "Enter choice (? for help) : " choice
                case "$choice" in
                \? ) display_demos_menu_help;;
                c|C ) create_demo_container_from_list;;
                l|L ) list_all_containers "DEMO|WORKSHOP";;
                d|D ) delete_containers   "DEMO|WORKSHOP";;
                t|T ) start_containers    "DEMO|WORKSHOP";;
                p|P ) stop_containers     "DEMO|WORKSHOP";;
				a|A ) add_os_utils_to_demos ;;

                x|X) download_demo_image;;
                s|S) show_all_images "DEMO|WORKSHOP";;
				r|R ) remove_images "DEMO" ;;

                b|B ) return 0;;

        esac  #end case ---------------------------
	read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
done
return 0
}	#end demos_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
3rdparty_menu_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function captures user selection for 3rdparty_menu
while true;
do
        clear
        display_3rdparty_menu_options
        choice=""
        echo
        read -p "Enter choice (? for help) : " choice
                case "$choice" in
                \? ) display_3rdparty_menu_help;;
                c|C ) create_3rdp_container_from_list;;
                l|L ) list_all_containers "3RDP";;
                d|D ) delete_containers   "3RDP";;
                t|T ) start_containers    "3RDP";;
                p|P ) stop_containers     "3RDP";;
                o|O ) add_os_utils_to_3rdparty ;;

                x|X) download_3rdparty_image;;
                s|S) show_all_images "3RDP";;
                r|R ) remove_images  "3RDP";;

                b|B ) return 0;;

        esac  #end case ---------------------------
        read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
done
return 0
}	#end 3rdparty_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
_pass_to_tmux() {
    _FUNC_TO_PASS="${1}"
    _IFS_BACKUP="${IFS}"
    IFS=$'\n'
    for i in $(type ${_FUNC_TO_PASS} | tail -n +2); do
        tmux send-keys "${i}" C-m
    done
    IFS="${_IFS_BACKUP}"
}
#---------------------------------------------------------------------------------------------------------------
clustering_menu_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function captures user selection for clustering_menu
while true;
do
        dockerinfo=`docker info|head -5| tr '\n' ' '|sed 's/: /:/g'`
        display_clustering_menu_options
        choice=""
        read -p "Enter choice: " choice
        case "$choice" in
                \? ) display_clustering_menu_help;;
				1 ) if [ "$graphics" == "true" ];then
						tmux new-session -d  './splunknbox.sh -g true -s true -c 1'
						tmux split-window -h
        				tmux send-keys "./scripts/viz.sh" C-m
						#tmux attach-session
						tmux -CC attach
					fi;
				#	create_single_idxc "AUTO";
					;;
				2 ) if [ "$graphics" == "true" ];then
				#		_pass_to_tmux "create_single_idxc AUTO"
						tmux new-session -d './splunknbox.sh -g true -s true -c 2'
						tmux split-window -h './scripts/viz.sh'
						tmux attach-session
					fi;
				#	create_single_shc "AUTO";
					;;
                3 ) build_single_site "AUTO" ;;
                4 ) build_multi_site "AUTO" ;;
                5 ) printf "${White} **Please remember to follow host naming convention**${NC}\n";
		    		create_single_idxc;;
				6 ) printf "${White} **Please remember to follow host naming convention**${NC}\n";
		    		create_single_shc;;
                7 ) printf "${White} **Please remember to follow host naming convention**${NC}\n";
		    		build_single_site;;
                8 ) printf "${White} **Please remember to follow host naming convention**${NC}\n";
		    		build_multi_site;;

	        	b|B) return 0;;
        esac  #end case ---------------------------
        read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
done
return 0
}	#end clustering_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
lunch_learn_menu_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function captures user selection for splunk_menu
while true;
do
	clear
        display_ll_menu_options
        choice=""
	echo
        read -p "Enter choice (? for help) : " choice
                case "$choice" in
                \? ) display_splunk_menu_help;;

                1 ) install_ll_menu_inputs "apps";;
                2 ) install_ll_menu_inputs "datasets";;
            	3 ) install_ll_menu_inputs;;

                #SPLUNK ------
                e|E ) reset_all_splunk_passwords ;;
                n|N ) add_splunk_licenses ;;
                u|U ) restart_all_splunkd ;;

				b|B) return 0;;

        esac  #end case ---------------------------
	read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
done
return 0
}	#end lunch_learn_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
install_ll_menu_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
installtype=$1
type=""
clear
printf "${BoldWhiteOnYellow}CONFIGURE LUNCH & LEARN CONTAINERS APPS/DATASETS MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers
echo
count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
        printf "No $type containers found!\n"
        return 0;
fi
declare -a list=($(docker ps -a --filter name="$type" --format "{{.Names}}" | sort | tr '\n' ' '))
choice=""
read -p $'Choose number to configure. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
	#convert array indexes to a string
	host_names=""
	for i in `echo $choice`; do
		   host_names="$host_names ""${list[$i-1]}"
	done
else
	host_names=${list[@]}
fi
printf "${Yellow}Configuring selected containers for Lunch & Learn...\n${NC}"
if [ "$installtype" == "apps" ]; then
	install_ll_apps "$host_names"

elif [ "$installtype" == "datasets" ]; then
	install_ll_datasets "$host_names"
else
	install_ll_datasets "$host_names"
	install_ll_apps "$host_names"  #keep this in the second place. Hosts need rebooting
fi
echo
return 0
}       #end install_ll_menu_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
install_ll_apps() {
host_names=$1	#list of hostnames to configure
echo
printf "${Yellow}Downloading apps...${NC}\n"
for file in $LL_APPS; do
	if [ -f $SPLUNK_APPS_DIR/$file ];then
		printf "Downloading file [$file]: [${White}*cached*${NC}]\n"
	else
		printf "Downloading file [$file]: "
		progress_bar_pkg_download "wget -q -np -O $SPLUNK_APPS_DIR/$file \
			https://raw.githubusercontent.com/mhassan2/splunk-n-box/master/splunk_apps/$file"
	fi
done
echo
for hostname in `echo $host_names` ; do
	printf "[${Purple}$hostname${NC}]${LightBlue} Configuring host apps ... ${NC}\n"
	#install all apps on hostname ---------
	for app in $LL_APPS; do
		printf "	${Yellow}${ARROW_EMOJI}${NC}Installing $app app "
		CMD="docker cp $SPLUNK_APPS_DIR/$app $hostname:/tmp"; OUT=`$CMD`
		CMD="docker exec -u splunk -ti $hostname /opt/splunk/bin/splunk install app /tmp/$app -auth $USERADMIN:$USERPASS"
		printf "\n${DarkGray}CMD:[$CMD]${NC}\n" >&4
		OUT=`$CMD`;# installed=$(display_output "$OUT" "installed" "2")
		reboot="N"
		if ( compare "$OUT" "already" ); then
			printf "${Red}${CHECK_MARK_EMOJI} Installed\n${NC}"
			reboot="N"
		else
			printf "${Green}Done!\n${NC}"
			reboot="Y"
		fi
		logline "$CMD" "$hostname"
	done #-----------------------------------
	if [ "$reboot" == "Y" ]; then
		restart_splunkd "$hostname" "b"
	fi
done
}	#end install_ll_apps()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
install_ll_datasets() {
host_names=$1	#list of hostnames to configure
echo
printf "${Yellow}Downloading datasets...${NC}\n"
for file in $LL_DATASETS; do
	if [ -f $SPLUNK_DATASETS_DIR/$file ];then
		printf "Downloading file [$file]: [${White}*cached*${NC}]\n"
	else
		printf "Downloading file [$file]: "
		progress_bar_pkg_download "wget -q -np -O $SPLUNK_DATASETS_DIR/$file \
			https://raw.githubusercontent.com/mhassan2/splunk-n-box/master/tutorial_datasets/$file"
	fi
done
echo

for hostname in `echo $host_names` ; do
	printf "[${Purple}$hostname${NC}]${LightBlue} Configuring host datasets... ${NC}\n"
	#install all datasets on hostname -------
	printf "	${Yellow}${ARROW_EMOJI}${NC}Indexing tutorial data [tutorialdata.zip] "
	CMD="docker cp $SPLUNK_DATASETS_DIR/tutorialdata.zip $hostname:/tmp"; OUT=`$CMD`
	CMD="docker exec -u splunk -ti $hostname /opt/splunk/bin/splunk add oneshot /tmp/tutorialdata.zip -auth $USERADMIN:$USERPASS"
	printf "\n${DarkGray}CMD:[$CMD]${NC}\n" >&4
	OUT=`$CMD`; display_output "$OUT" "added" "3"
	logline "$CMD" "$hostname"

	printf "	${Yellow}${ARROW_EMOJI}${NC}Configuring lookup table [http_status.csv] "
	CMD="docker cp $SPLUNK_DATASETS_DIR/http_status.csv $hostname:/opt/splunk/etc/apps/search/lookups"; OUT=`$CMD`
	printf "[http_status]\nfilename = http_status.csv\n" > transforms.conf.tmp
	CMD="docker cp transforms.conf.tmp $hostname:/tmp/transforms.conf"; OUT=`$CMD`
  	CMD=`docker exec -u splunk -ti $hostname bash -c "cat /tmp/transforms.conf >> /opt/splunk/etc/apps/search/local/transforms.conf" `
	OUT="$CMD"; display_output "$OUT" "" "2"
	printf "\n${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$hostname"
	rm -fr transforms.conf.tmp
	#-------------------------------------------
done
}	#end install_ll_datasets()
#---------------------------------------------------------------------------------------------------------------



#### CLUSTERS ######

#---------------------------------------------------------------------------------------------------------------
create_single_shc() {
#This function creates single Search Head Cluster. Details is passed using $1
#inputs: $1: pass all components (any order) needed and how many to create. The names the counts will be extracted
#example : create_single_shc "$siteSH:$SHcount $cm:1 $lm:1"
#outputs: -adjust hostname with sitename if used
#	  -always convert hostnames to upper case (to avoid lookup/compare issues)
#	  -create single deployer and as many SH hosts required
#	  -if param $1 is "AUTO" skip all user prompts and create standard cluster 3SH/1DEP
#-----------------------------------------------------------------------------------------------------
#$1 AUTO or MANUAL mode
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
if [ "$1" == "AUTO" ]; then  mode="AUTO"; else mode="MANUAL"; fi

server_list=""    #used by STEP#3
START=$(date +%s);

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
	#printf "\n${Yellow}[$mode]>>BUILDING SEARCH HEAD CLUSTER!${NC}\n\n"
	printf  "\n"
	printf "${LightPurple}>>BUILDING SEARCH HEAD CLUSTER (SHC):${NC}\n"
	printf "${LightPurple}==>Starting PHASE1: Creating generic SH hosts${NC}\n"
	printf "${DarkGray}Using DMC:[$DMC_BASE] LM:[$LM_BASE] CM:[$CM_BASE] LABEL:[$label] DEP:[$DEP_BASE:$DEP_SHC_COUNT] SHC:[$SH_BASE:$STD_SHC_COUNT]${NC}\n\n" >&4
	printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"

	#Basic services. Sequence is very important!
    create_splunk_container "$DMC_BASE" "1" ; dmc=$gLIST
    create_splunk_container "$LM_BASE" "1" ; lm=$gLIST
    make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
    create_splunk_container "$DEP_BASE" "$DEP_SHC_COUNT" ; dep="$gLIST"
    make_lic_slave $lm $dep ; make_dmc_search_peer $dmc $dep

	#The rest of SHs
    create_splunk_container "$SH_BASE" "$STD_SHC_COUNT" ; members_list="$gLIST"
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
	#printf "\n"
	#printf "${Yellow}The following single SH Cluster will be created [$mode]:${NC}\n"
	#printf "Cluster Label: ${Green}%s${NC}\n" $label
	#printf "Deployer Base Hostname: ${Green}%s${NC}\n" $DEPname
	#printf "DMC Base Hostname: ${Green}%s${NC}\n" $dmc
	#printf "License Master Base Hostname: ${Green}%s${NC}\n" $lm
	#printf "SH Base Hostname: ${Green}%s${NC}\n" $SHname
	#printf "Number of Search Heads: ${Green}%s${NC}\n" $SHcount
	#if [ "$mode" == "MANUAL" ]; then
	#	read -p $'Hit <\033[1;32mENTER>\e[0m:Confirm \033[1;32m <B>\e[0m:Go Back ? ' choice
	#	if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi
	#fi
	#printf "\n"


	#printf "\n${Yellow}[$mode]>>BUILDING SEARCH HEAD CLUSTER!${NC}\n\n"
	printf "${LightPurple}>>BUILDING SEARCH HEAD CLUSTER (SHC):${NC}\n\n"
	printf "${LightPurple}==>Starting PHASE1: Creating generic SH hosts${NC}\n"
	printf "${DarkGray}Using DMC[$dmc] LM:[$lm] CM:[$cm] LABEL:[$label] DEP:[$DEPname:$DEP_SHC_COUNT] SHC:[$SHname:$SHcount]${NC}\n\n" >&4
    printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"
	if [ "$build_dmc" == "1" ]; then
            create_splunk_container "$dmc" "1"; dmc=$gLIST
    fi
	if [ "$build_lm" == "1" ]; then
        	create_splunk_container "$lm" "1" ; lm="$gLIST"
			make_lic_slave $lm $dmc  #for previous step since lm was not ready yet
            make_dmc_search_peer $dmc $lm
	fi

        create_splunk_container "$DEPname" "$DEP_SHC_COUNT" ; dep="$gLIST"
		make_lic_slave $lm $dep
        make_dmc_search_peer $dmc $dep
        create_splunk_container "$SHname" "$SHcount" ; members_list="$gLIST"
fi
printf "${LightBlue}___________ Finished creating hosts __________________________${NC}\n"

printf "${LightPurple}==>Starting PHASE2: Converting generic SH hosts into SHC${NC}\n"

printf "${LightBlue}___________ Starting STEP#1 (deployer configuration) ____________________________${NC}\n" >&3

## from this point on all hosts should be created and ready. Next steps are SHCluster configurations ##########
#DEPLOYER CONFIGURATION: (create [shclustering] stanza; set SecretKey and restart) -----
printf "${DarkGray}Configuring SHC with created hosts: DEPLOYER[$dep]  MEMBERS[$members_list] ${NC}\n" >&3

#---------
printf "[${Purple}$dep${NC}]${LightBlue} Configuring Deployer ... ${NC}\n"
bind_ip_dep=`docker inspect --format '{{ .HostConfig }}' $dep| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
txt="\n #-----Modified by Docker Management script ----\n [shclustering]\n pass4SymmKey = $MYSECRET \n shcluster_label = $label\n"
#printf "%b" "$txt" >> $MOUNTPOINT/$dep/etc/system/local/server.conf	#cheesy fix!
printf "%b" "$txt" > $TMP_DIR/server.conf.tmp
CMD="docker cp $TMP_DIR/server.conf.tmp $dep:/tmp/server.conf"; OUT=`$CMD`
CMD=`docker exec -u splunk -ti $dep  bash -c "cat /tmp/server.conf >> /opt/splunk/etc/system/local/server.conf" `; #OUT=`$CMD`

printf "	${Yellow}${ARROW_EMOJI}${NC}Adding stanza [shclustering] to server.conf!" >&3 ; display_output "$OUT" "" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$dep"

restart_splunkd "$dep"

printf "${LightBlue}___________ Finished STEP#1 __________________________${NC}\n" >&3

printf "${LightBlue}___________ Starting STEP#2 (members configs) ________${NC}\n" >&3
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}After members_list loop> param2:[$2] members_list:[$members_list] sh_list:[$sh_list]${NC}\n" >&5
for i in $members_list ; do
	check_load	#throttle during SHC build

	#-------member config---
 	printf "[${Purple}$i${NC}]${LightBlue} Making cluster member...${NC}\n"
    bind_ip_sh=`docker inspect --format '{{ .HostConfig }}' $i| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	CMD="docker exec -u splunk -ti $i /opt/splunk/bin/splunk init shcluster-config -auth $USERADMIN:$USERPASS -mgmt_uri https://$bind_ip_sh:$MGMT_PORT -replication_port $REPL_PORT -replication_factor $RFACTOR -register_replication_address $bind_ip_sh -conf_deploy_fetch_url https://$bind_ip_dep:$MGMT_PORT -secret $MYSECRET -shcluster_label $label"
	OUT=`$CMD`
	OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
	printf "	${Yellow}${ARROW_EMOJI}${NC}Initiating shcluster-config " >&3 ; display_output "$OUT" "clustering has been initialized" "3"
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$i"
	#-------

	#-------auto discovery---
	# if cm exist (passed to us); configure search peers for idx auto discovery
	if [ -n "$cm" ]; then
		#another method of getting bind IP (showing published ports:IPs).Container must be RUNNING!
		cm_ip=`docker port  $cm| awk '{print $3}'| cut -d":" -f1|head -1`
    	CMD="docker exec -u splunk  -ti $i /opt/splunk/bin/splunk edit cluster-config -mode searchhead -master_uri https://$cm_ip:$MGMT_PORT -secret $MYSECRET -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
		printf "	${Yellow}${ARROW_EMOJI}${NC}Integrating with Cluster Master (for idx auto discovery) [$cm] " >&3 ; display_output "$OUT" "property has been edited" "3"
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

CMD="docker exec -u splunk -ti $i /opt/splunk/bin/splunk bootstrap shcluster-captain -servers_list "$server_list" -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "	${Yellow}${ARROW_EMOJI}${NC}Captain bootstrapping (may take time) " >&3 ; display_output "$OUT" "Successfully"  "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$i"
printf "${LightBlue}___________ Finished STEP#3 __________________________${NC}\n" >&3

printf "${LightBlue}___________ Starting STEP#4 (cluster status)__________${NC}\n" >&3
printf "[${Purple}$i${NC}]${LightBlue}==> Checking SHC status (on captain)...${NC}"

CMD="docker exec -u splunk -ti $i /opt/splunk/bin/splunk show shcluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
display_output "$OUT" "Captain" "2"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$i"
printf "${LightBlue}___________ Finished STEP#4 (cluster status)__________${NC}\n\n" >&3

END=$(date +%s);
TIME=`echo $((END-START)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Execution time for ${FUNCNAME}(): [$TIME]${NC}\n"
#count=`wc -w $CMDLOGBIN| awk '{print $1}' `
#printf "${DarkGray}Number of Splunk config commands issued: [%s]${NC}\n" "$count"

#print_stats $START ${FUNCNAME}

return 0
}	#create_single_shc()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_single_idxc() {
#This function creates single IDX cluster. Details are parsed from $1
#example call: create_single_idxc "$siteIDX:$IDXcount $cm:1 $lm $label"
#$1 AUTO or MANUAL mode

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
if [ "$1" == "AUTO" ]; then  mode="AUTO"; else mode="MANUAL"; fi

START=$(date +%s);
#$1 CMbasename:count   $2 IDXbasename:count  $3 LMbasename:count

check_load
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

#------- big if ------------------
if [ "$mode" == "AUTO" ]; then
	#CMname="CM"; DMCname="DMC"; LMname="LM";  IDXname="IDX"; IDXcount="$STD_IDXC_COUNT";
	label="$IDXCLUSTERLABEL"
	#printf "${Yellow}[$mode]>>BUILDING INDEX CLUSTER${NC}\n"
	printf "${LightPurple}>>BUILDING INDEX CLUSTER (IDX):${NC}\n"
	printf "${LightPurple}==>Starting PHASE1: Creating generic IDX hosts${NC}\n"
	printf "${DarkGray}Using base-names DMC:[$DMC_BASE] LM:[$LM_BASE] CM:[$CM_BASE] LABEL:[$IDXCLUSTERLABEL] IDXC:[$IDX_BASE:$STD_IDXC_COUNT]${NC}\n\n" >&4
    printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"

	#Basic services. Sequence is very important!
	create_splunk_container "$DMC_BASE" "1" ; dmc=$gLIST
	create_splunk_container "$LM_BASE" "1" ; lm=$gLIST
	make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
	create_splunk_container "$CM_BASE" "1" ; cm=$gLIST
	make_lic_slave $lm $cm ; make_dmc_search_peer $dmc $cm

	#The rest of IDXs
    create_splunk_container "$IDX_BASE" "$STD_IDXC_COUNT" ; members_list="$gLIST"
else
	#Anything passed to function; user will NOT be prompted for it!
	if [ -z "$label" ]; then
        read -p "Need to know IDX cluster label (default $SHCLUSTERLABEL)? " label ;
        label=`echo $label| tr '[a-z]' '[A-Z]'`; if [ -z "$label" ]; then label="$SHCLUSTERLABEL"; fi
    fi
	if [ -z "$IDXname" ] || [ -z "$IDXcount" ]; then
        read -p "Need to know IDX basename (default $IDX_BASE)? " IDXname ;
        IDXname=`echo $IDXname| tr '[a-z]' '[A-Z]'` ; if [ -z "$IDXname" ]; then IDXname="$IDX_BASE"; fi
		read -p "Need to know how IDX to create (default 3)? " IDXcount;
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
            read -p "Need to know DMC basename (default $DMC_BASE)? " dmc ;
            dmc=`echo $dmc| tr '[a-z]' '[A-Z]'`
            if [ -z "$dmc" ]; then
                    dmc="$DMC_BASE"; build_dmc=1;
            else
                    build_dmc=0;
            fi
    fi

	printf "\n"
	#printf "${Yellow}The following single IDX Cluster will be created[$mode]:${NC}\n"
	#printf "Cluster Label: ${Green}%s${NC}\n" $label
	#printf "Cluster Master Base Hostname: ${Green}%s${NC}\n" $cm
	#printf "DMC Base Hostname: ${Green}%s${NC}\n" $dmc
	#printf "License Master Base Hostname: ${Green}%s${NC}\n" $lm
	#printf "IDX Base Hostname: ${Green}%s${NC}\n" $IDXname
	#printf "Number of Indexers: ${Green}%s${NC}\n" $IDXcount
	#if [ "$mode" == "MANUAL" ]; then
	#	read -p $'Hit <\033[1;32mENTER>\e[0m:Confirm \033[1;32m <B>\e[0m:Go Back ? ' choice
	#	if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi
	#fi

	printf "\n"

	#printf "\n${Yellow}[$mode]>>BUILDING INDEX CLUSTER${NC}\n"
	printf "${LightPurple}>>BUILDING INDEX CLUSTER (IDX):${NC}\n"
	printf "${LightPurple}==>Starting PHASE1: Creating generic IDX hosts${NC}\n"
	printf "${DarkGray}Using DMC:[$dmc] LM:[$lm] CM:[$cm] LABEL:[$label] IDXC:[$IDXname:$IDXcount]${NC}\n\n" >&4
	printf "${LightBlue}___________ Creating hosts __________________________${NC}\n"
	if [ "$build_dmc" == "1" ]; then
                create_splunk_container "$dmc" "1"; dmc=$gLIST
    fi
    if [ "$build_lm" == "1" ]; then
        create_splunk_container "$lm" "1" ; lm=$gLIST
		make_lic_slave $lm $dmc  #for previous step since lm was not ready yet
		make_dmc_search_peer $dmc $lm
    fi
    if [ "$build_cm" == "1" ]; then
        create_splunk_container "$cm" "1"; cm=$gLIST
		make_lic_slave $lm $cm
		make_dmc_search_peer $dmc $cm
    fi

	#create the remaining IDXs
    create_splunk_container "$IDXname" "$IDXcount" ; members_list="$gLIST"

fi
#------- big if ------------------

printf "${LightBlue}___________ Finished creating hosts __________________________${NC}\n"
printf "\n"
printf "${LightPurple}==>Starting PHASE2: Converting generic IDX hosts into IDXC${NC}\n"

printf "${LightBlue}____________ Starting STEP#1 (Configuring IDX Cluster Master) __${NC}\n" >&3
printf "[${Purple}$cm${NC}]${LightBlue} Configuring Cluster Master... ${NC}\n"

#-------CM config---
bind_ip_cm=`docker inspect --format '{{ .HostConfig }}' $cm| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
CMD="docker exec -u splunk -ti $cm /opt/splunk/bin/splunk edit cluster-config  -mode master -replication_factor $RFACTOR -search_factor $SFACTOR -secret $MYSECRET -cluster_label $label -auth $USERADMIN:$USERPASS "
OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "	${Yellow}${ARROW_EMOJI}${NC}Configuring CM [RF:$RFACTOR SF:$SFACTOR] and cluster label[$label] " >&3 ; display_output "$OUT" "property has been edited" "3"
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
    CMD="docker exec -u splunk -ti $i /opt/splunk/bin/splunk edit cluster-config -mode slave -master_uri https://$bind_ip_cm:$MGMT_PORT -replication_port $REPL_PORT -register_replication_address $bind_ip_idx -cluster_label $label -secret $MYSECRET -auth $USERADMIN:$USERPASS "
	OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
	printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$i"
	printf "	${Yellow}${ARROW_EMOJI}${NC}Make a cluster member " >&3 ; display_output "$OUT" "property has been edited" "3"
	#-------
	#-------tcp/9997--- disabled 2/15/17 Already in 6.5 image build
        #CMD="docker exec -u splunk  -ti $i /opt/splunk/bin/splunk enable listen $RECV_PORT -auth $USERADMIN:$USERPASS "
        #OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
        #printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
        #logline "$CMD" "$i"
        #printf "	${Yellow}${ARROW_EMOJI}${NC}Enabling receiving port [$RECV_PORT] " >&3 ; display_output "$OUT" "Listening for" "3"
        #-------

	#We dont need to add IDXCs to DMC, just add their CM (which is already done)

	make_lic_slave $lm $i
	restart_splunkd "$i" "b"

	#assign_server_role "$i" "dmc_group_indexer"
done
printf "${LightBlue}____________ Finished STEP#2 __________________________${NC}\n" >&3

printf "${LightBlue}____________ Starting STEP#3 (IDXC status) ____________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${LightBlue}==> Checking IDXC status...${NC}"
CMD="docker exec -u splunk -ti $cm /opt/splunk/bin/splunk show cluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`; display_output "$OUT" "Replication factor" "2"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "${LightBlue}____________ Finished STEP#3 __________________________${NC}\n\n" >&3

END=$(date +%s);
TIME=`echo $((END-START)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray}Execution time for ${FUNCNAME}(): [$TIME]${NC}\n"
#count=`wc -w $CMDLOGBIN| awk '{print $1}' `
#printf "${DarkGray}Number of Splunk config commands issued: [%s]${NC}\n" "$count"

#print_stats $START ${FUNCNAME}

return 0
}	#end create_single_idxc()
#---------------------------------------------------------------------------------------------------------------

##### BUILD SITES ########

#---------------------------------------------------------------------------------------------------------------
build_single_site() {
#This function will build 1 CM and 1 LM then calls create_splunk_container()
# Expected parameters: "$cm $lm $siteIDX:$IDXcount $siteSH:$SHcount $siteDEP:1"
#$1 AUTO or MANUAL mode

_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

check_load
START_TIME=$(date +%s);
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
printf "\n"
#printf "${Yellow}The following single site will be created [$mode]:${NC}\n"
#printf "Site Name: ${Green}%s${NC}\n" $site
#printf "SH Cluster Label: ${Green}%s${NC}\n" $shc_label
#printf "IDX Cluster Label: ${Green}%s${NC}\n" $idxc_label
#printf "Cluster Master Base Hostname: ${Green}%s-CM${NC}\n" $site
#printf "DMC Base Hostname: ${Green}%s-DMC${NC}\n" $site
#printf "License Master Base Hostname: ${Green}%s-LM${NC}\n" $site
#printf "IDX Base Hostname: ${Green}%s-IDX${NC}\n" $site
#printf "Number of Indexers: ${Green}%s${NC}\n" $IDXcount
#printf "SH Base Hostname: ${Green}%s-SH${NC}\n" $site
#printf "Number of Search Heads: ${Green}%s${NC}\n" $SHcount
#if [ "$mode" == "MANUAL" ]; then
#	read -p $'Hit <\033[1;32mENTER>\e[0m:Confirm \033[1;32m <B>\e[0m:Go Back  > ' choice
#	if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi
#fi
printf "\n"


#printf "${Yellow}==>[$mode] Building single-site ($site)...${NC}\n\n"
printf "${LightPurple}==>Building single-site ($site)...${NC}\n\n"
printf "${LightBlue}____________ Building basic services [LM, DMC, CM] ___________________${NC}\n" >&3
#Basic services
#Sequence is very important!
create_splunk_container "$site$DMC_BASE" "1" ; dmc=$gLIST
create_splunk_container "$site$LM_BASE" "1" ; lm=$gLIST
make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
create_splunk_container "$site$CM_BASE" "1" ; cm=$gLIST
make_lic_slave $lm $cm ; make_dmc_search_peer $dmc $cm

#testing HF ****************************************
create_splunk_container "$site$HF_BASE" "1" ; hf=$gLIST
make_lic_slave $lm $hf ; #make_dmc_search_peer $dmc $hf

printf "${LightBlue}____________ Finished building basic services ___________________${NC}\n\n" >&3

create_single_idxc "$site$IDX_BASE:$IDXcount $dmc $cm:1 $lm LABEL:$idxc_label"
create_single_shc "$site$SH_BASE:$SHcount $site$DEP_BASE:1 $dmc $cm $lm LABEL:$shc_label"

#print_stats $START_TIME ${FUNCNAME}


return 0
}	#build_single_site()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
build_multi_site() {
#This function creates site-2-site cluster
#http://docs.splunk.com/Documentation/Splunk/6.4.3/Indexer/Migratetomultisite
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

mode=$1		#either "AUTO" or "MANUAL"
START_TIME=$(date +%s);

check_load
s=""; sites_str=""     			#used with "splunk edit cluster-config" on CM
SITEnames=""
clear
printf "Note:"
printf " -One DEP server per SHC will be automatically created.\n"
printf " -One CM server will be automatically created for the entire site-2-site cluster.\n"

if [ "$mode" == "AUTO" ]; then
	count=3;
    IDXcount="$STD_IDXC_COUNT"; SHcount="$STD_SHC_COUNT"; shc_label="$SHCLUSTERLABEL"; idxc_label="$IDXCLUSTERLABEL"
	#SITEnames="$DEFAULT_SITES_NAMES"
    SITEnames="STL LON HKG"
    sites_str="site1,site2,site3"
	first_site=`echo $SITEnames|awk '{print $1}'`		#where basic services CM,LM resides
	cm=$first_site"CM01"
else
	read -p "How many LOCATIONS to build (default 3)?  " count
    if [ -z "$count" ]; then count=3; fi

	#loop thru site count to capture site details
	for (( i=1; i <= ${count}; i++)); do
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
	read -p "site-to-site cluster must have one CM. Enter CM fullname (default $first_site"CM01")> " cm
    cm=`echo $cm| tr '[a-z]' '[A-Z]' `
    if [ -z "$cm" ]; then cm=$first_site"CM01"; fi
fi

#------- Finished capturing sites names/basic services names ------------------

printf "\n\n${BoldYellowOnBlue}[$mode] Building site-to-site cluster...${NC}\n"
printf "${DarkGray}Using Locations:[$SITEnames] CM:[$cm] First_site:[$first_site] ${NC}\n\n" >&4

printf "\n\n${Yellow}Creating cluster basic services [only in $first_site]${NC}\n"
#Sequence is very important!
create_splunk_container "$first_site$DMC_BASE" "1" ; dmc=$gLIST
create_splunk_container "$first_site$LM_BASE" "1" ; lm=$gLIST
make_lic_slave $lm $dmc ; make_dmc_search_peer $dmc $lm
create_splunk_container "$first_site$CM_BASE" "1" ; cm=$gLIST
make_lic_slave $lm $cm ; make_dmc_search_peer $dmc $cm

#Loop thru list of sites & build generic SH/IDX hosts on each site
counter=0
for site in $SITEnames; do
	let counter++
	#printf "counter=[$counter] [$SITEnames]\n"
	printf "\n${BoldYellowOnBlue}Building site$counter >> $site ${NC}\n"
	create_single_idxc "$site$IDX_BASE:$IDXcount $cm $lm LABEL:$IDXCLUSTERLABEL"
	create_single_shc "$site$SH_BASE:$SHcount $site$DEP_BASE:1 $cm $lm LABEL:$SHCLUSTERLABEL"
done

idx_list=`docker ps -a --filter name="IDX|idx" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
sh_list=`docker ps -a --filter name="SH|sh" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort | tr -d '\r' | tr  '\n' ' ' `
site_list=`echo $cm_list | sed 's/\-[a-zA-Z0-9]*//g' `

printf "${BoldYellowOnBlue}Migrating existing IDXCs & SHCs to site-2-site cluster: ${NC}\n"
printf "${DarkGray}Using LM:[$lm] CM:[$cm] sites:[$SITEnames]\n\n${NC}"

#echo "list of sites[$SITEnames]   cm[$cm]"

printf "${Cyan}____________ Starting STEP#1 (Configuring one CM for all locations) _____________________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${Cyan} Configuring Cluster Master... ${NC}\n"
cm_ip=`docker port $cm| awk '{print $3}'| cut -d":" -f1|head -1 `
CMD="docker exec -u splunk -ti $cm /opt/splunk/bin/splunk edit cluster-config -mode master -multisite true -available_sites $sites_str -site site1 -site_replication_factor origin:2,total:3 -site_search_factor origin:1,total:2 -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "	${Yellow}${ARROW_EMOJI}${NC}Setting multi-site to true... " >&3 ; display_output "$OUT" "property has been edited" "3"

restart_splunkd "$cm"
is_splunkd_running "$cm"

CMD="docker exec -u splunk -ti $cm /opt/splunk/bin/splunk enable maintenance-mode --answer-yes -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "	${Yellow}${ARROW_EMOJI}${NC}Enabling maintenance-mode... " >&3 ; display_output "$OUT" "aintenance mode set" "3"

printf "${Cyan}____________ Finished STEP#1 __________________________________________________${NC}\n" >&3

printf "${Cyan}____________ Starting STEP#2 (Configuring search peers in [site:"$site""$seq" location:$str]) _____________________${NC}\n" >&3

seq=1
for str in $SITEnames; do
	site="site""$seq"
	site_idx_list=`echo $idx_list | $GREP -Po '('$str'-\w+\d+)' | tr -d '\r' | tr  '\n' ' '  `
	site_sh_list=`echo $sh_list | $GREP -Po '('$str'-\w+\d+)' | tr -d '\r' | tr  '\n' ' '  `
	for i in $site_idx_list; do
		printf "[${Purple}$i${NC}]${Cyan} Migrating Indexer (restarting takes time)... ${NC}\n"
		CMD="docker exec -u splunk -ti $i /opt/splunk/bin/splunk edit cluster-config  -mode slave -site $site -master_uri https://$cm_ip:$MGMT_PORT -replication_port $REPL_PORT  -auth $USERADMIN:$USERPASS "
		OUT=`$CMD`
        OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up

		printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$i"
		printf "	${Yellow}${ARROW_EMOJI}${NC}Configuring multi-site clustering for [site:$site location:$str] " >&3
		display_output "$OUT" "property has been edited" "3"
		restart_splunkd "$i" "b"
	done
	printf "${Cyan}____________ Finished STEP#2 __________________________________________________${NC}\n" >&3

	printf "${Cyan}____________ Starting STEP#3 (Configuring SHs in [site:$site location:$str]) ___${NC}\n" >&3
	for i in $site_sh_list; do
		printf "[${Purple}$i${NC}]${Cyan} Migrating Search Head... ${NC}\n"
	    CMD="docker exec -u splunk -ti $i /opt/splunk/bin/splunk edit cluster-master https://$cm_ip:$MGMT_PORT -site $site -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
        OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
		printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$i"
		printf "	${Yellow}${ARROW_EMOJI}${NC}Pointing to CM[$cm] for [site:$site location:$str]" >&3
		display_output "$OUT" "property has been edited" "3"
		restart_splunkd "$i" "b"
	done
	printf "${Cyan}____________ Finished STEP#3 __________________________________________________${NC}\n" >&3

seq=`expr $seq + 1`
done  #looping thru the sites list

printf "${Cyan}____________ Starting STEP#4 (CM maintenance-mode) _____________________${NC}\n" >&3
printf "[${Purple}$cm${NC}]${Cyan} Disabling maintenance-mode... ${NC}\n"
CMD="docker exec -u splunk -ti $cm /opt/splunk/bin/splunk disable maintenance-mode -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "\t${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf "	${Yellow}${ARROW_EMOJI}${NC}Disabling maintenance-mode..." >&3 ; display_output "$OUT" "No longer"  "3"
#restart_splunkd "$i"
printf "${Cyan}____________ Finished STEP#4 __________________________________________________${NC}\n" >&3

#print_stats $START_TIME ${FUNCNAME}

return 0
}	#build_multi_site()
#---------------------------------------------------------------------------------------------------------------



#---------------------------------------------------------------------------------------------------------------
print_stats() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

START=$1; FUNC_NAME=$2

END=$(date +%s);
TIME=`echo $((END-START)) | awk '{print int($1/60)":"int($1%60)}'`

echo
#get unique host list  (mpty lines removed)
grep exec $CMDLOGTXT | awk '{print $5}'|grep -v -e '^[[:space:]]*$'|sort -u > tmp1

printf "${LightBlue}   HOST         NUMBER OF CMDS${NC}\n"  >&3
printf "${LightBlue}============    =============${NC}\n"   >&3
for host_name in `cat tmp1`; do
    count=`grep $host_name $CMDLOGTXT|grep exec|wc -l`;
    cmd_list=`grep exec $CMDLOGTXT| grep $host_name| awk '{print $6,$7,$8}'| sed 's/\$//g'|sed 's/\/opt\/splunk\/bin\/splunk //g'| sort | uniq -c|sed 's/\r\n/ /g'|awk '{printf "[%s:%s %s]", $1,$2,$3}' `

    printf "${LightBlue}%-15s %7s ${NC}\n" $host_name $count >&3
    printf "${DarkGray}$cmd_list${NC}\n" >&4

done > tmp2
#cat tmp2  >&3	#show results
echo

#awk '{total = total + int($2)}END {print "Total Splunk Commands Used to build the cluster = " total}' tmp2
cmd_total=`awk '{total = total + int($2)}END {print total}' tmp2`
printf "Number of Splunk Commands Used to Build The Cluster = ${LightBlue}$cmd_total${NC}\n"
printf "Total execution time for $FUNC_NAME = ${Yellow}$TIME ${NC}minutes\n\n"

#rm -fr tmp1 tmp2
return 0

} 	#print_stats()
#---------------------------------------------------------------------------------------------------------------

##### DISPLAY MENUS ####

#---------------------------------------------------------------------------------------------------------------
display_stats_banner() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#os_used_mem=`top -l 1 -s 0 | grep PhysMem |tr -d '[[:alpha:]]' |tr -d '[[:punct:]]'|awk '{print $1}' `    #extract used memory in G
#os_wired_mem=`top -l 1 -s 0 | grep PhysMem | tr -d '[[:alpha:]]' |tr -d '[[:punct:]]'|awk '{print $2}' `     #extract wired mem in M
#os_unused_mem=`top -l 1 -s 0 | grep PhysMem | tr -d '[[:alpha:]]' |tr -d '[[:punct:]]'|awk '{print $3}' `     #extract unused mem in M

dockerinfo_ver=`docker info| $GREP 'Server Version'| awk '{printf $3}'| tr -d '\n' `
dockerinfo_cpu=`docker info| $GREP 'CPU' | awk '{printf $2}'| tr -d '\n' `
dockerinfo_mem1=`docker info| $GREP  'Total Memory'| awk '{printf $3}'|sed 's/GiB//g'| tr -d '\n' `
dockerinfo_mem=`echo "$dockerinfo_mem1 / 1" | bc `
#echo "DOCKER: ver:[$dockerinfo_ver]  cpu:[$dockerinfo_cpu]  totmem:[$dockerinfo_mem] "

if [ "$os" == "Darwin" ]; then
        loadavg=`sysctl -n vm.loadavg | awk '{print $2}'`
        cores=`sysctl -n hw.ncpu`
elif [ "$os" == "Linux" ]; then
        loadavg=`cat /proc/loadavg |awk '{print $1}'|sed 's/,//g'`
        cores=`$GREP -c ^processor /proc/cpuinfo`
fi

#load=${loadavg%.*}
load=`echo "$loadavg/1" | bc `   #convert float to int
#load=4
#MAXLOADAVG=`echo $cores \* $LOADFACTOR | bc -l `
#echo $load : $MAXLOADAVG : $cores; exit

#c=`echo " $load > $MAXLOADAVG" | bc `;
#if [  "$c" == "1" ]; then
if [[ "$load" -ge "$cores" ]]; then
	loadavg="${Red}$loadavg${NC}"
elif [[ "$load" -ge "$cores/2" ]]; then
	loadavg="${BrownOrange}$loadavg${NC}"
else
	loadavg="${NC}$loadavg${NC}"
fi

if [ "$1" ]; then
	printf "=>${White}OS:${NC}[FreeMem:${os_free_mem}GB Load:$loadavg]${NC}\n"
else
	printf "${White}${DOLPHIN1_EMOJI}${NC} [ver:$dockerinfo_ver cpu:$dockerinfo_cpu mem:${dockerinfo_mem}GB] ${White}${BATTERY_EMOJI}${NC} [FreeMem:${os_free_mem}GB Load:$loadavg] ${White}${OPTICALDISK_EMOJI}${NC} [$DEFAULT_SPLUNK_IMAGE] ${White}${YELLOWBOOK_EMOJI} LogLevel:${NC}[$loglevel]${NC}\n"
fi

return 0
}	#end display_stats_banner()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_docker_stats() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${Yellow}In 5 seconds we will enter a loop to continuously display containers stats :\n";
printf "${Red}Control-C to stop\n${NC}";
#Trap the killer signals so that we can exit with a good message.
#trap "error_exit 'Received signal SIGHUP'" SIGHUP
#trap "error_exit 'Received signal SIGINT'" SIGINT
#trap "error_exit 'Received signal SIGTERM'" SIGTERM
#trap return

sleep 5
docker stats  --format "HOST{{.Name}}   CPU:{{.CPUPerc}}   MEM:{{.MemPerc}}";
printf "${NC}\n"

# Execute when user hits control-c
  #printf "${Red} [docker stats command] CRASH! "
  #echo -en "\n*** Possibly due to a bug in [docker stats] command ***\n"
  #printf "${NC}\n"
  #return 1
  #exit $?

echo
return 0
}	#end display_docker_stats()
#---------------------------------------------------------------------------------------------------------------



#---------------------------------------------------------------------------------------------------------------
login_to_splunk_hub() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
user=`echo $USER`	#use shell to determine user id

#detect if already login to splunk registry
loged_in=`$GREP $SPLUNK_DOCKER_HUB ~/.docker/config.json 2>/dev/null`
if [ -n "$loged_in" ]; then
	#printf "Already logged in..\n"
	return 0
else
	read -p "You are not connected to [$SPLUNK_DOCKER_HUB]. Would you like to login? [Y/n]? " answer
        if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		read -p "Enter your username (default $user)? " username
    	if [ -z "$username" ];then username=$USER; fi
		read -s -p 'Enter your password (use O2 or HOD password)? ' passwd
		CMD=`docker login -u $username -p $passwd $SPLUNK_DOCKER_HUB`
        if ( compare "$CMD" "Login Succeeded" );then
            printf "${Green}Login Succeeded!\n"
		else
            printf "${LightRed}Login failed! Demo image download will fail\n"
		fi
	else
        printf "You still can use any cached images but further downloads will fail...\n"
	fi
fi
read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'

return 0
}	#end login_to_splunk_hub()
#---------------------------------------------------------------------------------------------------------------

##### DOWNLOADS ######

#---------------------------------------------------------------------------------------------------------------
spinner() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Modified version of spinner http://fitnr.com/showing-a-bash-spinner.html
#for i in `seq 1 100`; do printf "\033[48;5;${i}m${i} "; done
#echo "spinner(): pid:$1"

local pid=$1
local delay=5   #ex 0.75 second
local spinstr='|/-\'
i=0;  gTIMEOUT=""
SECONDS=0	#bash built-in function
#loop until spawn process exists (assuming job is completed)
while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
	local temp=${spinstr#?}
       # printf " [%c]  " "$spinstr"
	#printf "\033[48;5;${i}m\x41\\"
#       echo -en "\033[48;5;2m x\e[0m"
        local spinstr=$temp${spinstr%"$temp"}
	if [ "$i" -gt "10" ]; then i=0; printf "${Blue}▓${NC}"; fi  #blue block roughly every 1 min

	printf "▓"

        sleep $delay
	let i++
	elapsedseconds=$SECONDS
	if [ "$elapsedseconds"  -gt "$DOWNLOAD_TIMEOUT" ]; then
		gTIMEOUT="1"
	#	printf "TIMEOUT[$elapsedseconds]! Killing [$pid]${NC}\n"
	(kill -9 $pid > /dev/null ) &	#dont show the output, just do it
	fi
        #printf "\b\b\b\b\b\b"
done

printf "${NC}"
#printf "    \b\b\b\b"
return 0
}	#end spinner()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
progress_bar_image_download() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
image_name=$1
if ( compare "$image_name" "demo" ) || ( compare "$image_name" "workshop" ) ; then    #detect demo/workshop imagename (mostly lower case)
	hub="$SPLUNK_DOCKER_HUB/sales-engineering/"
	login_to_splunk_hub
elif ( compare "$image_name" "splunk" ); then		#detect splunk images
	#hub="hub.docker.com/r/"
	hub=""

else							#detect 3rd party images (can be any name)
	original_name=$image_name	#save it
#	image_name=`echo $image_name| sed 's/3rd-//g' `   #real images on docker hub don't have "3rd-"
	hub=""
fi
#echo "hub:[$hub]  imagename:[$image_name]";exit

#docker pull hub.docker.com/r/mhassan/splunk
#echo "[docker pull $hub$image_name]"
cached=`docker images | grep $image_name`
if [ -z "$cached" ]; then
	t_start=$(date +%s)
      	#printf "    ${Purple}$image_name:${NC}["
      	printf "Downloading ${Purple}$image_name${NC}:["
	check_status=""
      	#(docker pull $hub$image_name >/dev/null) &
      	(docker pull $hub$image_name > "tmp.$$") &
	background_pid=`ps xa|grep "docker pull $hub$image"| awk '{print $1}'`
	spinner $background_pid
	check_status=`grep -i "Digest" tmp.$$`

	t_end=$(date +%s)
	t_total=`echo $((t_end-t_start))|awk '{print int($1/60)":"int($1%60)}'`

	#fall back on verbose mode if progress_bar_download failed
	if [ -z "$TIMEOUT" ] && [ -z "$check_status" ];then
		printf "${Red} Timed out!${NC}]\n"
		printf "${Red}Terminating background download process [exceeded $DOWNLOAD_TIMEOUT sec].If download problem persists; try restarting docker daemon first!${NC}\n"
		printf ">>Retrying download in foreground with verbose mode...\n"
		printf ">>Running${BrownOrange} [docker pull $hub$image_name] ${NC}\n"
		sleep 5
      		time docker pull $hub$image_name
	else
		printf "] ${DarkGray} $t_total ${NC}\n"
	fi
else
      	printf "Downloading ${Purple}$image_name${NC}>[${White}*cached*${NC}]\n"

fi
original_name=""  #initialize for next round in case of consecutive downloads
rm -fr tmp.$$
return 0
}	#end progress_bar_image_download()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
progress_bar_pkg_download() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
install_cmd1="$1"
install_cmd2="$2"
install_cmd3="$3"
install_cmd2="$4"
START=$(date +%s)
printf "[${NC}"
( $install_cmd1 $install_cmd2 $install_cmd3 $install_cmd4> /dev/null 2>&1) &
spinner $!
printf "]${NC}"
END=$(date +%s)
TIME=`echo $((END-START)) | awk '{print int($1/60)":"int($1%60)}'`
printf "${DarkGray} $TIME${NC}\n"

return 0
}	#end progress_bar_pkg_download()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
download_demo_image() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
#-----------show images details
printf "${BoldYellowOnBlue}Manage Images -> DOWNLOAD DEMO IMAGES MENU ${NC}\n"
display_stats_banner
#printf "${BrownOrange}*Depending on time of the day downloads may take a while. Cached images are not downloaded! ${NC}\n"
printf "\n"
printf "Demo images available from $SPLUNK_DOCKER_HUB:\n"
printf "${BoldWhiteOnRed}             IMAGE NAME%-22s SIZE%-15s AUTHOR%-20s${NC}\n"
printf "${White} -------------------------------------      --------   ---------------------------------------\n"

counter=1
#count=`docker images --format "{{.ID}}" | wc -l`
for image_name in $REPO_DEMO_IMAGES; do
        printf "${Purple}%-2s${NC}) ${Purple}%-40s${NC}" "$counter" "$image_name"
	image_name="$SPLUNK_DOCKER_HUB/sales-engineering/$image_name"
#	echo "cached[$cached]\n"
	created=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $7,$8}'`
        if [ -n "$created" ]; then
        	author=`docker inspect $image_name |grep -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
                printf "%-12s %-7s %-10s ${NC}\n" "$created" "$size" "$author"
        else
                printf "${DarkGray}NOT CACHED! ${NC}\n"
        fi
        let counter++
done

printf "${BrownOrange}${BULB_EMOJI} You're required to login into splunk internal docker. You will prompted if creds are not cached${NC}\n"
login_to_splunk_hub

#build array of images list
declare -a list=($REPO_DEMO_IMAGES)
choice=""
read -p $'Choose number to download. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
        printf "${Yellow}Downloading selected demo image(s)...\n${NC}"
	START=$(date +%s)
        for id in `echo $choice`; do
		image_name=(${list[$id - 1]})
		progress_bar_image_download "$image_name"
        done
       # docker stop $choice
else
		printf "${DONT_ENTER_EMOJI}${LightRed} WARNING! \n"
        printf "This operation may take a long time (~20 mins). Make sure you have enough disk-space...${NC}\n"
	read -p "Are you sure? [Y/n]? " answer
	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
        	printf "${Yellow}Downloading all demo image(s)...\n${NC}"
		START=$(date +%s);
		for i in $REPO_DEMO_IMAGES; do
			progress_bar_image_download "$i"
		done
	fi
fi
        #read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
END=$(date +%s);
TIME=`echo $((END-START)) | awk '{print int($1/60)":"int($1%60)}'`
printf "    ${DarkGray}Total download time: [$TIME]${NC}\n"
return 0
}	#end download_demo_image()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
download_3rdparty_image() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
#-----------show images details
printf "${BoldYellowOnBlue}Manage Images -> DOWNLOAD 3RD PARTY IMAGES MENU ${NC}\n"
display_stats_banner
printf "\n"
printf "${BrownOrange}*Depending on time of the day downloads may a take long time.Cached images are not downloaded! ${NC}\n"
printf "\n"
printf "3rd party images available from docker hub:\n"
printf "${Purple}     		IMAGE NAME${NC}		    CREATED	SIZE			AUTHOR\n"
printf "${Purple} -------------------------------------${NC}   ------------  --------   ---------------------------------------\n"
counter=1
#count=`docker images --format "{{.ID}}" | wc -l`
for image_name in $REPO_3RDPARTY_IMAGES; do
        printf "${Purple}%-2s${NC}) ${Purple}%-40s${NC}" "$counter" "$image_name"
	created=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | grep -v REPOSITORY | awk '{print $7,$8}'`
        if [ -n "$created" ]; then
        	author=`docker inspect "$image_name" |grep -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
                printf "%-12s %-7s %-10s ${NC}\n" "$created" "$size" "$author"
        else
                printf "${DarkGray}NOT CACHED! ${NC}\n"
        fi
        let counter++
done
echo
#build array of images list
declare -a list=($REPO_3RDPARTY_IMAGES)

choice=""
read -p $'Choose number to download. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
        printf "${Yellow}Downloading selected 3rd party image(s)...\n${NC}"
        START=$(date +%s)
        for id in `echo $choice`; do
                image_name=(${list[$id - 1]})
                progress_bar_image_download "$image_name"
        done
       # docker stop $choice
else
        #printf "${Red}WARNING! This operation may take time. Make sure you have enough disk-space...${NC}\n"
        read -p $'Are you sure? [\033[1;37mY\033[0m/n]? ' answer
        if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                printf "${Yellow}Downloading all 3rd party image(s)...\n${NC}"
                START=$(date +%s);
                for i in $REPO_3RDPARTY_IMAGES; do
                        progress_bar_image_download "$i"
                done
        fi
fi
        #read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
END=$(date +%s);
TIME=`echo $((END-START)) | awk '{print int($1/60)":"int($1%60)}'`
printf "    ${DarkGray}Total download time: [$TIME]${NC}\n"
return 0
}	#end download_3rdparty_image()
#---------------------------------------------------------------------------------------------------------------


#### CONTAINERS ######

#---------------------------------------------------------------------------------------------------------------
list_all_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type=$1         #container type (ex DEMO, 3RDPARTY, empty for ALL)

clear
printf "${BoldWhiteOnYellow}LIST $type CONTAINERS MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers "$type"
echo
count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
        printf "\nNo $type container to list!\n"
        return 0
fi
echo

return 0
}       #end list_all_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
start_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type=$1
clear
printf "${BoldWhiteOnYellow}START $type CONTAINERS MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers "$type"
echo
count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
        printf "No $type container found!\n"
        return 0;
fi

#build array of containers list
declare -a list=($(docker ps -a --filter name="$type" --format "{{.Names}}" | sort | tr '\n' ' '))

choice=""
read -p $'Choose number to start. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
        printf "${Yellow}Starting selected $type containers...\n${NC}"
        for id in `echo $choice`; do
                #printf "${Purple} ${list[$id - 1]}:${NC}\n"
                hostname=${list[$id - 1]}
		docker start "$hostname"
        done
else
        printf "${Yellow}Starting all $type containers...\n${NC}"
	#docker start $(docker ps -a --format "{{.Names}}")
	docker start $(docker ps -a --filter name="$type" --format "{{.Names}}" | tr '\n' ' ')
        rm -fr $HOSTSFILE
fi
read -p $'\033[1;32mHit <ENTER> to show new status (some change need time to take effect)...\e[0m'
list_all_containers "$type"

return 0
}	#start_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
stop_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type=$1
clear
printf "${BoldWhiteOnYellow}STOP $type CONTAINERS MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers "$type"
echo
count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
	printf "No $type container found!\n"
        return 0;
fi
#build array of containers list
declare -a list=($(docker ps -a --filter name="$type" --format "{{.Names}}" | sort | tr '\n' ' '))

choice=""
read -p $'Choose number to stop. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
        printf "${Yellow}Stopping selected $type containers...\n${NC}"
        for id in `echo $choice`; do
                #printf "${Purple} ${list[$id - 1]}:${NC}\n"
    		hostname=${list[$id - 1]}
        	docker stop "$hostname"
	done
else
        printf "${Yellow}Stopping all $type containers...\n${NC}"
       # docker stop $(docker ps -aq);
	docker stop $(docker ps -a --filter name="$type" --format "{{.Names}}" | tr '\n' ' ')
        rm -fr $HOSTSFILE
fi
read -p $'\033[1;32mHit <ENTER> to show new status (some change need time to take effect)...\e[0m'
list_all_containers "$type"

return 0
}	#stop_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
delete_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type=$1

clear
printf "${BoldWhiteOnYellow}DELETE $type CONTAINERS MENU ${NC}\n"
display_stats_banner
printf "\n"
display_all_containers "$type"
echo
count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
        printf "No $type containers found!\n"
        return 0;
fi
#build array of containers list
declare -a list=($(docker ps -a --filter name="$type" --format "{{.Names}}" | sort | tr '\n' ' '))
echo

choice=""
read -p $'Choose number to delete. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
        printf "${Yellow}Deleting selected $type containers...\n${NC}"
        for id in `echo $choice`; do
                hostname=${list[$id - 1]}
                #printf "${Purple}$hostname${NC}\n"
                docker rm -v -f "$hostname"
        done
       # docker stop $choice
else
        printf "${Yellow}Deleting all $type containers and volumes...\n${NC}"
       # docker rm -v -f $(docker ps -a --format "{{.Names}}");
	docker rm -v -f $(docker ps -a --filter name="$type" --format "{{.Names}}" | tr '\n' ' ')
        rm -fr $HOSTSFILE
#       delete_all_volumes
fi
read -p $'\033[1;32mHit <ENTER> to show new status (some change need time to take effect)...\e[0m'
list_all_containers "$type"

return 0
}       #end delete_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_all_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type=$1		#container type (ex DEMO|WORKSHOP, 3RDPARTY, empty for ALL)
#curl http://169.254.169.254/latest/meta-data/public-hostname| sed 's/aws.com/aws.com \n/g'

if [ "$AWS_EC2" == "YES" ]; then
	rm -fr aws_eip_mapping.tmp
	for i in `curl -s http://169.254.169.254/latest/meta-data/public-hostname| sed 's/aws.com/aws.com \n/g' `; do
		external_ip=`dig +short $i`
		echo  "$external_ip $i"  >> aws_eip_mapping.tmp
	done
fi
printf "Current list of all $type containers on this system:\n"
printf " ${BoldWhiteOnRed}  Host(container)%-5s State%-2s Splunkd%-2s Ver%-2s Internal IP%-3s Image used%-15s     URL%-13s${NC}\n"
printf "   ---------------%-3s --------- ------- ------- ----------%-3s------------------%-3s---------------------------${NC}\n"

i=0
hosts_sorted=`docker ps -a --format {{.Names}}| egrep -i "$type"| sort`

for host in $hosts_sorted ; do
    let i++	#container display counter (starts at zero now that we have special DOCKER-MONITOR)
    id=`docker ps -a --no-trunc --filter  name="^/$host$" --format {{.ID}}`
    #These operations take long time execute
    #cpu_percent=`docker stats $id -a --no-stream |grep -v CONTAINER|awk '{print $2}'`
    #mem_usage=`docker stats $id -a --no-stream |grep -v CONTAINER|awk '{print $3$4}'`
    #mem_limit=`docker stats $id -a --no-stream |grep -v CONTAINER|awk '{print $6$7}'`
    #mem_percent=`docker stats $id -a --no-stream |grep -v CONTAINER|awk '{print $8}'`

    internal_ip=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$id"`
    bind_ip=`docker inspect --format '{{ .HostConfig }}' "$id"| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
    hoststate=`docker ps -a --filter id="$id" --format "{{.Status}}" | awk '{print $1}'`
    hostname=`docker ps -a --filter id="$id" --format "{{.Names}}"`
    imagename=`docker ps -a --filter id="$id" --format "{{.Image}}" | cut -d'/' -f2-3`  #remove repository name
    splunkd_ver=`docker exec "$hostname" /opt/splunk/bin/splunk version 2>/dev/null | awk '{print $2}'`
    host_line[$i]="$bind_ip"
    if [ "$AWS_EC2" == "YES" ]; then
		eip=`grep "$bind_ip" aws_eip_mapping.tmp | awk '{print $2}'`
	    eip="$bind_ip $eip:$SPLUNKWEB_PORT_EXT"
	else
		eip="http://$bind_ip:$SPLUNKWEB_PORT_EXT"
    fi

    #check splunk state if container is UP
    if [ "$hoststate" == "Up" ]; then
	#check splunkstate
        splunkstate=`docker exec -ti "$id" /opt/splunk/bin/splunk status| $GREP splunkd| awk '{ print $3}'`
    else
        splunkstate="${Red}N/A${NC}"
		splunkd_ver="N/A"
    fi

    #set host state color. Use printf "%b" to show interpreting backslash escapes in there
    case "$hoststate" in
        Up)      hoststate="${Green}Up${NC}" ;;
        Created) hoststate="${DarkGray}Created${NC}" ;;
        Exited)  hoststate="${Red}Exited${NC}" ;;
    esac

    #set splunk state color
    if ( compare "$splunkstate" "running" ); then
                splunkstate="${Green}Running${NC}"
    else
                splunkstate="${Red}Down${NC}   "
    fi

    #3rd party don't have splunk
    if ( compare "$hostname" "3RDP" ); then
        splunkd_ver="N/A"
        splunkstate="${Red}N/A${NC}"
    fi
	#indentation:
	fmt_i="%-2s"
	fmt_hostname="%-20s"
	fmt_hoststate="%-18b"
	fmt_splunkstate="%-18b"
	fmt_splunkver="%-6s"
	fmt_bind_ip="%-12s"
	fmt_internal_ip="%-12s"
	fmt_imagename="%-20s"
	fmt_eip="%-30s"

    if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) ; then
        	printf "${LightCyan}$fmt_i) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$i" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"
   	elif ( compare "$hostname" "3RDP" ); then
			open_ports=`docker port $hostname|$GREP -Po "\d+/tcp|udp"|tr -d '\n'| sed 's/tcp/tcp /g' `
        	printf "${LightPurple}$fmt_i) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$i" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$open_ports"
		#for y in $open_ports; do printf "%80s\n" "$y"; done

    elif ( compare "$hostname" "DEP" ); then
        	printf "${LightBlue}$fmt_i) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$i" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"

    elif ( compare "$hostname" "CM" ); then
        	printf "${LightBlue}$fmt_i) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$i" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"

    elif ( compare "$hostname" "DMC" ); then
        	printf "${LightBlue}$fmt_i) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$i" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"

    else 	###generic
        	printf "${LightBlue}$fmt_i) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$i" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"
   	fi

  	if [ -z "$bind_ip" ]; then
       printf "${Red}<NOT BUILT BY THIS SCRIPT!${NC}\n"
    else
        printf "${NC}\n"
    fi

done

printf "count: %s\n\n" $i

#only for the Mac
#if [ "$os" == "Darwin" ]; then
#       read -p 'Select a host to launch in your default browser <ENTER to continue>? '  choice
#       #echo "Choice[$choice] i=[$i]"
#       if [ -z "$choice" ]; then
#               continue
#       elif [ "$choice" -le "$i" ] && [ "$choice" -ne "0" ] ; then
#                       open http://${host_line[$choice]}:$SPLUNKWEB_PORT_EXT
#               else
#                       printf "Invalid choice! Valid options [1..$i]\n"
#       fi
#fi
return 0
}	#end display_all_containers()
#---------------------------------------------------------------------------------------------------------------

#### IMAGES ########

#---------------------------------------------------------------------------------------------------------------
remove_images() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
type=$1
printf "${BoldWhiteOnRed}REMOVE $type IMAGES MENU ${NC}\n"
display_stats_banner
printf "\n"
printf "Current list of all $type images downloaded on this system:\n"
display_all_images "$type"
echo

if [ "$type" == "3RDP" ]; then
	id_list=$(docker images  -a| grep -v "REPOSITORY" | egrep -iv "DEMO|WORKSHOP"| grep -iv "splunk"| awk '{print $3}'| tr '\n' ' ')
elif [ "$type" == "DEMO" ]; then
	id_list=$(docker images  -a| grep -v "REPOSITORY" | egrep -i "DEMO|WORKSHOP" | awk '{print $3}'| tr '\n' ' ')
else
	id_list=$(docker images  -a| grep -v "REPOSITORY" | awk '{print $3}'| tr '\n' ' ')
fi

#build array of images list
declare -a list=($id_list)

if [ "${#list[@]}" == "0" ]; then
        printf "\nCannot find any $type images in the system!\n"
        return 0
fi

echo
choice=""
read -p $'Choose number to remove. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -n "$choice" ]; then
        printf "${Yellow}Deleting selected $type image(s)...\n${NC}"
        for id in `echo $choice`; do
               #echo "$id : ${list[$id - 1]}"
        	imagename=`docker images|grep  ${list[$id -1]} | awk '{print $1}'`
               	printf "${Purple}Deleting:$imagename${NC}\n"
               	#printf "${Purple} ${list[$id - 1]}:${NC}\n"
               	docker rmi -f ${list[$id - 1]}
        done
else
	if [ "$(docker ps -a --filter name="$type" --format "{{.Names}}")" ]; then  	#stop running containers first
		printf "${Yellow}Stop any running containers first...\n"
		docker stop $(docker ps -a --filter name="$type" --format "{{.Names}}")
		#docker stop $id_list
        fi
	printf "${Yellow}Deleting all $type images...\n${NC}"
       # docker rmi -f $(docker images|grep -v "REPOSITORY"|grep -i "$type" |awk '{print $3}')
	docker rmi -f $id_list
fi
return 0
}	#end remove_images()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
show_all_images() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type=$1
clear
printf "${BoldWhiteOnRed}SHOW $type IMAGES MENU ${NC}\n"
display_stats_banner
printf "\n"
printf "Current list of $type images downloaded on this system:\n"
display_all_images "$type"
echo

return 0
}	#end show_all_images()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_all_images() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function displays custom view all images downloaded.

#clean up the anoying "none" images first
#docker rmi $(docker images -a | grep "^<none>" | awk '{print $3}')
type=$1
id_list=""
count=`docker images --format "{{.ID}}" | wc -l`
if [ $count == 0 ]; then
        printf "\nNo $type images to list!\n"
        return 0
fi
if [ "$type" == "3RDP" ]; then
	id_list=$(docker images  -a| grep -v "REPOSITORY" | egrep -iv "DEMO|WORKSHOP"| grep -iv "splunk"| awk '{print $3}'| tr '\n' ' ')

elif [ "$type" == "DEMO" ] || [ "$type" == "WORKSHOP" ]; then
	id_list=$(docker images  -a| grep -v "REPOSITORY" | egrep -i "DEMO|WORKSHOP" | awk '{print $3}'| tr '\n' ' ')
else
	id_list=$(docker images  -a| grep -v "REPOSITORY" | awk '{print $3}'| tr '\n' ' ')
fi
count=0
for id in $id_list; do
        let count++
        imagename=`docker images|grep  $id | awk '{print $1}'`
        imagetag=`docker images|grep  $id | awk '{print $2}'`
        created=`docker images|grep  $id | awk '{print $4,$5,$6}'`
        size=`docker images|grep  $id | awk '{print $7,$8}'`
        sizebytes=`docker images|grep  $id | awk '{print $7,$8}'`
        printf "${LightBlue}$count) ${NC}Name:${LightBlue}%-50s ${NC}Tag:${LightBlue}%-10s ${NC}Size:${LightBlue}%-10s ${NC}Created:${LightBlue}%-15s ${NC}\n" "$imagename" "$imagetag" "$size" "$created"
done
printf "count: %s\n\n" $count

return 0
}	#end display_all_images()
#---------------------------------------------------------------------------------------------------------------

###### MISC #####

#---------------------------------------------------------------------------------------------------------------
delete_all_volumes() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#disk1=`df -kh /var/lib/docker/| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
#disk1=`df -kh $MOUNTPOINT| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
printf "${Yellow}Deleting all volumes...\n${NC}"
docker volume rm $(docker volume ls -qf 'dangling=true')
#rm -fr $MOUNTPOINT
#disk2=`df -kh $MOUNTPOINT| awk '{print $4}'| $GREP -v Avail|sed 's/G//g'`
#freed=`expr $disk2 - $disk1`
#printf "Disk space recovered: [$freed] GB\n"
rm -fr $HOSTSFILE

return 0
}	#end delete_all_volumes()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
wipe_entire_system() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnGreen}WIPE CLEAN ENTIRE SYSTEM MENU ${NC}\n"
display_stats_banner
printf "\n"
printf "${DONT_ENTER_EMOJI}${LightRed} WARNING!${NC}\n"
printf "${LightRed}This option will remove IP aliases, delete all containers, delete all images and remove all volumes! ${NC}\n"
printf "${LightRed}Use this option only if you want to return the system to a clean state! ${NC}\n"
printf "${LightRed}Restarting the script will recreate every thing again! ${NC}\n"
printf "\n"
read -p "Are you sure you want to proceed? [y/N]? " answer
        if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                printf "${Yellow}Stopping all containers...${NC}\n"
		docker stop $(docker ps -aq)
                printf "\n"
		printf "${Yellow}Deleting all containers...\n${NC}"
        	docker rm -f $(docker ps -a --format "{{.Names}}");
		printf "\n"
                printf "${Yellow}Removing all images...${NC}\n"
		docker rmi -f $(docker images -q)
		printf "\n"
		printf "${Yellow}Removing all volumes (including dangling)...${NC}\n"
		docker volume rm $(docker volume ls -qf 'dangling=true')
                printf "\n"

                printf "${Yellow}Removing all IP aliases...${NC}\n"
		remove_ip_aliases
		printf "\n"

		printf "${Red}Removing all dependency packages [brew ggrep pcre]? ${NC}\n"
		read -p "Those packages are not a bad thing to have installed. Are you sure you want to proceed? [y/N]? " answer
        	if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
			#remove ggrep, pcre
			brew uninstall ggrep pcre

			#remove brew
			/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall)"
	#		sudo rm -rf /usr/local/Homebrew/
		fi

	 	printf "\n\n"
                echo -e "Life is good! Thank you for using Splunk n' Box v$GIT_VER\n"
		printf "Please send feedback to mhassan@splunk.com \n"
		exit
fi

return 0
}	#end wipe_entire_system()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_welcome_screen() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

# Find out current screen width and hight
# Set a trap to restore terminal on Ctrl-c (exit).
# Reset character attributes, make cursor visible, and restore
# previous screen contents (if possible).
#trap 'tput sgr0; tput cnorm; tput rmcup || clear; exit 0' SIGINT
# Save screen contents and make cursor invisible
#tput smcup; tput civis
tput clear
COLUMNS=$(tput cols)
LINES=$(tput lines)
#echo "cols:$COLUMNS"
#echo "lines:$LINES"
new=""
colored_git_version=`echo $GIT_VER|awk -F '[.-]' '{print "\033[1;33m"$1"\033[0;33m."$2"\033[1;31m-" $3"\033[0m"}'`
#Dont prompt for upgrade if we cannot get GIT_VER ( missing ggrep)
if [ -z "$GIT_VER" ]; then
	new="N"
	colored_git_version="${LightRed}*UNKNOWN*${NC}     "
fi

MESSAGE[1]=""
MESSAGE[2]="Welcome to Splunk N\' Box v$colored_git_version"
MESSAGE[3]="Splunk SE essential tool"
MESSAGE[4]=""
MESSAGE[5]="Please set your terminal to full mode"
MESSAGE[6]="https://github.com/mhassan2/splunk-n-box"
MESSAGE[7]="By continuing you accept Splunk software license agreement"
#MESSAGE[6]="https://www.splunk.com/en_us/legal/splunk-software-license-agreement.html"
#MESSAGE[7]=""
MESSAGE[10]="This script is licensed under Apache 2.0 All rights reserved Splunk Inc 2005-2018"

# Calculate x and y coordinates so that we can display $MESSAGE
# centered in the screen
x=$(( $LINES / 2 ))                             #centered in the screen
num_of_msgs=${#MESSAGE[@]}
z=0

#-----show splunknbox logo only if imgcat is installed & and jpeg file exist -------
#	Otherwise skip with no feedback -------------
condition=$(which imgcat 2>/dev/null | grep -v "not found" | wc -l)
if [ $condition != "0" ] && [ -e img/splunknbox_logo.png ]; then
	col=$(( ( $COLUMNS - 13 )  / 2 )); row=$(($x - 9)); tput cup $row $col
	imgcat img/splunknbox_logo.png
fi
#----------------------------------------------------------------------

for (( i=x; i <= (x + $num_of_msgs); i++)); do
        let z++
		msg_len=${#MESSAGE[$z]}
        col=$(( ( $COLUMNS - $msg_len )  / 2 ))
		row=$(($i - 4))
		if ( compare "${MESSAGE[$z]}" "Box" ); then
			col=$(($col + 12))
		fi
        tput cup $row $col                 #set x and y position
        tput bold   #set reverse video mode
        # Alright display message stored in $MESSAGE
		#printf "($row,$col)\033[0;36m${MESSAGE[$z]}"
		printf "\033[0;36m${MESSAGE[$z]}"

done
rm -fr $TMP_DIR/online_ver.tmp		#start fresh
wget -qO $TMP_DIR/online_ver.tmp "https://raw.githubusercontent.com/mhassan2/splunk-n-box/master/VERSION.TXT"
online_ver=`cat $TMP_DIR/online_ver.tmp`
colored_online_ver=`echo $online_ver | awk -F '[.-]' '{print "\033[1;33m" $1 "\033[0;33m." $2 "\033[1;31m-" $3}'`

new=`awk -v n1=$online_ver -v n2=$GIT_VER 'BEGIN {if (n1>n2) print ("Y");}'  `

if [ "$new" == "Y" ] && [ -n "$GIT_VER" ] && [ -n "$online_ver" ]; then
	#tput cup $LINES $(( ( $COLUMNS - ${#MESSAGE[10]} )  / 2 ))
	tput cup $LINES 0
	printf "Checking for new version... [found $colored_online_ver${NC}]\n"
	printf "\033[0m"
	read -p $"Newer version available. Upgrade? [Y/n]? " answer
	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		tput cup $LINES 0
		printf "Downloading [$PWD/${0##*/}] >> ${NC}"
		progress_bar_pkg_download "curl -O https://raw.githubusercontent.com/mhassan2/splunk-n-box/master/${0##*/}"
		#curl --max-time 5 -O https://raw.github.com/mhassan2/splunk-n-box/master/${0##*/}
		chmod 755  ${0##*/}   	#set x permission on splunknbox.sh
	#	./$(basename $0) && exit  # restart the script
		echo
		printf "${Yellow}Please restart the script!${NC}                          \n\n"
		exit

	fi
fi

tput cup $LINES $(( ( $COLUMNS - ${#MESSAGE[10]} )  / 2 ))
printf "\033[0;34m${MESSAGE[10]}"
# Just wait for user input...
read -p "" readKey
# Start cleaning up our screen...
tput clear
tput sgr0	#reset terminal (doesn't always work)
tput rc

return 0
}	#end display_welcome_screen()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_goodbye_msg() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
echo;echo;echo
printf "\033[31m           0000\033[0m_____________0000________0000000000000000__000000000000000000+\n\033[31m         00000000\033[0m_________00000000______000000000000000__0000000000000000000+\n\033[31m        000\033[0m____000_______000____000_____000_______0000__00______0+\n"
printf "\033[31m       000\033[0m______000_____000______000_____________0000___00______0+\n\033[31m      0000\033[0m______0000___0000______0000___________0000_____0_____0+\n"
printf "\033[31m      0000\033[0m______0000___0000______0000__________0000___________0+\n\033[31m      0000\033[0m______0000___0000______0000_________000___0000000000+\n"
printf "\033[31m      0000\033[0m______0000___0000______0000________0000+\n\033[31m       000\033[0m______000_____000______000________0000+\n"
printf "\033[31m        000\033[0m____000_______000____000_______00000+\n\033[31m         00000000\033[0m_________00000000_______0000000+\n\033[31m           0000\033[0m_____________0000________000000007;\n"
echo;echo
return 0
}	#display_goodbye_msg()
#---------------------------------------------------------------------------------------------------------------


#<<<<<<<<<<<<<----------   MAIN BEGINS     ---------->>>>>>>>>>>>

#---------------------------------------------------------------------------------------------------
#The following must start at the beginning for the code since we use I/O redirection for logging
#http://stackoverflow.com/questions/8455991/elegant-way-for-verbose-mode-in-scripts/8456046
loglevel=$LOGLEVEL
maxloglevel=7	 #The highest loglevel we use / allow to be displayed.

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.
output_file=""
while getopts "h?v:s:g:c:f:" opt; do
    case "$opt" in
    h|\?)
		printf "Usage:\n"
        printf "\t-v[2|3|4|5|6]\tSet log level\n"
		printf "\t-s[true]\tSkip startup checks (if all requirements are satisfied).${LightRed}**Use with caution***${NC}\n"
        printf "\t-f[filename]\tSet log file name\n"
        exit 0
        ;;
    v)  loglevel=$OPTARG
        ;;
    s)  skip_checks=$OPTARG
		;;
    g)  graphics=$OPTARG
		;;
    c)  cluster=$OPTARG
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

#delete log files on restart
#rm  -fr $CMDLOGBIN $CMDLOGTXT
printf "\n--------------- Starting new script run. Hosts are grouped by color -------------------\n" > $CMDLOGBIN
tput setab 0
clear
detect_os						#ggrep OSX is set here
detect_ver
if [ -z "$skip_checks" ] || [ "$skip_checks" != "true" ];then
	startup_checks				#contains ggrep install if missing OSX (critical command)
fi

if [ "$cluster" == "1" ];then
	create_single_idxc "AUTO"
elif [ "$cluster" == "2" ];then
	create_single_shc "AUTO"
elif [ "$cluster" == "3" ];then
	build_single_site "AUTO"
elif [ "$cluster" == "4" ];then
	build_multi_site "AUTO"

fi
display_welcome_screen		#ggrep must installed otherwise ver check will fail
main_menu_inputs


#<<<<<<<<<<<<<----------   MAIN ENDS     ---------->>>>>>>>>>>>

##### EOF #######
