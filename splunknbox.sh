#!/bin/bash
#################################################################################
#	__VERSION: 5.1-8 $
#	__DATE: Thu May 31,2018 - 03:03:25AM -0600 $
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
#	-Complete multi and single site cluster builds including CM,LM,MC and DEP servers
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
#START_ALIAS_OSX=10.2.237.1"";  		END_ALIAS_OSX="10.2.237.49"

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
DEFAULT_SPLUNK_IMAGE="splunknbox/splunk_7.1.1"

#DEFAULT_SPLUNK_IMAGE="splunk/splunk"		#official image
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
LL_APPS="splunk-datasets-add-on_10.tgz machine-learning-toolkit_210.tgz customer-search-party-app_10.tgz splunk-enterprise-65-overview_13.tgz splunk-6x-dashboard-examples_60.tgz splunk-common-information-model-cim_470.tgz eventgen.spl"
#python-for-scientific-computing-for-linux-64-bit_12.tgz" #too large for github 63M
LL_DATASETS="http_status.csv tutorialdata.zip"
#---------------------------------------
#-------- containers stuff --------------
MASTER_CONTAINER="MONITOR" 	#name of master container used to monitor ALL containers
BASEHOSTNAME="HOST"					#default hostname to create
CM_BASE="CM"
MC_BASE="MC"
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
USERPASS="hello1234"
#----------------------------------------------------

#----------Cluster stuff----------------
R_FACTOR="2"							#default replication factor
S_FACTOR="2"							#default search factor
DEF_SITE_REP_FACT="origin:2,total:3"
DEF_SITE_SEARCH_FACT="origin:1,total:2"
DEFAULT_SHC_LABEL="shcluster1"
DEFAULT_IDXC_LABEL="idxcluster1"
LABEL="buttercup"
DEF_SINGLE_SITE="DC01"  					#used in single-site build
DEF_MULTI_SITES="LON HKG"  		#used in multi-site build

MYSECRET="mysecret"					#defualt Pass4SymmKey
STD_IDXC_COUNT="3"					#default IDXC count
STD_SHC_COUNT="3"					#default SHC count
DEP_SHC_COUNT="1"					#default DEP count
#------------------------------------------
#---------DIRECTORIES & Logs-----------------------------
DEFAULT_LOG_LEVEL=3
DEFAULT_TIMER=30
FILES_DIR="$PWD" 			#place anything needs to copy to container here
TMP_DIR="$PWD/tmp"			#used as scrach space
LOGS_DIR="$PWD/logs"		#store generated logs during run
CMDLOGBIN="$LOGS_DIR/splunknbox_bin.log"		#capture all docker cmds (with color)
CMDLOGTXT="$LOGS_DIR/splunknbox.log"			#capture all docker cmds (just ascii txt)
#LOGFILE="${0##*/}.log"   						#log file will be this_script_name.log
#SCREENLOGFILE="$LOGS_DIR/splunknbox_screens.log"  #capture all screen shots during execution
HOSTSFILE="$PWD/docker-hosts.dnsmasq"  	#local host file. optional if dns caching is used
SPLUNK_LIC_DIR="$PWD/splunk_licenses"	#place all your license file here
VOL_DIR="docker-volumes"				#volumes mount point.Full path is dynamic based on OS type
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
MACSPEAK_VOL="7"					#default volume for MacOS speak feature
#--------------------------------------------------------------------
#--Progress status. tput (R,0) locations ---------
R_HEADER="0"
R_BANNER="1"
R_BUILD_SITE="3"
R_STEP1="4"
R_STEP2="5"
R_STEP3="6"
R_STEP4="7"
R_STEP5="8"
R_STEP6="9"
R_STEP7="10"
R_STEP8="11"
R_STEP9="12"
R_STEP10="13"
R_LINE="10"; R_ROLL="11"	#defaults

#MAXLEN="55"		#fill until for docker_status msgs (rolling scr size)
MAXLEN="56"			#progress section length
C_PROGRESS="55"		#progress section width
R_SCR_END_FACTOR="4" #max_rows - factor=rolling scr size
#---------------------------------------------------------

#--------COLORES ESCAPE CODES------------
#for i in `seq 1 100`; do printf "\033[48;5;${i}m${i} "; done
#https://misc.flogisoft.com/bash/tip_colors_and_formatting
NC='\033[0m' # No Color
Black="\033[0;30m";             White="\033[1;37m"
Red="\033[0;31m";               LightRed="\033[1;31m"
Green="\033[0;32m";             LightGreen="\033[1;32m"
BrownOrange="\033[0;33m";       Yellow="\033[1;33m"
Blue="\033[0;34m";              LightBlue="\033[1;34m"
Purple="\033[0;35m";            LightPurple="\033[1;35m"
Cyan="\033[0;36m";              LightCyan="\033[1;36m"
LightGray="\033[0;37m";         DarkGray="\033[1;30m"

WhiteOnLightBlue="\033[48;5;12m"
WhiteOnOrange="\033[48;5;166m"
WhiteOnGreen="\033[48;5;2m"
WhiteOnRed="\033[48;5;1m"
#used for docker status bar.
Gray1="241"
Gray2="100"
WhiteOnGray1="\033[97;48;5;${Gray1}m";		WhiteOnGray2="\033[97;48;5;${Gray2}m"
LightRedOnGray1="\033[91;48;5;${Gray1}m";	LightRedOnGray2="\033[91;48;5;${Gray2}m";
RedOnGray1="\033[31;48;5;${Gray1}m";		RedOnGray2="\033[31;48;5;${Gray2}m"
LightGreenOnGray1="\033[92;48;5;${Gray1}m";LightGreenOnGray2="\033[92;48;5;${Gray2}m"
LightYellowOnGray1="\033[93;48;5;${Gray1}m";LightYellowOnGray2="\033[93;48;5;${Gray2}m"
#used for phase/step titles displays
BoldWhiteOnRed="\033[1;1;5;41m"; BoldWhiteOnGreen="\033[1;1;5;42m"
BoldWhiteOnYellow="\033[1;1;5;43m"; BoldWhiteOnBlue="\033[1;1;5;44m"
BoldWhiteOnLightBlue="\033[1;1;5;104m"; BoldWhiteOnPink="\033[1;1;5;45m"
BoldWhiteOnTurquoise="\033[1;1;5;46m"; BoldYellowOnBlue="\033[1;33;44m"
BoldYellowOnPurple="\033[1;33;44m"
#-----------------------------------------
BoldWhiteOnBlue="\033[44;5;70;1m"
BoldGreenOnBlue="\033[44;5;92;1m"
BoldYellowOnBlue="\033[44;5;93;1m"
BoldRedOnBlue="\033[44;5;91;1m"
BoldWhiteOnDarkRed="\033[48;5;88;1m"
BoldWhiteOnDarkGreen="\033[48;5;28;1m"
BoldWhiteOnLimeGreen="\033[48;5;40;1m"


#R_PROGRESS_COLOR="${WhiteOnOrange}"		#progress status
R_PROGRESS_COLOR="${BoldWhiteOnDarkGreen}"		#progress status
R_BUILD_COLOR="${WhiteOnGray1}"			#build site status
R_LINE_COLOR="$R_BUILD_COLOR"			#R_BUILD line
#HEADER_COLOR="${WhiteOnGray1}"
HEADER_COLOR="${BoldWhiteOnBlue}"
FOOTER_COLOR1="${BoldWhiteOnBlue}"			#sync with header colors
FOOTER_COLOR2="${BoldGreenOnBlue}"		#docker counters colors
FOOTER_COLOR3="${BoldYellowOnBlue}"	#when loadavg Yellow
FOOTER_COLOR4="${BoldRedOnBlue}"		#when loadavg Red

#ACTION_COLOR="$BoldWhiteOnLightBlue"	#containers CREATE, DEL,STOP...etc
ACTION_COLOR="$BoldWhiteOnGreen"	#containers CREATE, DEL,STOP...etc
INACTIVE_TXT_COLOR="\033[1;30m"			#unprocessed step
ACTIVE_TXT_COLOR="${White}"				#processed step
#ACTIVE_TXT_COLOR="\033[1;35m"
#ACTIVE_TXT_COLOR="\033[1;91m"
DONE_STEP_COLOR="\033[1;32m"

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
COMPUTER_EMOJI="\xf0\x9f\x96\xa5"
OPTICALDISK_EMOJI="\xf0\x9f\x92\xbf"
YELLOWBOOK_EMOJI="\xf0\x9f\x93\x92"
YELLOW_LEFTHAND_EMOJI="\xf0\x9f\x91\x89"
TIMER_EMOJI="\xe2\x8f\xb0"
RED_BALL_EMOJI="\xf0\x9f\x94\xb4"
BELL_EMOJI="\xf0\x9f\x94\x94"
NO_BELL_EMOJI="\xf0\x9f\x94\x95"


#---------------------------------------


#**** Let the fun begin.I will see you 5000+ lines later! ***

#Log level is controlled with I/O redirection. Must be first thing executed in a bash script
# Redirect stdout ( > ) into a named pipe ( >() ) running "tee"
#exec >> >(tee -i $SCREENLOGFILE)
exec 2>&1

#---------------------------------------------------------------------------------------------------------------
_debug_function_inputs() {

func_name="$1"; arg_num="$2"; param_list="$3"; calls="$4"

#printf "#--------------------[$func_name] ( $param_list )------------------\n" >> $CMDLOGTXT
calls_count=`echo $calls|wc -w|sed 's/ //g'`
calls=`echo $calls| sed 's/ / <- /g'`

printf "\n${LightRed}CALLS:($calls_count) =>${Yellow}[$calls]${NC}\n" >&5
printf "\n${LightRed}STARTING: $func_name() :=> ${Purple}args:[$arg_num] ${Yellow}(${LightGreen}$param_list${Yellow})${NC}\n" >&5

return 0
}	#end _debug_function_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
function catimg() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

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
cmd="$1"; curr_host="$2"
#DATE=` date +'%b %e %R'`
DATE=`date +%Y-%m-%d:%H:%M:%S`
#echo "curr[$curr_host]  prev[$prev_host]" >> $CMDLOGBIN

#change log entry color when the remote docker cmd executed in new host
#if [ "$FLIPFLOP" == 0 ] && [ "$curr_host" != "$prev_host" ]; then
#	FLIPFLOP=1; COLOR="${LightBlue}"; echo > $CMDLOGBIN
#elif [ "$FLIPFLOP" == 1 ] && [ "$curr_host" != "$prev_host" ]; then
#	FLIPFLOP=2; COLOR="${Yellow}"; echo > $CMDLOGBIN
#elif [ "$FLIPFLOP" == 2 ] && [ "$curr_host" != "$prev_host" ]; then
#        FLIPFLOP=0; COLOR="${LightCyan}"; echo > $CMDLOGBIN
#fi

#printf "${White}[$DATE]" >>$CMDLOGBIN
printf "[$DATE:$curr_host] $CMD\n" >> $CMDLOGTXT

#echo "[$DATE] $CMDLOGBIN
#sed "s,\x1B\[[0-9;]*[a-zA-Z],,g" -i $CMDLOGBIN
#prev_host=$curr_host

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
	open -a /Applications/Docker.app ; pausing "30"
    is_running=`docker info|$GREP Images`
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
        is_running=`docker info|$GREP Images`
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> REMOVE iP ALIASES"
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

printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if last IP alias is configured on any NIC [${Yellow}$END_ALIAS${NC}]..."
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
#printf "${NC}\n"
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
		os_free_mem=`top -l 1 | head -n 10 | $GREP PhysMem | awk '{print $2}' | sed 's/G//g' `
	else
        	loadavg=`cat /proc/loadavg |awk '{print $1}'|sed 's/,//g'`
        	os_free_mem=`free -g|$GREP -i mem|awk '{print $2}' `
	fi

	load=${loadavg%.*}
	#load=10	#debug
	MAXLOADAVG=`echo $cores \* $LOADFACTOR | bc -l `
	c=`echo " $load > $MAXLOADAVG" | bc `;
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} OS:[$os] MAX ALLOWED LOAD:[$MAXLOADAVG] current load:[$loadavg] cores[$cores]${NC}\n" >&5
	if [  "$c" == "1" ]; then
		echo
		for c in $(seq 1 $t); do
			echo -ne "${LightRed}High load avg [$loadavg] Max allowed[$MAXLOADAVG] Pausing ${Yellow}$t${NC} seconds... ${Yellow}$c${NC}\033[0K\r"
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
condition=$(which bc 2>/dev/null | $GREP -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [bc]${NC}:"
	progress_bar_pkg_download "sudo apt-get install bc -y"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------
#----------
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking [wget] package:${NC} "
condition=$(which wget 2>/dev/null | $GREP -v "not found" | wc -l)
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
condition=$(which imgcat 2>/dev/null | $GREP -v "not found" | wc -l)
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
condition=$(which timeout 2>/dev/null | $GREP -v "not found" | wc -l)
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
condition=$(which dot 2>/dev/null | $GREP -v "not found" | wc -l)
if [ $condition -eq 0 ]; then
	printf "${BrownOrange}Installing [graphviz]${NC}:"
	progress_bar_pkg_download "sudo apt-get install graphviz -y"
else
	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
fi
#----------
#----------
#printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [tmux] package:${NC} "
#condition=$(which tmux 2>/dev/null | $GREP -v "not found" | wc -l)
#if [ $condition -eq 0 ]; then
#	printf "${BrownOrange}Installing [tmux]${NC}:"
#	progress_bar_pkg_download "sudo apt-get install tmux -y"
#else
#	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
#fi
#----------

return 0
}	#end check_for_ubuntu_pkgs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_for_MACOS_pkgs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

##make sure you use built-in grep in this function ####

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
printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking GNU grep package:${NC} "
cmd=$(brew ls grep --versions|cut -d" " -f2)    #use native OS grep on this one!
if [ -n "$cmd" ]; then
        printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
else
	printf "${BrownOrange}Installing [ggrep]${NC}:"
	brew tap homebrew/dupes > /dev/null 2>&1
	#progress_bar_pkg_download "brew install homebrew/dupes/grep"
	progress_bar_pkg_download "brew install grep"
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
#printf "${Yellow}   ${ARROW_EMOJI}${NC} Checking optional [tmux] package:${NC} "
#cmd=$(brew ls tmux --versions)
#if [ -n "$cmd" ]; then
#	printf "${Green}${CHECK_MARK_EMOJI} Installed${NC}\n"
#else
#	printf "${BrownOrange}Installing [tmux]${NC}:"
#	progress_bar_pkg_download "brew install tmux"
#fi
#----------


echo
return 0
}	#end check_for_MACOS_pkgs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
startup_checks() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

printf "${WhiteOnGray1}Splunk N' A Box (v${Yellow}$GIT_VER${WhiteOnGray1}): Starting validation checks...${NC}\n"

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
pid_list=`ps -efa | $GREP "$this_script_name" | $GREP "/bin/bash" |$GREP -v $$ |awk '{printf $2" " }'`
#echo "running:  ps -efa | grep splunknbox.sh | grep \"/bin/bash\" |grep -v \$\$ |awk '{printf \$2\" \" }"
if [ -n "$pid_list" ]; then
	printf "\n"
        printf "    ${Red}>>${NC} Detected running instance(s) of $this_script_name [$pid_list]${NC}\n"
        read -p "    >> This script doesn't support multiple instances. Kill them? [Y/n]? " answer
        if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                sudo kill -9 $pid_list
		#kill any stray docker pull requests
		kill $(ps -ax|$GREP "docker pull"|$GREP -v "grep"|awk '{print $1}') >/dev/null 2>&1
        fi
	printf "\n"
else
        printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------other scripts running?---------

#-----------docker daemon running check----
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if docker daemon is running "

is_running=`docker info|$GREP Images 2>/dev/null `
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
	os_used_mem=`free -g|$GREP -i mem|awk '{print $3}' `
        os_free_mem=`free -g|$GREP -i mem|awk '{print $4}' `
        os_total_mem=`free -g|$GREP -i mem|awk '{print $2}' `
        os_free_mem_perct=`echo "($os_free_mem * 100) / $os_total_mem"| bc`

elif [ "$os" == "Darwin" ]; then
        cores=`sysctl -n hw.ncpu`
        os_used_mem=`top -l 1 -s 0|$GREP PhysMem|tr -d '[[:punct:]]'|awk '{print $2}' `
	if ( compare "$os_used_mem" "M" ); then
		os_used_mem=`echo $os_used_mem | tr -d '[[:alpha:]]'`  #strip M
		os_used_mem=`printf "%0.1f\n" $(bc -q <<< scale=6\;$os_used_mem/1024)` #convert float from MB to GB
	else
		os_used_mem=`echo $os_used_mem | tr -d '[[:alpha:]]'`  #strip G
	fi
        os_wired_mem=`top -l 1 -s 0|$GREP PhysMem|tr -d '[[:punct:]]'|awk '{print $4}' `
	if ( compare "$os_wired_mem" "M" ); then
                os_wired_mem=`echo $os_wired_mem | tr -d '[[:alpha:]]'`  #strip M
		os_wired_mem=`printf "%0.1f\n" $(bc -q <<< scale=6\;$os_wired_mem/1024)` #convert float from MB to GB
        else
                os_wired_mem=`echo $os_wired_mem | tr -d '[[:alpha:]]'`  #strip G
        fi
        os_unused_mem=`top -l 1 -s 0|$GREP PhysMem|tr -d '[[:punct:]]'|awk '{print $6}' `
	if ( compare "$os_unused_mem" "M" ); then
                os_unused_mem=`echo $os_unused_mem | tr -d '[[:alpha:]]'`  #strip M
		os_unused_mem=`printf "%0.1f\n" $(bc -q <<< scale=6\;$os_unused_mem/1024)` #convert float from MB to GB
        else
                os_unused_mem=`echo $os_unused_mem | tr -d '[[:alpha:]]'`  #strip G
        fi
        #echo "MEM: used:[$os_used_mem] wired:[$os_wired_mem]  unused:[$os_unused_mem]"
		os_free_mem=$os_unused_mem
        #os_total_mem=`echo $os_used_mem + $os_wired_mem + $os_unused_mem | bc`
		os_total_mem=`hostinfo|$GREP "memory available"| awk '{print $4}'`
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
	printf "\t${BULB_EMOJI}${NC} Recommended %sGB+ of free memory for large builds\n" $LOW_MEM_THRESHOLD
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
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if Splunk image is available [${Yellow}$DEFAULT_SPLUNK_IMAGE${NC}]..."
image_ok=`docker images|$GREP "$DEFAULT_SPLUNK_IMAGE"`
if [ -z "$image_ok" ]; then
	printf "${Red}NOT FOUND!${NC}\n"
	read -p "    >> Download default splunk image [$DEFAULT_SPLUNK_IMAGE] [Y/n]? " answer
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
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if docker network is created [${Yellow}$SPLUNKNET${NC}]..."
net=`docker network ls | $GREP $SPLUNKNET `
if [ -z "$net" ]; then
	printf "${Green} Creating...${NC}\n"
        docker network create -o --iptables=true -o --ip-masq -o --ip-forward=true $SPLUNKNET
else
       printf "${Green}${OK_MARK_EMOJI} OK${NC}\n"
fi
#-----------splunk-net check---------------

#-----------license files/dir check--------
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if we have license files *.lic in [${Yellow}$SPLUNK_LIC_DIR${NC}]..."
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
printf "${Blue}   ${ARROW_EMOJI}${ARROW_EMOJI}${NC} Checking if non-docker splunkd process is running [${Yellow}$LOCAL_SPLUNKD${NC}]..."
PID=`ps aux | $GREP 'splunkd' | $GREP 'start' | head -1 | awk '{print $2}' `  	#works on OSX & Linux

if [ "$os" == "Darwin" ] && [ -n "$PID" ]; then
	splunk_is_running="$PID"
elif [ "$os" == "Linux" ] && [ -n "$PID" ]; then
	splunk_is_running=`cat /proc/$PID/cgroup|head -n 1|$GREP -v docker`	#works on Linux only
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
        DNSSERVER=`scutil --dns|$GREP nameserver|awk '{print $3}'|sort -u|tail -1`
	printf "[${Yellow}$DNSSERVER${NC}]...${Green}${OK_MARK_EMOJI} OK${NC}\n"
else
	printf "\n"
fi
if [ -z "$DNSSERVER" ]; then
	DNSSERVER="127.0.0.1";
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
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Set global vars based on OS type:
# ETH to use
# GREP command. Must install ggrep utility on OSX
# MOUNTPOINT   (OSX is strict about permissions)

uname=`uname -a | awk '{print $1}'`
if [ "$(uname)" == "Darwin" ]; then
    os="Darwin"
	START_ALIAS=$START_ALIAS_OSX
	END_ALIAS=$END_ALIAS_OSX
	ETH=$ETH_OSX
	GREP=$GREP_OSX		#for Darwin http://www.heystephenwood.com/2013/09/install-gnu-grep-on-mac-osx.html
	MOUNTPOINT="/Users/${USER}/$VOL_DIR"
	PROJ_DIR="/Users/${USER}"  #anything that needs to copied to container
	sys_ver=`system_profiler SPSoftwareDataType|grep  "System Version" |awk '{print $5}'`
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
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Need to detect git version stuff as early as possible but after ggrep is installed

#Lines below  must be broked with "\" .Otherwise git clean/smudge scripts will
#screw up things if the $ sign is not the last char
GIT_VER=`echo "__VERSION: 5.1-8 $" | \
		$GREP -Po "\d+.\d+-\d+"`
GIT_DATE=`echo "__DATE: Thu May 31,2018 - 03:03:25AM -0600 $" | \
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

#-----------------------------------------------------------------------------------------------------
timer() {
local start_time="$1"
local end_time=$(date +%s);
echo $(($end_time - $start_time)) | awk '{print int($1/60)":"int($1%60)}'
return
}	#end timer()
#-----------------------------------------------------------------------------------------------------
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

for l in $(seq 3 $loglevel); do
    (( "$l" <= "$maxloglevel" )) && eval exec "$l>&2"  #Don't change anything higher than the maximum loglevel allowed.
done

#From the loglevel level one higher than requested, through the maximum;
for l in $(seq $(( loglevel+1 )) $maxloglevel ); do
    (( "$l" > "2" )) && eval exec "$l>/dev/null" #Redirect these to bit bucket, provided that they don't match stdout and stderr.
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

string="$1" ; substring="$2"


    if test "${string#*$substring}" != "$string"
    then
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} strings matching${NC}\n"  >&6
        return 0    # TRUE! $substring is in $string
    else
	printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} strings NOT matching!${NC}\n"  >&6
        return 1    # NOT TRUE! $substring is not in $string
    fi
return 0
}	#end compare()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
pausing() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#use timer if passed in CLI other other use what passed to this function
if [ -n "$set_timer" ]; then
	timer="$set_timer"
else
	timer="$1"
fi
for c in $(seq 1 $timer); do
	echo -ne " ${LighBlue}${ARROW_EMOJI}${NC}Pausing $timer seconds... ${Yellow}$c\r"  >&3
	sleep 1
done
printf " ${LightBlue}${ARROW_EMOJI}${NC}Pausing $timer seconds... ${Green}Done!${NC}\n"  >&3

return 0
}	#end pausing()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_output() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function displays the output from CMD (docker command executed)
#$1  Actual message after executing docker command
#$2  The expected "good" message returned if docker command executed OK. Otherwise everything would be an error
#$3  The logging (I/O redirect) to display the message (good for verbosity settings)


outputmsg="$1"; OKmsg="$2"; logging="$3"
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
				read -p $'\033[0;31mHit <ENTER> to continue...\e[0m'
                #restart_splunkd "$host"
        fi
return 0
}	#end display_output()
#---------------------------------------------------------------------------------------------------------------

####### SPLUNKD ##########

#---------------------------------------------------------------------------------
is_splunkd_running() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

clear_from_if_screen_ended "$R_ROLL"
fullhostname="$1"
check_load

#-----check if splunkd is running--------
if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ); then
	pausing 30;
fi #demo/workshop containers takes little longer to start

#splunkstate=`docker exec -ti $fullhostname /opt/splunk/bin/splunk status| $GREP -i "not running" `
splunkstate=`docker exec -ti $fullhostname sh -c "ps xa|$GREP '[s]plunkd -p'" `
#echo "splunkstate[$splunkstate]"
echo -ne " ${LightBlue}${ARROW_EMOJI}${NC}Verifying splunkd is running...\r" >&3
if [ -n "$splunkstate" ]; then
        echo -ne  " ${LightBlue}${ARROW_EMOJI}${NC}Verifying splunkd is running...${Green}${OK_MARK_EMOJI} OK${NC}                           \n" >&3
else
        	echo -ne "${NC}	${LightBlue}${ARROW_EMOJI}${NC}Verifying splunkd is running..${Red}Not running! Attempt ${Yellow}$i${Red} to restart\r${NC}" >&3
        	sleep 30        #pause between attempts to restart
        	CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk start "
        	#echo "cmd[$CMD]"
        	OUT=`$CMD`; display_output "$OUT" "Splunk web interface is at" "4"
        	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
        	#logline "$CMD" "$fullhostname"
        	#pausing "30"
			splunkstate=`docker exec -ti $fullhostname sh -c "ps xa|$GREP '[s]plunkd -p'" `
			if [ -z "$splunkstat" ]; then
        		echo -ne  " ${LightBlue}${ARROW_EMOJI}${NC}Verifying splunkd is running...${Green}${OK_MARK_EMOJI} OK${NC}                           \n" >&3
				return

			fi
fi

#if [ -z "$splunkstate" ]; then
# printf "${Green}${OK_MARK_EMOJI} OK${NC}\n" >&3
 #       echo -ne  "	${Yellow}${ARROW_EMOJI}${NC}Verifying splunkd is running...${Green}${OK_MARK_EMOJI} OK${NC}                           \n" >&3
#else
 #       echo -ne  "	${Yellow}${ARROW_EMOJI}${NC}Verifying splunkd is running...${Red}NOT${OK_MARK_EMOJI} OK${NC}                          \n" >&3
#fi

return 0
}	#end is_splunkd_running()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
splunkd_status_all() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This functions displays splunkd status on all containers

for i in `docker ps --format "{{.Names}}"`; do
        printf "${Purple}$i${NC}: "
        docker exec -ti $i /opt/splunk/bin/splunk status| $GREP splunkd| awk '{ \
        if($3=="not")           {$3="\033[31m" $3 "\033[0m" }  \
        if($3=="running")       {$3="\033[32m" $3 "\033[0m" } ; \
        print $1,$2,$3,$4,$5 }'
		clear_from_if_screen_ended "$R_ROLL"
done
return 0
}	#end splunkd_status_all()
#---------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------
add_license_file() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function will just copy the license file. Later on if the container get configured
#as a license-slave; then this file become irrelevant
# $1=fullhostname
#see: https://docs.docker.com/engine/reference/commandline/cp/

clear_from_if_screen_ended "$R_ROLL"
check_load
CMD="docker cp $SPLUNK_LIC_DIR  $1:/opt/splunk/etc/licenses/enterprise"; OUT=`$CMD`
printf " ${LightBlue}${ARROW_EMOJI}${NC}Copying license file(s)..." >&3 ; display_output "$OUT" "" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$1"

if ( compare "$1" "LM" ); then
	printf " ${LightBlue}${ARROW_EMOJI}${NC}*LM* Forcing splunkd restart.Please wait " >&3
	docker exec -u splunk -ti $1  /opt/splunk/bin/splunk restart > /dev/null >&1
	printf "${Green} Done! ${NC}\n" >&3
fi
return 0
}	#end add_license_file()
#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------
reset_splunk_passwd() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
fullhostname="$1"

docker exec -u splunk -ti $fullhostname touch /opt/splunk/etc/.ui_login	#prevent first time changeme password screen
docker exec -u splunk -ti $fullhostname rm -fr /opt/splunk/etc/passwd	#remove any existing users (include admin)

#reset password to "$USERADMIN:$USERPASS"
CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk edit user admin -password $USERPASS -roles admin -auth admin:changeme"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
logline "$CMD" "$fullhostname"
printf "${Purple}$fullhostname${NC}: > $CMD\n"  >&4

if ( compare "$CMD" "failed" ); then
   echo " ${LightBlue}${ARROW_EMOJI}${NC}Trying default password "
   CMD="docker exec -u splunk -ti $fullhostname /opt/splunk/bin/splunk edit user admin -password changeme -roles admin -auth $USERADMIN:$USERPASS"
   printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4 ; OUT=`$CMD`
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> RESET SPLUNK INSTANCES PASSWORD MENU"
printf "\n"
display_all_containers

for host_name in `docker ps --format "{{.Names}}"`; do
        if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) || ( compare "$host_name" "3RDP" ) ; then
                true
        else
                printf "${Purple}$host_name${NC}: Admin password reset to [$USERPASS]\n"
                reset_splunk_passwd $host_name
        fi
		clear_from_if_screen_ended "$R_ROLL"
done
echo
return 0
}	#end reset_all_splunk_passwords()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
add_splunk_licenses() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
printf "${BoldWhiteOnBlue}ADD SPLUNK LICENSE MENU                                    ${NC}\n"
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> ADD SPLUNK LICENSE MENU"
printf "\n"
display_all_containers

for host_name in `docker ps --format "{{.Names}}"`; do
        if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) || ( compare "$host_name" "3RDP" ) ; then
                true
        else
		printf "${Purple}$host_name${NC}:"
		add_license_file $host_name
        fi
		clear_from_if_screen_ended "$R_ROLL"
done
return 0
}	#end add_splunk_licenses()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
restart_all_splunkd() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> RESTART SPLUNK INSTANCES MENU"
printf "\n"
display_all_containers

for host_name in `docker ps --format "{{.Names}}"`; do
        if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) || ( compare "$host_name" "3RDP" ) ; then
                true
        else
		printf "${Purple}$host_name${NC}:"
     		restart_splunkd "$host_name"
        fi
		clear_from_if_screen_ended "$R_ROLL"
done
return 0
}	#end restart_all_splunkd()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
restart_splunkd() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
fullhostname="$1"
#$2=b Execute in the background and don't wait to return.This will speed up everything but load the CPU


clear_from_if_screen_ended "$R_ROLL"

if [ "$2" == "b" ]; then
	printf " ${LightBlue}${ARROW_EMOJI}${NC}Restarting splunkd in the ${White}background${NC} " >&3
        CMD="docker exec -u splunk -d $fullhostname /opt/splunk/bin/splunk restart "
        OUT=`$CMD`; display_output "$OUT" "The Splunk web interface is at" "3"
   	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$fullhostname"
else
	printf " ${LightBlue}${ARROW_EMOJI}${NC}Restarting splunkd. Please wait! " >&3
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
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
# This function designate $hostname as license-slave using LM (License Manager)
#Always check if $lm exist before processing

clear_from_if_screen_ended "$R_ROLL"
check_load
lm="$1"; hostname="$2";
if [ -n "$lm" ]; then
	#echo "hostname[$hostname]  lm[$lm] _____________";exit
	lm_ip=`docker port  $lm| awk '{print $3}'| cut -d":" -f1|head -1`
  	if [ -n "$lm_ip" ]; then
        	CMD="docker exec -u splunk -ti $hostname /opt/splunk/bin/splunk edit licenser-localslave -master_uri https://$lm_ip:$MGMT_PORT -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
        	printf " ${LightBlue}${ARROW_EMOJI}${NC}Making [$hostname] license-slave using LM:[$lm] " >&3 ; display_output "$OUT" "has been edited" "3"
		printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$hostname"
        	fi
fi

return 0
} 	#end make_lic_slave()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_host_exist() {		 ####### NOT USED YET ########
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#$1=hostname (may include digits sequence)   $2=list_to_check_against
#Check if host exist in list; if not create it using basename only . The new host seq is returned by function


clear_from_if_screen_ended "$R_ROLL"
printf "${Purple}[$1] Host check >>> "
basename=$(printf '%s' "$1" | tr -d '0123456789')  #strip numbers
if [ -z "$2" ]; then
        printf "${LightPurple}Group is empty >>> creating host ${NC}\n";
        create_splunk_container "$basename" "1" "no"
else if ( compare "$2" "$1" ); then
                printf "${Purple}Found in group. No action. ${NC}\n";
                return 0
        else
                printf "${LightPurple}Not found in group >>> Using basename to create next in sequence ${NC}\n";
                create_splunk_container "$basename" "1" "no"
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> ADD OS UTILS MENU"
printf "\n"
printf "${BrownOrange}This option will add OS packages [vim net-tools telnet dnsutils] to ALL running demo containers only...\n"
printf "${BrownOrange}Might be useful if you will be doing a lot of manual splunk configuration, however, it will increase container's size! ${NC}\n"
printf "\n"
read -p "Are you sure you want to proceed? [Y/n]? " answer
if [ "$answer" == "y" ] || [ "$answer" == "y" ] || [ "$answer" == "" ]; then
	true  #do nothing
else
	return 0
fi

count=`docker ps -a|egrep -i "DEMO|WORKSHOP"| $GREP -v "IMAGE"| wc -l`
if [ $count == 0 ]; then
        printf "\nNo running demo containers found!\n"; printf "\n"
        return 0
fi;
for id in $(docker ps -a|egrep -i "DEMO|WORKSHOP"|$GREP -v "PORTS"|awk '{print $1}'); do
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
mc_list=`docker ps -a --filter name="MC|mc" --format "{{.Names}}"|sort`
demo_list=`docker ps -a --filter name="DEMO|demo|WORKSHOP|workshop" --format "{{.Names}}"|sort`
rdparty_list=`docker ps -a --filter name="3RDP|3rdp" --format "{{.Names}}"|sort`

screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> GROUP CONTAINERS BY ROLE MENU"
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
printf "${Green}MCs${NC}: ";		printf "%-5s " $mc_list;echo
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
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates custom login screen with some useful data (hostname, IP, cluster label)

vip="$1";  fullhostname="$2"

check_load
#set -x
#----------- password stuff ----------
if ( compare "$fullhostname" "DEMO-ES" ) || ( compare "$fullhostname" "DEMO-ITSI" ) || ( compare "$fullhostname" "DEMO-VMWARE" ) ; then
	true #dont change pass for some demos.
	USERPASS="changeme"
        printf "${Green}OK${NC}\n"
else
	if [ "$splunkversion" -ge "710" ]; then
	txt="\n #-----Modified by splunk-n-box ----\n [general]\n allowRemoteLogin=always \n"
	printf "%b" "$txt" > $TMP_DIR/server.conf.tmp
	CMD="docker cp $TMP_DIR/server.conf.tmp $fullhostname:/tmp/server.conf"; OUT=`$CMD`
	CMD=`docker exec -u splunk -ti $fullhostname  bash -c "cat /tmp/server.conf >> /opt/splunk/etc/system/local/server.conf" `; OUT=`$CMD`

	#printf " ${LightBlue}${ARROW_EMOJI}${NC}Setting allowRemoteLogin=always in server.conf..." >&3
#	docker exec -i $fullhostname /bin/bash -c "sed -i 's/requireSetPassword/always/g' /opt/splunk/etc/system/default/server.conf"
	#logline "$CMD" "$fullhostname"
	fi

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
LINE6="<CENTER><font color=\"#867979\">Created using Splunk N' A Box v$GIT_VER<BR/> Docker image [$SPLUNK_IMAGE]</font></CENTER>"

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

USERPASS="$USERPASS" #rest in case we just processed ES or VMWARE DEMOS
#set +x
return 0
}	#end custom_login_screen()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
assign_server_role() {		 ####### NOT USED YET ########
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#EXAMPLE:
#mhassan:~> docker exec -u splunk -ti SITE01-MC01 cat /opt/splunk/etc/apps/splunk_management_console/lookups/assets.csv
#peerURI,serverName,host,machine,"search_group","_mkv_child","_timediff","__mv_peerURI","__mv_serverName","__mv_host","__mv_machine","__mv_search_group","__mv__mkv_child","__mv__timediff"
#"10.0.0.101:$MGMT_PORT","SITE01-LM01","SITE01-LM01","SITE01-LM01","mc_group_license_master",0,,,,,,,,
#"10.0.0.102:$MGMT_PORT","SITE01-CM01","SITE01-CM01","SITE01-CM01","mc_group_cluster_master",0,,,,,,,,
#"10.0.0.102:$MGMT_PORT","SITE01-CM01","SITE01-CM01","SITE01-CM01","mc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.107:$MGMT_PORT","SITE01-DEP01","SITE01-DEP01","SITE01-DEP01","mc_group_deployment_server",0,,,,,,,,
#"10.0.0.108:$MGMT_PORT","SITE01-SH01","SITE01-SH01","SITE01-SH01","mc_group_search_head",0,,,,,,,,
#"10.0.0.108:$MGMT_PORT","SITE01-SH01","SITE01-SH01","SITE01-SH01","mc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.108:$MGMT_PORT","SITE01-SH01","SITE01-SH01","SITE01-SH01","mc_searchheadclustergroup_LABEL1",2,,,,,,,,
#"10.0.0.109:$MGMT_PORT","SITE01-SH02","SITE01-SH02","SITE01-SH02","mc_group_search_head",0,,,,,,,,
#"10.0.0.109:$MGMT_PORT","SITE01-SH02","SITE01-SH02","SITE01-SH02","mc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.109:$MGMT_PORT","SITE01-SH02","SITE01-SH02","SITE01-SH02","mc_searchheadclustergroup_LABEL1",2,,,,,,,,
#"10.0.0.110:$MGMT_PORT","SITE01-SH03","SITE01-SH03","SITE01-SH03","mc_group_search_head",0,,,,,,,,
#"10.0.0.110:$MGMT_PORT","SITE01-SH03","SITE01-SH03","SITE01-SH03","mc_indexerclustergroup_LABEL1",1,,,,,,,,
#"10.0.0.110:$MGMT_PORT","SITE01-SH03","SITE01-SH03","SITE01-SH03","mc_searchheadclustergroup_LABEL1",2,,,,,,,,
#localhost,"SITE01-MC01","SITE01-MC01","SITE01-MC01","mc_group_search_head",0,,,,,,,,

#docker exec -u splunk -ti SITE01-DEP01 cat /opt/splunk/etc/apps/splunk_management_console/lookups/assets.csv
#peerURI,serverName,host,machine,"search_group","__mv_peerURI","__mv_serverName","__mv_host","__mv_machine","__mv_search_group"
#localhost,"SITE01-DEP01","SITE01-DEP01","SITE01-DEP01","mc_group_license_master",,,,,
#localhost,"SITE01-DEP01","SITE01-DEP01","SITE01-DEP01","mc_group_search_head",,,,,

name="$1"; role="$2"
echo peerURI,serverName,host,machine,"search_group","_mkv_child","_timediff","__mv_peerURI","__mv_serverName","__mv_host","__mv_machine","__mv_search_group","__mv__mkv_child","__mv__timediff" > assets.csv.tmp
echo "localhost,"$name","$name","$name","$role,,,,,"" > assets.csv.tmp

# $MOUNTPOINT/$name/etc/apps/splunk_management_console/lookups/assets.csv
#Roles:
#mc_group_indexer
#mc_group_license_master
#mc_group_search_head
#mc_group_kv_store
#mc_group_license_master
return 0
}	#end assign_server_role()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
make_mc_search_peer() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#Always check if $mc exist before processing

mc="$1"; host="$2"
clear_from_if_screen_ended "$R_ROLL"

#adding search peer in MC
if [ -n "$mc" ]; then
	bind_ip_host=`docker inspect --format '{{ .HostConfig }}' $host| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	CMD="docker exec -u splunk -ti $mc /opt/splunk/bin/splunk add search-server -host $bind_ip_host:$MGMT_PORT -auth $USERADMIN:$USERPASS -remoteUsername $USERADMIN -remotePassword $USERPASS"
    OUT=`$CMD`
    OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
    printf " ${LightBlue}${ARROW_EMOJI}${NC}Adding [$host] to MC:[$mc] " >&3 ; display_output "$OUT" "Peer added" "3"
    printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$mc"
fi

return 0
} 	#end make_mc_search_peer()
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
printf " ${Yellow}${ARROW_EMOJI}${NC}Configuring demo to be viewed on http://$fullhostname:$SPLUNKWEB_PORT_EXT ${Green} Done!${NC}\n" >&3

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

basename="$1"		#input
count="$2"		#input
#vip			#output global
#fullhostname	#output global

#---- calculate sequence numbers -----------[in:basename out: startx, endx]
#get last seq used by last host created
last_host_num=`docker ps -a --format "{{.Names}}"|$GREP "^$basename"|head -1| $GREP -P '\d+(?!.*\d)' -o`;
if [ -z "$last_host_num" ]; then    					#no previous hosts with this name exists
        printf "${DarkGray}[$basename] New basename. ${NC}" >&5
		starting=1
        ending=$count
		last_host_num=0
else
       	starting=`expr $last_host_num + 1`
       	ending=`expr $starting + $count - 1`
       	printf "${DarkGray}Last hostname created:${NC}[${Green}$basename${NC}${Yellow}$last_host_num${NC}] " >&5
fi
#fix single digit issue if < 2-digits
if [ "$starting" -lt "10" ]; then  startx="0$starting"; else  startx="$starting";  fi
if [ "$ending" -lt "10" ]; then endx="0$ending"; else endx=$ending; fi

printf "${DarkGray}Next sequence:${NC} [${Green}$basename${Yellow}$startx${NC} --> ${Green}$basename${Yellow}$endx${NC}]\n"  >&5
#---- end calculate sequence numbers -----------

#---- calculate VIP numbers -----------
base_ip=`echo $START_ALIAS | cut -d"." -f1-3 `;  #base_ip=$base_ip"."

#Find last container created IP (not hostname/sitename dependent).
#Returns value only if last container has bind IP assigned (which excludes containers not built by this script)
containers_count=`docker ps -aq | wc -l|awk '{print $1}' `
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} last ip used:[$last_ip_used]\n" >&6
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} containers_count:[$containers_count]\n" >&6

#get last octet4 used ----
if [ "$containers_count" == 0 ]; then       #nothing created yet!
        last_used_octet4=`echo $START_ALIAS | cut -d"." -f4 `
        last_ip_used="$base_ip.$start_octet4"
        printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} NO HOSTS EXIST! [containers_count:$containers_count] [last ip used:$last_ip_used][last_octet4:$last_used_octet4]\n" >&6

elif [ "$containers_count" -gt "0" ]; then
	#last_ip_used=`docker inspect --format '{{ .HostConfig }}' $(docker ps -aql)|$GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	#last_ip_used=`docker inspect --format='{{(index (index .NetworkSettings.Ports "8000/tcp") 0).HostIp}}' $(docker ps -aq) 2>/dev/null | sort -u |tail -1`
	last_ip_used=`docker inspect --format '{{ .HostConfig }}' $(docker ps -aq)| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+ 8000'|cut -d" " -f 1|sort -un|tail -1`

	if [ -n "$last_ip_used" ]; then
        	last_used_octet4=`echo $last_ip_used |cut -d"." -f4`
	else
		printf "${NC}\n"
		printf "Use option ${Yellow}1)${NC} SHOW all containers... ${Red}above to see the offending container(s). Exiting...${NC}\n"
	#	exit
	fi
        printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}SOME HOSTS EXIST. [containers_count:$containers_count][last ip used:$last_ip_used][last_octet4:$last_used_octet4]\n" >&6
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
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}fulhostname:[$fullhostname] vip:[$vip] basename:[$basename] count[$count] ${NC}\n" >&6


#---- build fullhostname (Base+seq & VIP) -----------

return 0
}	#calc_next_seq_fullhostname_ip()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
create_splunk_container() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates generic splunk containers. Role is assigned later
#inputs:
#	 $1:basehostname: (ex IDX, SH,HF) just the base (no numbers)
#	 $2:hostcount:     how many containers to create from this host type (ie name)
#outputs:
#	$gLIST:  global var compare the list of hostname just got created
#
basename="$1"				#basehostname ex IDX
hostcount="$2"				#how many hosts to create
local show_progress="$3"	#if yes; update progress (use when hostcount > 1)
local step_pos="$4"			#where in steps section to update progresss bar
local clear_pos="$5"		#starting of rolling(clearing) postion [default R_ROLL]

local TIME_START=$(date +%s);
#lic_master="$3"; cluster_label="$4"
count=0;starting=0; ending=0;  octet4=0
gLIST=""   #build global list of hosts created by this session. Used somewhere else

printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}  basename[$basename]  hostcount[$hostcount] ${NC}\n" >&6

#---If not passed; prompt user to get basename and count ----
if [ -z "$basename" ]; then
        read -p ">>>> Enter BASE HOSTNAME (default: $BASEHOSTNAME)?: " basename
else
        basename=$basename
fi
if [ -z "$basename" ]; then
        basename=$BASEHOSTNAME
        last_host_name=""
        #printf "First time to use this host_base_name ${Green}[$basename]${NC}\n"
fi
#always convert to upper case before creating
basename=`echo $basename| tr '[a-z]' '[A-Z]'`

if [ -z "$hostcount" ]; then
		printf "${LightRed}Something went wrong! You should not be here...${NC}\n"
        read -p ">>>> How many hosts to create (default 1)? " count
		if [ -z "$count" ]; then count=1;  fi  #user accepted default 1
else
        count="$2"
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
#Loop thru count of how containers to create
pass_list=$(seq 1 $count |tr -d '\r' | tr  '\n' ' ')
for (( a = 1; a <= count; a++ ))  ; do
	if [ -z "$clear_pos" ]; then
		clear_from_if_screen_ended "$R_ROLL"		#clearing anything below
	else
		clear_from_if_screen_ended "$clear_pos"		#clearing anything below
	fi
	calc_next_seq_fullhostname_ip "$basename" "$count"	#function will return global $vip
	construct_splunk_container $vip $fullhostname $lic_master $cluster_label $bindip_monitor
	gLIST="$gLIST""$fullhostname "		#append last host create to the global LIST

	local TIME_END=$(date +%s);
	timer=`echo $((TIME_END - TIME_START)) | awk '{print int($1/60)":"int($1%60)}'`
	#update_progress_bar () here only if we are building cluster
	if [ "$show_progress" == "yes" ]; then
		update_progress_bar "$step_pos" "$C_PROGRESS" "$a" "$pass_list" "$timer"
		#echo "----now ----";exit
	fi
	docker_status
done


gLIST=`echo $gLIST |sed 's/;$//'`	#GLOBAL! remove last space (causing host to look like "SH "
#echo "gLIST[$gLIST]"; exit

return $host_num
}	#end of create_splunk_container()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
#build_dot_file() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
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

vip="$1";  fullhostname="$2"; lic_master="$3"; cluster_label="$4";
START=$(date +%s);
fullhostname=`echo $fullhostname| tr -d '[[:space:]]'`	#trim white space if they exist
#echo "vip[$vip]"
#echo "fullhostname[$fullhostname]"
#echo "lic_master[$lic_master]"
#echo "cluster_label[$cluster_label]"

check_load		#throttle back if high load

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

#Force changme passwd at startup with version 7.1+. (moved to entrypoint.sh)
splunkversion=`echo "$DEFAULT_SPLUNK_IMAGE" | sed 's/[^0-9]*//g'`
#if [ "$splunkversion" -ge "710" ]; then
#	START_ARGS="--accept-license\x20--seed-passwd\x20changeme"
#else
#	START_ARGS="--accept-license"
#fi

CMD="docker run -d \
--network=$SPLUNKNET --hostname=$fullhostname --name=$fullhostname --dns=$DNSSERVER \
-p $vip:$SPLUNKWEB_PORT:$SPLUNKWEB_PORT_EXT -p $vip:$MGMT_PORT:$MGMT_PORT -p $vip:$SSHD_PORT:$SSHD_PORT \
-p $vip:$HEC_PORT:$HEC_PORT \
-p $vip:$RECV_PORT:$RECV_PORT -p $vip:$REPL_PORT:$REPL_PORT -p $vip:$APP_SERVER_PORT:$APP_SERVER_PORT \
-p $vip:$APP_KEY_VALUE_PORT:$APP_KEY_VALUE_PORT \
-e SPLUNK_START_ARGS=--accept-license \
-e SPLUNK_ENABLE_LISTEN=$RECV_PORT -e SPLUNK_SERVER_NAME=$fullhostname \
-e SPLUNK_SERVER_IP=$vip -e SPLUNK_USER=splunk  $full_image_name"

#-v $MOUNTPOINT/$fullhostname/etc:/opt/splunk/etc -v  $MOUNTPOINT/$fullhostname/var:/opt/splunk/var \

if [ "$fullhostname" == "$MASTER_CONTAINER" ]; then
	printf "[${LightGreen}$fullhostname${NC}:${Green}$vip${NC}] ${Yellow}Creating docker monitor container.This is created once in the entire system! ${NC} "
else
	printf "[${LightGreen}$fullhostname${NC}:${Green}$vip${NC}] ${LightBlue}Creating generic splunk container ${NC} "
fi

OUT=`$CMD`
display_output "$OUT" "" "2"
#CMD=`echo $CMD | sed 's/\t//g' `;
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4

#get aggressive with rolling screen checks. V4 tend to be chatty
clear_from_if_screen_ended "$R_ROLL"		#clearing anything below
logline "$CMD" "$fullhostname"

if [ "$os" == "Darwin" ]; then
	pausing "30"
else
	pausing "15"
fi

#-----check if container is running--------
printf " ${LightBlue}${ARROW_EMOJI}${NC}Verifying container is running..." >&3
if ! ( is_container_running "$fullhostname" ); then
	printf "${Red}NOT RUNNING!${NC}\n" >&3
else
	printf "${Green}${OK_MARK_EMOJI} OK${NC}\n" >&3
fi

#-----check if splunkd is running--------
is_splunkd_running "$fullhostname"

#custom_login_screen() will not change pass for DEMO-ES* or DEMO-VMWARE*. Set allowRemoteLogin for 7.1+
printf " ${LightBlue}${ARROW_EMOJI}${NC}Splunk initialization..." >&3
custom_login_screen "$vip" "$fullhostname" "$splunkversion"

#Do not add license file to DEMO containers. They are shipped with their own
if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) ; then
	true
else
	add_license_file $fullhostname
fi


#Misc OS stuff
if [ -f "$PWD/containers.bashrc" ]; then
	printf " ${LightBlue}${ARROW_EMOJI}${NC}Copying $PWD/containers.bashrc to $fullhostname:/root/.bashrc\n" >&4
       	CMD=`docker cp $PWD/containers.bashrc $fullhostname:/root/.bashrc`
fi
if [ -f "$PWD/containers.vimrc" ]; then
	printf " ${LightBlue}${ARROW_EMOJI}${NC}Copying $PWD/containers.vimrc to $fullhostname:/root/.vimrc\n" >&4
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
#tput cup 0 45; imgcat ~/splunk-n-box/tmp/run.png
docker_status
return 0
}	#end construct_splunk_container()
#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_demo_container_from_list() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear



#-----------show images details
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> MANAGE CONTAINERS -> CREATE & DOWNLOAD DEMO CONTAINERS MENU"
printf "\n"
printf "Demo images available from $SPLUNK_DOCKER_HUB:\n"
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}" " -- SELECTED AVIALABLE IMAGES FROM [$SPLUNK_DOCKER_HUB] -- "
print_step_bar_from "$R_STEP2" "${BoldWhiteOnBlue}" "        Image%-30s Created%-7s Size%-12s Author%-21s${NC}"
clear_page_starting_from "$R_STEP3"

#---Scan demos images from $REPO_DEMO_IMAGES ---------
counter=1
#count=`docker images --format "{{.ID}}" | wc -l`
for image_name in $REPO_DEMO_IMAGES; do
    printf "${Purple}%-2s${NC}) ${Purple}%-40s${NC}" "$counter" "$image_name"
	image_name="$SPLUNK_DOCKER_HUB/sales-engineering/$image_name"
#	echo "cached[$cached]\n"
	created=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $7,$8}'`
    if [ -n "$created" ]; then
        	author=`docker inspect $image_name |$GREP -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
            printf "%-12s %-7s %-10s ${NC}\n" "$created" "$size" "$author"
    else
            printf "${DarkGray}NOT CACHED! ${NC}\n"
    fi
    let counter++
	clear_from_if_screen_ended "$R_STEP3" "p"
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
       		printf "${NC}Using ${Purple}[$id:$image_name]:${NC}"; display_system_banner "short"
        	create_splunk_container "$image_name" "$number" "no"
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
                #printf "${NC}Using ${Purple}[$i${NC}]"; display_system_banner "short"
                create_splunk_container "$i" "1" "no"
				pausing "30"
            done
	fi
fi
return 0
}	#end create_demo_container_from_list()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
construct_3rdp_container_from_image() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates single 3rd party container using $vip and $hostname
image_name="$1"      #example  johndoe/mysql

START=$(date +%s);

check_load              #throttle back if high load
mkdir -m 777 -p $MOUNTPOINT/$fullhostname

#extract basename from full image name
basename=`echo $image_name | sed 's/^.*\///g' | tr '[a-z]' '[A-Z]' `
basename="3RDP-$basename"

cached=`docker images|$GREP $image_name`
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
printf " ${LightBlue}${ARROW_EMOJI}${NC}Verifying container is running..." >&3
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> MANAGE CONTAINERS -> CREATE 3RD PARTY CONTAINERS MENU"
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
        cached=`docker images|$GREP $i| awk '{print $4,$5,$6" "$7,$8}'`
        if [ -n "$cached" ]; then
                author=`docker inspect $i|$GREP -i author|cut -d":" -f1-3|sed 's/,//g'`
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
                cached=`docker images|$GREP $image_name`
                if [ -z "$cached" ]; then
                printf "${NC}Using ${Purple}[$id:$image_name]:${NC}\n"
                        progress_bar_image_download "$image_name"
                fi
                #echo "$id : ${list[$id - 1]}"
                printf "${NC}Using ${Purple}[$id:$image_name]:${NC}"; display_system_banner "short"
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
                        printf "${NC}Using ${Purple}[$image_name${NC}]"; display_system_banner "short"
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

#### nCurses stuff ####

#---------------------------------------------------------------------------------------------------------------
update_progress_bar() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function will update the progress bars section. No clearing
#of lines before or after will happen (expect on the bars sections)

r_pos="$1"; c_pos="$2"; local item="$3"; local pass="$4"; local timer="$5"

#---------------------------
#convert to seq of numbers in case $pass is a string.This will handle something like item="one" pass="one two three"
ctr=0;str=""
#echo "pass[$pass]  item=[$item]  ctr[$ctr]"
pos=0
for i in $pass; do
        let ctr++
        str="$str"" $ctr"
        if [ "$i" == "$item" ]; then pos=$ctr; fi
done
pass=$str
item=$pos
#---------------------------

tput sc	#save cursor

if [ -n "$timer" ]; then
	timerstr="[$timer]"
else
	timerstr=""
fi

local todo_str="              "
if [ "$r_pos" -eq "$R_BUILD_SITE" ]; then
	local done_str="###############"
	p_color="${R_BUILD_COLOR}"
else
	local done_str="|||||||||||||||"
	p_color="${R_PROGRESS_COLOR}"
fi
#build todo_strne w/colors
#for i in {57..31}; do
#		let c=$c+1
#		#done_str="\033[48;5;${i}m\033[1;34m▓\033[0m"$done_str
#		done_str="\033[48;5;${i}m  \033[0m"$done_str
#done
#get $pass string size
max=0;#todo_len=$max; done_len=0
for i in $pass ; do
	let max=$max+1
done

c=0
tput cup $r_pos $c_pos; echo  "                                    "  #clear to end of line (tput el doesnt work!)
tput cup $r_pos $c_pos

#will show in the very first call when there is no element match in $pass
percent=0
echo -ne "\033[0m[                ] %$percent \033[0m\r"
#echo "r_pos:$r_pos  c_pos:$c_pos  item:[$item]  pass:[$pass]"	#debug

index=0
for i in $pass; do
    let index++
    done_len=$((index * ${#done_str} / max))
    let todo_len=${#done_str}-$done_len
    percent=$((index * 100 / max))
	if [ "$i" == "$item" ]; then
		#color="\033[1;${c}m"
		tput cup $r_pos $c_pos
		echo -ne "[${p_color}${done_str:0:$done_len}$item${BoldWhiteOnDarkRed}${todo_str:0:$todo_len}${NC}]${LightBlue} %$percent${NC} $timerstr\r"
    	#printf "[\033[48;5;2m${done_str:0:$done_len}\033[48;5;1m${todo_str:0:$todo_len}\033[0m]\033[1;34m %%$percent\033[0m"
   		# printf "[${done_str:0:$done_len} ${todo_str:0:$todo_len}] ${percent}% \n"
		#let c=$c-1	#gradually increase the color value
	fi;
done
tput rc	#restore cursor. Got back where we started

}	#end update_progress_bar()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
screen_header() {
#_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

tput sc
color="$1"
str="$2"
ROWS=$(tput lines)
COLUMNS=$(tput cols)
size=$((${#str} - 9 ))
len=$(($COLUMNS - $size))
pad=`printf '\x20%.0s' $(seq 1 $len)`
tput cup $R_HEADER 0; printf "$color ${str}$pad${NC}\n"
tput cup $R_BANNER 0; display_system_banner
tput rc
docker_status
return
}	#end screen_header()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
screen_footer() {
#_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

tput sc
#screen_footer "$Containers" "$Running" "$Paused" "$Stopped" "$Images" "${loadavg}" "$freedisk"
Containers="$1"; Running="$2"; Paused="$3"; Stopped="$4"; Images="$5"; c_loadavg="$6"; disk="$7"
if	[ "$(uname)" == "Linux" ]; then
	speak_str=""

elif [ "$set_macspeak" == "true" ]; then
	speak="$BELL_EMOJI"
	speak_str="  SPEAK[${BELL_EMOJI}${NC}${FOOTER_COLOR1}]             "

else
	speak_str="  SPEAK[${NO_BELL_EMOJI}${NC}${FOOTER_COLOR1}]          "
fi

str="\
${FOOTER_COLOR1} Docker:[Containers: ${FOOTER_COLOR2}$Containers${NC}\
${FOOTER_COLOR1} Running: ${FOOTER_COLOR2}$Running${NC}\
${FOOTER_COLOR1} Paused: ${FOOTER_COLOR2}$Paused${NC}\
${FOOTER_COLOR1} Stopped: ${FOOTER_COLOR2}$Stopped${NC}\
${FOOTER_COLOR1} Images: ${FOOTER_COLOR2}$Images${FOOTER_COLOR1}]${NC}\
${FOOTER_COLOR1} Load:[$c_loadavg${NC}${FOOTER_COLOR1}]\
${FOOTER_COLOR1} FreeDisk:[${FOOTER_COLOR2}$disk${NC}${FOOTER_COLOR1}]\
${FOOTER_COLOR1} $speak_str"

#rows and cols are also detected in redraw function with a trap
ROWS=$(tput lines)
COLUMNS=$(tput cols)

#https://unix.stackexchange.com/questions/140251/strip-color-on-os-x-with-bsd-sed-or-any-other-tool
size=$(echo $str| sed $'s,\\\\033\\[[0-9;]*[a-zA-Z],,g'|wc -c| tr -d '[:space:]')
#echo "[$size]";exit

#dont pad if screen width less that str size
if [ "$size" -gt "$COLUMNS" ]; then
	len=1
else
	len=$(($COLUMNS - $size))
fi
pad=`printf '\x20%.0s' $(seq 1 $len)`
#tput cup $ROWS 0;printf "[$COLUMNS-$size=$len]$str$pad${NC}"
tput cup $ROWS 0;printf "$str$pad${NC}"
tput rc

return
}	#end screen_footer()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
docker_status() {
#_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#\033[37;48;5;88m  \033[37;48;5;88m

tput sc		#save cursor

timer="$1"		#time took to execute the task
Containers=`docker info| $GREP -i Containers| awk '{print $2}'`
Running=`docker info| $GREP -i Running| awk '{print $2}'`
Paused=`docker info| $GREP -i Paused| awk '{print $2}'`
Stopped=`docker info| $GREP -i Stopped| awk '{print $2}'`
Images=`docker info| $GREP -i Images| awk '{print $2}'`
dockerinfo="Containers: $Containers Running:$Running Paused:$Paused Stopped:$Stopped Images:$Images"
#screen_footer "${dockerinfo}"
if [ "$os" == "Darwin" ]; then
        loadavg=`sysctl -n vm.loadavg | awk '{print $2}'`
        cores=`sysctl -n hw.ncpu`
		freedisk=`df -kh /Users|tail -1 |awk '{print  $4}' |sed 's/i/B/g'` #docker image under /User
elif [ "$os" == "Linux" ]; then
        loadavg=`cat /proc/loadavg |awk '{print $1}'|sed 's/,//g'`
        cores=`$GREP -c ^processor /proc/cpuinfo`
		freedisk=`df -kh /var|tail -1 |awk '{print $4}'|sed 's/G/GB/g'` #docker images under /var
fi

load=`echo "$loadavg/1" | bc `   #convert float to int
#load=13
#c=`echo " $load > $MAXLOADAVG" | bc `;

if [[ "$load" -ge "$cores" ]]; then
	color_loadavg="${FOOTER_COLOR4}$loadavg"
elif [[ "$load" -ge "$cores/2" ]]; then
	color_loadavg="${FOOTER_COLOR3}$loadavg"
else
	color_loadavg="${FOOTER_COLOR2}$loadavg"
fi

#Containers="$1"; Running="$2"; Paused="$3"; Stopped="$4"; Images="$5"; loadavg="$6"; timer="$7"
#screen_footer "$Containers" "$Running" "$Paused" "$Stopped" "$Images" "${loadavg}" "$timer"
screen_footer "$Containers" "$Running" "$Paused" "$Stopped" "$Images" "$color_loadavg" "$freedisk"
tput rc		#restore cursor
return
}	#end docker_status()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
clear_from_if_screen_ended() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#This function will check current cursor poistion. Clear screen to specific
#starting row $1 if screen hieght (ROWS-3) is reached

if [ "$loglevel" -gt "4" ]; then	#dont clear if DEBUG turned on
	return
fi

pos="$1"	#row to start clearing from (if screen limit reached)
prompt="$2"	#if set & screen limit reached; prompt user "to continue"

# Get current settings.
if ! termios="$(stty -g 2>/dev/null)" ; then
    echo "Not running in a terminal." >&2
    exit 1
fi

# Restore terminal settings when the script exits.
trap "stty '$termios'" EXIT

# Disable ICANON ECHO. Should probably also disable CREAD.
stty -icanon -echo

# Request cursor coordinates
printf '\033[6n'

# Read response from standard input; note, it ends at R, not at newline
read -d "R" rowscols

# Clean up the rowscols (from \033[rows;cols -- the R at end was eaten)
rowscols="${rowscols//[^0-9;]/}"
rowscols=("${rowscols/ /;/ }")
curr_row=""; curr_col=""
curr_pos=(${rowscols[0]})
curr_row=`echo $curr_pos|cut -d ";" -f1 `
curr_col=`echo $curr_pos|cut -d ";" -f2 `
#x=$(($pos + 1))
ROWS=$(tput lines)
height_limit=$(( $ROWS - $R_SCR_END_FACTOR ))
#printf "${Yellow}[R:$curr_row L:$height_limit]${NC}"  #DEBUG
if [[ $curr_row -ge $height_limit ]]; then
#	printf "${LightRed}---end of screen reached ---(from:$pos)${NC}"; sleep 2	#DEBUG
	if [ -n "$prompt" ]; then
		read -p "<ENTER> to show more.." answer
	fi
	clear_page_starting_from "$pos" "0"
	gSplit_col=30
fi

# Reset original terminal settings.
stty "$termios"
docker_status
sleep 2		#allow for extra time to view the data before clearing
}	#end clear_from_if_screen_ended()
#----------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------
clear_page_starting_from() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

#This function will clear screen starting at specific row. IT DOES NOT
# CHECK IF END-OF-SCREEN is reached
#
if [ "$loglevel" -gt "4" ]; then	#dont clear if DEBUG turned on
	return
fi

#clear screen staring at (x,y)
x="$1"; y="$2"
ROWS=$(tput lines)
height_limit=$(( $ROWS - 2 ))
tput cup $x $y
#printf "Clearing screen starting at ($x,$y)\n";sleep 2		#DEBUG
#xterm in OSX does not honor ed and el (bug)
printf '\E[K'	#tput ed  (clear to end of display)
printf '\E[J'   #tput el  (clear to end of line)

return
}	#end clear_page_starting_from()
#------------------------------------------------------------------------------------------------------
#------------------------------------------------------------------------------------------------------
print_step_bar_from() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
if [ "$loglevel" -gt "4" ]; then	#dont clear if DEBUG turned on
	return
fi
tput sc
#display msg from row=pos and clear everything after it
pos="$1"		#row where should start displaying msg
color="$2"		#color code for msg
text="$3"		#msg to display
progress_item="$4"
progress_list="$5"
tput cup $pos 0
size=$((${#text}))
size=$(($size + 4))	#take out ESC code for color & emoji
#len=$(($size - 10))	#take out color ESC codes
#echo "[size:$size vs len:$len vs MAXLEN:$MAXLEN]"
#dont pad if strlen > maxlen
if [ "$size" -gt "$MAXLEN" ]; then
	len=1
else
	len=$(($MAXLEN - $size))
fi
pad=`printf '\x20%.0s' $(seq 1 $len)`
#printf "[$MAXLEN-$size=$len]${color}$text$pad${NC}"	#DEBUG
printf "$color${text}$pad${NC}"
x=$(($pos + 1))
#tput smcup	#save screen
#clear_page_starting_from "$x" "0"
#tput rmcup	#restore screen
docker_status
tput rc

return
}	#end print_step_bar_from()
#------------------------------------------------------------------------------------------------------

#### DISPLAY MENU OPTIONS #####

#---------------------------------------------------------------------------------------------------------------
display_main_menu_options() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function displays user options for the main menu
clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU"

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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> SPLUNK MENU"
printf "\n\n\n"
printf "${BoldWhiteOnRed}Manage Images:${NC}\n"
printf "${Red}I${NC}) ${Red}I${NC}mages details ${DarkGray}[custom view]${NC}\n"
printf "${Red}R${NC}) ${Red}R${NC}EMOVE image(s) to recover disk-space (will extend build times) ${DarkGray}[docker rmi --force \$(docker images)]${NC}\n"
printf "${Red}F${NC}) DE${Red}F${NC}AULT Splunk image ${DarkGray}[currently: $DEFAULT_SPLUNK_IMAGE]${NC}\n"
printf "\n"
printf "${BoldWhiteOnYellow}Manage Containers:${NC}\n"
printf "${Yellow}C${NC}) ${Yellow}C${NC}REATE generic Splunk container(s) ${DarkGray}[docker run ...]${NC}\n"
printf "${Yellow}D${NC}) ${Yellow}D${NC}ELETE container(s) & Volumes(s)${DarkGray} [docker rm -vf \$(docker ps -aq)]${NC}\n"
printf "${Yellow}S${NC}) ${Yellow}S${NC}TART container(s) ${DarkGray}[docker start \$(docker ps -a --format \"{{.Names}}\")]${NC}\n"
printf "${Yellow}T${NC}) S${Yellow}T${NC}OP container(s) ${DarkGray}[docker stop \$(docker ps -aq)]${NC}\n"
printf "${Yellow}L${NC}) ${Yellow}L${NC}IST all containers ${DarkGray}[custom view]${NC} \n"
printf "${Yellow}H${NC}) ${Yellow}H${NC}OSTS grouped by role ${DarkGray}[works only if you followed the host naming rules]${NC}\n"
printf "\n"
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> SYSTEM MENU"
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> DEMOs MENU"
printf "\n\n"
echo
printf "${BoldWhiteOnRed}Manage Demo Images:${NC}\n"
printf "${Red}I${NC}) ${Red}I${NC}mages details ${DarkGray}[downloaded demos only]${NC}\n"
printf "${Red}O${NC}) Download demo images from $SPLUNK_DOCKER_HUB ${DarkGray}[cache images] ${NC} \n"
printf "${Red}R${NC}) ${Red}R${NC}EMOVE demo image(s)\n"
printf "\n"
printf "${BoldWhiteOnYellow}Manage Demo Containers:${NC}\n"
printf "${Yellow}C${NC}) ${Yellow}C${NC}REATE Splunk demo container from available list${NC}\n"
printf "${Yellow}D${NC}) ${Yellow}D${NC}ELETE demo container(s)${NC}\n"
printf "${Yellow}S${NC}) ${Yellow}S${NC}TART demo container(s) ${NC}\n"
printf "${Yellow}T${NC}) S${Yellow}T${NC}OP demo container(s) ${NC}\n"
printf "${Yellow}L${NC}) ${Yellow}L${NC}IST demo container(s) ${NC}\n"
printf "${Yellow}A${NC}) ${Yellow}A${NC}DD common utils to demo container(s) ${DarkGray}[Useful if you need command line access]${NC}\n"
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> 3RD PARTY MENU"
printf "\n\n"
echo
printf "${BoldWhiteOnRed}Manage 3rd Party Images:${NC}\n"
printf "${Red}O${NC}) D${Red}O${NC}WNLOAD 3rd party images [use this option to cache demo images] ${NC} \n"
printf "${Red}W${NC}) SHO${Red}W${NC} all downloaded 3rd party images ${NC} \n"
printf "${Red}R${NC}) ${Red}R${NC}EMOVE 3rd party image(s)\n"
echo
printf "${BoldWhiteOnYellow}Manage 3rd Party containers:${NC}\n"
printf "${Yellow}C${NC}) ${Yellow}C${NC}REATE 3rd party container from available list${NC}\n"
printf "${Yellow}D${NC}) ${Yellow}D${NC}ELETE 3rd party container(s)${NC}\n"
printf "${Yellow}S${NC}) ${Yellow}S${NC}TART 3rd party container(s) ${NC}\n"
printf "${Yellow}T${NC}) S${Yellow}T${NC}OP 3rd party container(s) ${NC}\n"
printf "${Yellow}L${NC}) ${Yellow}L${NC}IST 3rd party container(s) ${NC}\n"
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> CLUSTERING MENU"
printf "\n\n"
echo
printf "${BoldWhiteOnBlue}AUTOMATIC CLUSTER BUILDS (components: R$R_FACTOR/S$S_FACTOR 1-CM 1-DEP 1-MC 1-LM $STD_SHC_COUNT-SHC $STD_IDXC_COUNT-IDXC): ${NC}\n"
printf "${LightBlue}1${NC}) Create Stand-alone Index Cluster (IDXC)${NC}\n"
printf "${LightBlue}2${NC}) Create Stand-alone Search Head Cluster (SHC)${NC}\n"
printf "${LightBlue}3${NC}) Build Single-site Cluster [$DEF_SINGLE_SITE]${NC}\n"
printf "${LightBlue}4${NC}) Build Multi-site Cluster [$DEF_MULTI_SITES]${NC} \n";
echo

printf "${BoldWhiteOnYellow}MANUAL CLUSTER BUILDS (specify base host-names and counts): ${NC}\n"
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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> LUNCH & LEARN MENU"
printf "\n\n"
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
                i|I ) list_all_images;;
                f|F ) change_default_splunk_image;;

                #CONTAINERS ------------
                c|C) create_containers  ;;
                d|D ) delete_containers;;
                v|V ) delete_all_volumes;;
                l|L ) list_all_containers ;;
                s|S ) start_containers;;
                t|T ) stop_containers;;
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
                s|S ) start_containers    "DEMO|WORKSHOP";;
                t|T ) stop_containers     "DEMO|WORKSHOP";;
				a|A ) add_os_utils_to_demos ;;

                o|O) download_demo_image;;
                i|I) list_all_images "DEMO|WORKSHOP";;
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
                s|S ) start_containers    "3RDP";;
                t|T ) stop_containers     "3RDP";;
                a|A ) add_os_utils_to_3rdparty ;;

                o|O) download_3rdparty_image;;
                w|W) list_all_images "3RDP";;
                r|R ) remove_images  "3RDP";;

                b|B ) return 0;;

        esac  #end case ---------------------------
        read -p $'\033[1;32mHit <ENTER> to continue...\e[0m'
done
return 0
}	#end 3rdparty_menu_inputs()
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

				##Automatic builds
				1 ) create_standalone_idxc "$IDX_BASE:$STD_IDXC_COUNT MC:1 CM:1 LM:1 LABEL:$DEFAULT_IDXC_LABEL RF:$R_FACTOR SF:$S_FACTOR"
					;;
				2 ) create_standalone_shc "$SH_BASE:$STD_SHC_COUNT $DEP_BASE:1 MC:1 LM:1 LABEL:$DEFAULT_SHC_LABEL"
			#create_standalone_shc "STL$SH_BASE:$STD_SHC_COUNT STL$DEP_BASE:1 STLMC:1 STLLM:1 LABEL:STL$DEFAULT_SHC_LABEL"
					;;
                3 ) build_singlesite_cluster "$IDX_BASE:$STD_IDXC_COUNT $SH_BASE:$STD_SHC_COUNT $DEP_BASE:1 MC:1 CM:1 LM:1 LABEL:$DEFAULT_IDXC_LABEL SNAME:$DEF_SINGLE_SITE RF:$R_FACTOR SF:$S_FACTOR"
   					;;
				4)	build_multisite_cluster "$DEP_BASE:1 MC:1 CM:1 LM:1 LABEL:$DEFAULT_IDXC_LABEL" "LOC:STL SITE:site1 IDX:$STD_IDXC_COUNT SH:$STD_SHC_COUNT DEP:1 AFF:site1 LABEL:$DEFAULT_IDXC_LABEL, LOC:ATL SITE:site2 IDX:$STD_IDXC_COUNT SH:$STD_SHC_COUNT DEP:1 AFF:site2" "RF:origin:2,total:3 SF:origin:1,total:2"
#cluster_conf2="LOC:DC01 SITE:site1 IDX:4 SH:0 DEP:1 AFF:site1,LOC:DC02 SITE:site2 IDX:2 SH:1 AFF:site0"
					;;

				##Manual builds
                5 ) get_standalone_idxc_inputs
				 	create_standalone_idxc "$IDX_BASE:$IDXcount MC:1 CM:1 LM:1 LABEL:$label RF:$gRF SF:$gSF"
					;;
                6 ) get_standalone_shc_inputs
					create_standalone_shc "$SH_BASE:$SHcount $DEP_BASE:1 MC:1 LM:1 LABEL:$label"
					;;
                7 ) get_singlesite_inputs
                	build_singlesite_cluster "$IDX_BASE:$IDXcount $SH_BASE:$SHcount $DEP_BASE:1 MC:1 CM:1 LM:1 LABEL:$label SNAME:$SITElocation RF:$gRF SF:$gSF"
		    		;;
                8 ) get_multisite_inputs
                	build_multisite_cluster "$DEP_BASE:1 MC:1 CM:1 LM:1" "$gClusterConf" "$gClusterRepl"

					;;
	        	b|B) return 0;

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
installtype="$1"
type=""
clear
printf "${BoldWhiteOnYellow}CONFIGURE LUNCH & LEARN CONTAINERS APPS/DATASETS MENU    ${NC}\n"
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
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

host_names="$1"	#list of hostnames to configure
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
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

host_names="$1"	#list of hostnames to configure
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
return
}	#end install_ll_datasets()
#---------------------------------------------------------------------------------------------------------------

#### CLUSTERS ######

#------------------------------------------------------------------------------------------------------
color_selected() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

local site_loc="$1"; local loc_list_clean="$2"

site_loc_clean=`echo $site_loc| sed 's/_//g'` #Remove "_" if found. Used for title display only
#result=$(echo  $LOCATIONSlist_clean| sed "s/$SITElocation_clean/\\\033[1;1;5;43m$SITElocation_clean\\\033[1;1;5;45m/g")
result=$(echo  $loc_list_clean| sed "s/$site_loc_clean/\\${BoldWhiteOnYellow}$site_loc_clean\\${R_BUILD_COLOR}/g")
echo  "$result"
#printf "%b" "$result"

return
}	#end color_selected()
#------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
get_standalone_idxc_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

###create_standalone_idxc "$IDX_BASE:$IDXcount MC:1 CM:1 LM:1 LABEL:$label"

clear_page_starting_from "$R_ROLL"
read -p "Enter IDX cluster label (default $DEFAULT_IDXC_LABEL)? " label ;
label=`echo $label| tr '[a-z]' '[A-Z]'`; if [ -z "$label" ]; then label="$DEFAULT_IDXC_LABEL"; fi

read -p "How many indexers in this cluster (default $STD_IDXC_COUNT)? " IDXcount;
if [ -z "$IDXcount" ]; then IDXcount="$STD_IDXC_COUNT"; fi

read -p $'What is the \033[1;32mReplication Factor\033[0m'$' for this cluster (default '"$R_FACTOR"$')? ' gRF
if [ -z "$gRF" ]; then gRF="$R_FACTOR"; fi

read -p $'What is the \033[1;32mSearch Factor\033[0m'$' for this cluster (default '"$S_FACTOR"$')? ' gSF
if [ -z "$gSF" ]; then gSF="$S_FACTOR"; fi

while [[ "$gRF" -lt "$gSF" ]]
	do
	read -p "S-Factor cannnot be less than R-Factor, are you sure want to continue [y/N]? " answer
    if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
    	break
    else
		read -p $'What is the \033[1;32mSearch Factor\033[0m'$' for this cluster (default '"$S_FACTOR"$')? ' gSF
		if [ -z "$gSF" ]; then gSF="$S_FACTOR"; fi
    fi
done

return
}	#get_standalone_idxc_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
get_standalone_shc_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

clear_page_starting_from "$R_ROLL"
read -p "Enter SH cluster label (default $DEFAULT_SHC_LABEL)? " label ;
label=`echo $label| tr '[a-z]' '[A-Z]'`; if [ -z "$label" ]; then label="$DEFAULT_SHC_LABEL"; fi
#read -p "Enter indexer host basename (default $IDX_BASE)? " IDXname ;
#IDXname=`echo $IDXname| tr '[a-z]' '[A-Z]'` ; if [ -z "$IDXname" ]; then IDXname="$IDX_BASE"; fi
read -p "How many search heads in this cluster (default $STD_SHC_COUNT)? " SHcount
if [ -z "$SHcount" ]; then
	SHcount="$STD_SHC_COUNT"
fi
while [ "$SHcount" -lt "$STD_SHC_COUNT" ]
	do
	read -p "SHC requires minimum of 3 hosts, are you sure want to continue [y/N]? " answer
	if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		break
	else
		read -p "How many search heads in this cluster (default $STD_SHC_COUNT)? " SHcount
	fi
	done

return
}	#get_standalone_shc_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
get_singlesite_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

clear_page_starting_from "$R_ROLL"

read -p "Enter cluster label (default $DEFAULT_SHC_LABEL)? " label
label=`echo $label| tr '[a-z]' '[A-Z]'`; if [ -z "$label" ]; then label="$DEFAULT_SHC_LABEL"; fi

read -p "Enter site name (default $DEF_SINGLE_SITE)? " SITElocation
SITElocation=`echo $SITElocation| tr '[a-z]' '[A-Z]'`; if [ -z "$SITElocation" ]; then SITElocation="$DEF_SINGLE_SITE"; fi

read -p "Prefix hostnames with site name [Y/n]? " answer
if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then SITElocation="$SITElocation""_" ; fi

read -p "How many indexers in this cluster (default $STD_IDXC_COUNT)? " IDXcount;
if [ -z "$IDXcount" ]; then IDXcount="$STD_IDXC_COUNT"; fi

read -p "How many search heads in this cluster (default $STD_SHC_COUNT) ? " SHcount
if [ -z "$SHcount" ]; then SHcount="$STD_SHC_COUNT"; fi
while [[ "$SHcount" -lt "$STD_SHC_COUNT" ]]
	do
	read -p "SHC requires minimum of 3 hosts, are you sure want to continue [y/N]? " answer
	if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		break
	else
		read -p "How many search heads in this cluster (default $STD_SHC_COUNT) )? " SHcount
		if [ -z "$SHcount" ]; then SHcount="$STD_SHC_COUNT"; fi
	fi
done

read -p $'What is the \033[1;32mReplication Factor\033[0m'$' for this cluster (default '"$R_FACTOR"$')? ' gRF
if [ -z "$gRF" ]; then gRF="$R_FACTOR"; fi

read -p $'What is the \033[1;32mSearch Factor\033[0m'$' for this cluster (default '"$S_FACTOR"$')? ' gSF
if [ -z "$gSF" ]; then gSF="$S_FACTOR"; fi

while [[ "$gRF" -lt "$gSF" ]]
	do
	read -p "S-Factor cannnot be less than R-Factor, are you sure want to continue [y/N]? " answer
    if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
    	break
    else
		read -p $'What is the \033[1;32mSearch Factor\033[0m'$' for this cluster (default '"$S_FACTOR"$')? ' gSF
		if [ -z "$gSF" ]; then gSF="$S_FACTOR"; fi
    fi
done

return
}	#get_singlesite_inputs()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
get_multisite_inputs() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

###build_singlesite_cluster "$IDX_BASE:$idxc_count $SH_BASE:$shc_count $DEP_BASE:1 MC:1 CM:1 LM:1 LABEL:$DEFAULT_IDXC_LABEL SNAME:$SITElocation"
clear_page_starting_from "$R_ROLL"

clear
printf "Note:You must configure the site_replication_factor attribute correctly. Otherwise, the master will not start.\n"
printf "Syntax:\t\t${Green}origin:${Yellow}<n>${NC}, [${Green}site1:${Yellow}<n>${NC},] [${Green}site2:${Yellow}<n>${NC},] ..., ${Green}total:${Yellow}<n>${NC}\n"
printf "where:\n"
printf "  ${Green}${Yellow}<n>${NC}\t\tPositive integer indicating the number of copies of a bucket.${NC}\n"
printf "  ${Green}origin:${Yellow}<n>${NC}\tMinimum number of copies of a bucket that will be held on the site originating data.${NC}\n"
printf "  ${Green}site1:${Yellow}<n>${NC}, ${Green}site2:${Yellow}<n>${NC}, ..., \tMinimum number of copies that will be held at each specified site.${NC}\n"
printf "  ${Green}total:${Yellow}<n>${NC}\tTotal number of copies of each bucket, across all sites in the cluster.${NC}\n"

echo
#make sure to remove spaces in R/S strings. Regex will fail later on
printf "${Purple}Cluster Master Configurations: ${NC}\n"
read -p $'Enter \033[1;34msite_replication_factor\033[0m string. Default ['"$DEF_SITE_REP_FACT]: " site_rf
if [ -z "$site_rf" ]; then site_rf="$DEF_SITE_REP_FACT"; fi
site_rf=`echo $site_rf| tr -d '[[:space:]]'`

read -p $'Enter \033[1;34msite_search_factor\033[0m string. Default ['"$DEF_SITE_SEARCH_FACT]: " site_sf
if [ -z "$site_sf" ]; then site_sf="$DEF_SITE_SEARCH_FACT"; fi
site_sf=`echo $site_sf| tr -d '[[:space:]]'`

read -p $'Enter \033[1;34msites locations\033[0m (available_sites string). Default ['"$DEF_MULTI_SITES]: " availabel_sites
if [ -z "$availabel_sites" ]; then availabel_sites="$DEF_MULTI_SITES"; fi

read -p $'Enter optional \033[1;34mcluster label\033[0m. Default ['"$LABEL]? " cluster_label
if [ -z "$cluster_label" ]; then cluster_label="$LABEL"; fi

echo
c=1
for i in ${availabel_sites} ; do
    printf "${Purple}Site$c [Location: $i]: ${NC}\n"

	#----------------
	read -p $'site\033[1;33m'"$c"$'\033[0m-IDXC: How many \033[1;34mindexers\033[0m in this location. Default ['"$STD_IDXC_COUNT]? "   idxcount
	if [ -z "$idxcount" ]; then idxcount="$STD_IDXC_COUNT"; fi
	#----------------

	#----------------
	read -p $'site\033[1;33m'"$c"$'\033[0m-SHC: Build SHC for this location [Y/n]? '  answer
   	if [ "$answer" == "N" ] || [ "$answer" == "n" ]; then
		shc_pref="no"
	else
		shc_pref="yes"
	fi
	#----------------

	#----------------
	if [ "$shc_pref" == "yes" ]; then
		read -p $'site\033[1;33m'"$c"$'\033[0m-SHC: How many \033[1;34msearch heads\033[0m in this location. Default ['"$STD_SHC_COUNT]? "   shcount
		if [ -z "$shcount" ]; then shcount="$STD_SHC_COUNT"; fi
		dep_count="1"

		#.................
		read -p $'site\033[1;33m'"$c"$'\033[0m-SHC: Enable \033[1;34msearch affinity\033[0m in this location [y/N]? '   answer
   		if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
			affinity="yes"
		else
			affinity="no"
		fi
		#.................
		#.................
		if [ "$affinity" == "no" ]; then	#answer is No
			affinity="site$c"
			printf "${Cyan}This SHC will search ${NC}site${Yellow}$c${Cyan} only${NC}\n"
		else
			affinity="site0"
			printf "${Cyan}This SHC will search All sites (affinity=site0)${NC}\n"
		fi
		#.................
	else #/$shc_pref="no"/
		shcount="0"; affinity="0"; dep_count="0"
		printf "${BrownOrange}This location will NOT have SHC${NC}\n"

	fi 	#/$shc_pref=n/
	#----------------

	#must have comma (separator) at the end
	gClusterConf="$gClusterConf""SITE:site$c LOC:$i IDX:$idxcount SH:$shcount DEP:$dep_count AFF:$affinity LABEL:$cluster_label,"
	let c++
	echo
done
gClusterRepl="RF:$site_rf SF:$site_sf"
#echo "[$gClusterConf] [$gClusterRepl]";exit
#gClusterConf="SITE:site1 LOC:DC01 IDX:2 SH:2 AFF:site1"
return
}	#get_multisite_inputs()
#---------------------------------------------------------------------------------------------------------------

#-----------------------------------------------------------------------------------------------------
config_sh_for_singlesite() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#STEP#4
members_list="$1"; cm="$2"; mc="$3"; lm="$4"; step_pos="$5"
local start_time=$(date +%s);

clear_page_starting_from "$R_ROLL"

for sh in $members_list ; do
	#$members_list  $i  $bind_ip_sh $bin_ip_dep $cm  $cm_ip $mc $lm $server_list
	check_load	#throttle during SHC build

	#-------member config---
 	printf "[${Purple}$sh${NC}]${LightBlue} Making cluster member...${NC}\n"
    bind_ip_sh=`docker inspect --format '{{ .HostConfig }}' $sh| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	CMD="docker exec -u splunk -ti $sh /opt/splunk/bin/splunk init shcluster-config -auth $USERADMIN:$USERPASS -mgmt_uri https://$bind_ip_sh:$MGMT_PORT -replication_port $REPL_PORT -replication_factor $R_FACTOR -register_replication_address $bind_ip_sh -conf_deploy_fetch_url https://$bind_ip_dep:$MGMT_PORT -secret $MYSECRET -shcluster_label $label"
	OUT=`$CMD`
	OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
	printf "${Yellow}${ARROW_EMOJI}${NC}Initializing shcluster-config " >&3 ;display_output "$OUT" "clustering has been initialized" "3"
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$sh"
	#-------member config---

	#-------auto discovery---
	if [ -n "$cm" ]; then
		#another method of getting bind IP (showing published ports:IPs).Container must be RUNNING!
		cm_ip=`docker port  $cm| awk '{print $3}'| cut -d":" -f1|head -1`
    	CMD="docker exec -u splunk  -ti $sh /opt/splunk/bin/splunk edit cluster-config -mode searchhead -master_uri https://$cm_ip:$MGMT_PORT -secret $MYSECRET -auth $USERADMIN:$USERPASS"
		OUT=`$CMD`
		printf "${Yellow}${ARROW_EMOJI}${NC}Integrating with Cluster Master [$cm] for idx auto discovery " >&3 ; display_output "$OUT" "property has been edited" "3"
		printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
		logline "$CMD" "$sh"
    fi
	#-------auto discovery---

	make_lic_slave "$lm" "$sh"
    make_mc_search_peer "$mc" "$sh"
	restart_splunkd "$sh"
	update_progress_bar "$step_pos" "$C_PROGRESS" "$sh" "$members_list"	"$(timer "$start_time")"

	#assign_server_role "$i" "mc_group_search_head"
	#gserver_list="$gserver_list""https://$bind_ip_sh:$MGMT_PORT,"   #used by STEP#3 gserverlist:Global
done

server_list=`echo ${server_list%?}`  # remove last comma in string
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} server_list:[$gserver_list]________${NC}\n" >&6
return
}	#end config_sh_for_singlesite()
#-----------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
config_sh_for_multisite() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
sh="$1";  SITElocation="$2"; local site="$3" ; m_cm="$4" ; step_pos="$5"; mc="$6"; lm="$7"
local start_time=$(date +%s);

#clear_page_starting_from "$R_ROLL"

printf "[${Purple}$sh${NC}]${Cyan} Configure Search Head for multi-site ${NC}\n"

bind_ip_sh=`docker inspect --format '{{ .HostConfig }}' $sh| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
bind_ip_cm=`docker inspect --format '{{ .HostConfig }}' $m_cm| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`

#-------member config---
CMD="docker exec -u splunk -ti $sh /opt/splunk/bin/splunk init shcluster-config -auth $USERADMIN:$USERPASS -mgmt_uri https://$bind_ip_sh:$MGMT_PORT -replication_port $REPL_PORT -replication_factor $R_FACTOR -register_replication_address $bind_ip_sh -conf_deploy_fetch_url https://$bind_ip_dep:$MGMT_PORT -secret $MYSECRET -shcluster_label $label"

#CMD="docker exec -u splunk -ti $sh /opt/splunk/bin/splunk init shcluster-config -mgmt_uri https://$m_cm_ip:$MGMT_PORT -replication_port $REPL_PORT -register_replication_address $bind_ip_sh -secret $MYSECRET -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$sh"
printf "${Yellow}${ARROW_EMOJI}${NC}Initializing shcluster-config " >&3 ;display_output "$OUT" "clustering has been initialized" "3"
#-------member config---

#splunk edit cluster-config -mode searchhead -master_uri https://10.0.x.3:8089 -site site2 -secret idxcluster

#-------auto discovery---
CMD="docker exec -u splunk -ti $sh /opt/splunk/bin/splunk edit cluster-config -mode searchhead -site $site -secret $MYSECRET -register_replication_address $bind_ip_sh -master_uri https://$bind_ip_cm:$MGMT_PORT -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$sh"
printf "${Yellow}${ARROW_EMOJI}${NC}Integrating with Cluster Master (for idx auto discovery) [$m_cm] " >&3 ; display_output "$OUT" "property has been edited" "3"
display_output "$OUT" "property has been edited" "3"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$sh"
#-------auto discovery---

make_lic_slave "$lm" "$sh"; make_mc_search_peer "$mc" "$sh"

restart_splunkd "$sh"

update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1" "$(timer "$start_time")"
return
}	#end config_sh_for_multisite()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
config_idx_for_singlesite() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#STEP#4
members_list="$1"; label="$2"; lm="$3"; cm="$4"; step_pos="$5"; mc="$6"
local start_time=$(date +%s);
clear_page_starting_from "$R_ROLL"

for member in $members_list ; do
	check_load	#throttle during IDXC build
	printf "[${Purple}$member${NC}]${LightBlue} Making search peer... ${NC}\n"
	bind_ip_cm=`docker inspect --format '{{ .HostConfig }}' $cm| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
    bind_ip_idx=`docker inspect --format '{{ .HostConfig }}' $member| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	#-------member config----
    CMD="docker exec -u splunk -ti $member /opt/splunk/bin/splunk edit cluster-config -mode slave -master_uri https://$bind_ip_cm:$MGMT_PORT -replication_port $REPL_PORT -register_replication_address $bind_ip_idx -cluster_label $label -secret $MYSECRET -auth $USERADMIN:$USERPASS "
	OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
	printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
	logline "$CMD" "$member"
	printf " ${Yellow}${ARROW_EMOJI}${NC}Make a cluster member " >&3 ; display_output "$OUT" "property has been edited" "3"
	#-------

	#We dont need to add IDXCs to MC, just add their CM (which is already done)

	make_lic_slave "$lm" "$member"
	make_mc_search_peer "$mc" "$member"
	restart_splunkd "$member" "b"

	update_progress_bar "$step_pos" "$C_PROGRESS" "$member" "$members_list" "$(timer "$start_time")"

	#assign_server_role "$member" "mc_group_indexer"
done

return
}	#end config_idx_for_singlesite()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
pos_in_string() {
target="$1"		#workd we're looking for
source="$2"		#string we'r searching

#find position in string
#https://superuser.com/questions/434507/how-to-find-the-index-of-a-word-in-a-string-in-bash
words_before=( ${source%$target*} )     # truncate string, make array
pos=`expr ${#words_before[*]} + 1`             # count words in array
words_count=`echo $source|wc -w`
seq_list=$(seq 1 $words_count)
echo $pos

return
}	#end pos_in_string()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
config_idx_for_multisite() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
idx="$1";  SITElocation="$2"; local site="$3" ; m_cm_ip="$4" ; step_pos="$5"; mc="$6"; lm="$7"

local start_time=$(date +%s);
clear_from_if_screen_ended "$R_ROLL"

#printf "${Yellow} idx[$idx] SITElocation[$SITElocation] site[$site] m_cm_ip[$m_cm_ip] step_pos[$step_pos]";exit		#debug
bind_ip_idx=`docker inspect --format '{{ .HostConfig }}' $idx| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
#from singlesite build
#CMD="docker exec -u splunk -ti $member /opt/splunk/bin/splunk edit cluster-config -mode slave -master_uri https://$bind_ip_cm:$MGMT_PORT -replication_port $REPL_PORT -register_replication_address $bind_ip_idx -cluster_label $label -secret $MYSECRET -auth $USERADMIN:$USERPASS "



printf "[${Purple}$idx${NC}]${Cyan} Configure Indexer for multi-site ${NC}"
#splunk edit cluster-config -mode slave -site site1 -master_uri https://10.160.31.200:8089 -replication_port 9887
CMD="docker exec -u splunk -ti $idx /opt/splunk/bin/splunk edit cluster-config  -mode slave -site $site -master_uri https://$m_cm_ip:$MGMT_PORT -replication_port $REPL_PORT -register_replication_address $bind_ip_idx -secret $MYSECRET -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up

clear_from_if_screen_ended "$R_ROLL"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$idx"
display_output "$OUT" "property has been edited" "3"
make_lic_slave "$lm" "$idx"; make_mc_search_peer "$mc" "$idx"

restart_splunkd "$idx" "b"
update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1" "$(timer "$start_time")"

return
}	#end config_idx_for_multisite()
#---------------------------------------------------------------------------------------------------------------


#------------------------------------------------------------------------------------------------------
configure_deployer() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#STEP#3
dep="$1"; label="$2"; step_pos="$3"
local start_time=$(date +%s);
#clear_page_starting_from "$R_ROLL"
clear_from_if_screen_ended "$R_ROLL"

bind_ip_dep=`docker inspect --format '{{ .HostConfig }}' $dep| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
txt="\n #-----Modified by splunk-n-box ----\n [shclustering]\n pass4SymmKey = $MYSECRET \n shcluster_label = $label\n"
#printf "%b" "$txt" >> $MOUNTPOINT/$dep/etc/system/local/server.conf	#cheesy fix!
printf "%b" "$txt" > $TMP_DIR/server.conf.tmp

CMD="docker cp $TMP_DIR/server.conf.tmp $dep:/tmp/server.conf"; OUT=`$CMD`
CMD=`docker exec -u splunk -ti $dep  bash -c "cat /tmp/server.conf >> /opt/splunk/etc/system/local/server.conf" `; #OUT=`$CMD`

#~/sh3/bin/splunk edit shcluster-config -conf_deploy_fetch_url https://10.0.x.3:8189

printf " ${Yellow}${ARROW_EMOJI}${NC}Adding [shclustering] stanza to server.conf!" >&3 ; display_output "$OUT" "" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1 2"	"$(timer "$start_time")"
logline "$CMD" "$dep"
restart_splunkd "$dep"
update_progress_bar "$step_pos" "$C_PROGRESS" "2" "1 2"	"$(timer "$start_time")"
return
}	#end configure_deployer()
#------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------
configure_captain() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#STEP#5
local members_list="$1"; step_pos="$2"

local start_time=$(date +%s);
#clear_page_starting_from "$R_ROLL"
clear_from_if_screen_ended "$R_ROLL"

len=`echo $members_list|wc -w`		#ex: [LON HKG STL]
captain=`echo $members_list| cut -d" " -f$len`
printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple} members_list:[$members_list] captain[$captain]${NC}\n" >&6
server_list=""
for member in $members_list; do
    bind_ip_sh=`docker inspect --format '{{ .HostConfig }}' $member| $GREP -o '[0-9]\+[.][0-9]\+[.][0-9]\+[.][0-9]\+'| head -1`
	server_list="$server_list""https://$bind_ip_sh:$MGMT_PORT,"
done
server_list=`echo ${server_list%?}`  # remove last comma in string
#echo "server_list-[$server_list]  members_list[$members_list]"	#debug

printf "[${Purple}$captain${NC}]${LightBlue} Configuring as Captain (last SH created)...${NC}\n"
#restart_splunkd "$captain"  # captain may not be ready yet, so force restart again
update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1 2"	"$(timer "$start_time")"

#splunk bootstrap shcluster-captain -servers_list "<URI>:<management_port>,<URI>:<management_port>,..." -auth <username>:<password>

CMD="docker exec -u splunk -ti $captain /opt/splunk/bin/splunk bootstrap shcluster-captain -servers_list $server_list -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "${Yellow}${ARROW_EMOJI}${NC}Captain bootstrapping (may take time) " >&3
display_output "$OUT" "Successfully"  "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$captain"
update_progress_bar "$step_pos" "$C_PROGRESS" "2" "1 2"	"$(timer "$start_time")"
return
}	#end configure_captain()
#-----------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
enable_cm_maintenance_mode() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
m_cm="$1"

CMD="docker exec -u splunk -ti $m_cm /opt/splunk/bin/splunk enable maintenance-mode --answer-yes -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$m_cm"
printf "${Yellow}${ARROW_EMOJI}${NC}Enabling maintenance-mode [$m_cm] " >&3 ; display_output "$OUT" "aintenance mode set" "3"
#update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1" "$(timer "$start_time")"
return
}	#end enable_cm_maintenance_mode()
#---------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------
disable_cm_maintenance_mode() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
m_cm="$1"

printf "[${Purple}$m_cm${NC}]${Cyan} Disabling maintenance-mode... ${NC}\n"
CMD="docker exec -u splunk -ti $m_cm /opt/splunk/bin/splunk disable maintenance-mode -auth $USERADMIN:$USERPASS"
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$m_cm"
printf "${Yellow}${ARROW_EMOJI}${NC}Disabling maintenance-mode..." >&3 ; display_output "$OUT" "No longer"  "3"
#restart_splunkd "$i"
return

}	#end disable_cm_maintenance_mode()
#----------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
config_cm_for_singlesite() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#STEP#3
cm="$1"; label="$2"; step_pos="$3"; rf="$4"; sf="$5"
local start_time=$(date +%s);
#clear_page_starting_from "$R_ROLL"
clear_from_if_screen_ended "$R_ROLL"

#-------CM config---
CMD="docker exec -u splunk -ti $cm /opt/splunk/bin/splunk edit cluster-config  -mode master -replication_factor $rf -search_factor $sf -secret $MYSECRET -cluster_label $label -auth $USERADMIN:$USERPASS "
OUT=`$CMD`; OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `   # clean it up
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
printf " ${Yellow}${ARROW_EMOJI}${NC}Configuring CM [RF:$rf SF:$sf] and cluster label[$label] " >&3 ; display_output "$OUT" "property has been edited" "3"
update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1 2" "$(timer "$start_time")"
clear_from_if_screen_ended "$R_ROLL"

#-------
restart_splunkd "$cm"
update_progress_bar "$step_pos" "$C_PROGRESS" "2" "1 2" "$(timer "$start_time")"
#assign_server_role "$i" ""
return
}	#end config_cm_for_singlesite()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
config_cm_for_multisite() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
m_cm="$1"; local sites_list="$2"; step_pos="$3"; site_rp="$4"; site_sf="$5"
local start_time=$(date +%s);
#clear_page_starting_from "$R_ROLL"
clear_from_if_screen_ended "$R_ROLL"

sites_list=`echo "$sites_list" | sed 's/ /,/g'`		#add commas to string as expected by cluster-config command
m_cm_ip=`docker port $m_cm| awk '{print $3}'| cut -d":" -f1|head -1 `

#splunk edit cluster-config -mode master -multisite true -available_sites site1,site2 -site site1 -site_replication_factor origin:2,total:3 -site_search_factor origin:1,total:2

#CMD="docker exec -u splunk -ti $m_cm /opt/splunk/bin/splunk edit cluster-config -mode master -multisite true -available_sites $sites_list -site site1 -site_replication_factor origin:2,total:3 -site_search_factor origin:1,total:2 -secret $MYSECRET -auth $USERADMIN:$USERPASS "
CMD="docker exec -u splunk -ti $m_cm /opt/splunk/bin/splunk edit cluster-config -mode master -multisite true -available_sites $sites_list -site site1 -site_replication_factor $site_rp -site_search_factor $site_sf -secret $MYSECRET -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
OUT=`echo $OUT | sed -e 's/^M//g' | tr -d '\r' | tr -d '\n' `    #clean up
printf " ${Yellow}${ARROW_EMOJI}${NC}Setting multi-site to true... " >&3 ; display_output "$OUT" "property has been edited" "3"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$m_cm"

restart_splunkd "$m_cm"
is_splunkd_running "$m_cm"

update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1" "$(timer "$start_time")"
return
}	#end config_cm_for_multisite()
#---------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------
check_shc_status() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#STEP#6
members_list="$1"; step_pos="$2"
local start_time=$(date +%s);
#clear_page_starting_from "$R_ROLL"
clear_from_if_screen_ended "$R_ROLL"

len=`echo $members_list|wc -w`		#ex: [LON HKG STL]
captain=`echo $members_list| cut -d" " -f$len`
#captain=${members_list##* }			#cut last item
printf "[${Purple}$captain${NC}]${LightBlue} Checking SHC status (on captain)...${NC}"

CMD="docker exec -u splunk -ti $captain /opt/splunk/bin/splunk show shcluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`
display_output "$OUT" "Captain" "2"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$captain"
update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1"	"$(timer "$start_time")"
return
}	#end check_shc_status()
#-----------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_idxc_status() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#STEP#5
cm="$1"; step_pos="$2"
local start_time=$(date +%s);
#clear_page_starting_from "$R_ROLL"
clear_from_if_screen_ended "$R_ROLL"

printf "[${Purple}$cm${NC}]${LightBlue} Checking IDXC status...${NC}"
CMD="docker exec -u splunk -ti $cm /opt/splunk/bin/splunk show cluster-status -auth $USERADMIN:$USERPASS "
OUT=`$CMD`; display_output "$OUT" "Replication factor" "2"
printf "${DarkGray}CMD:[$CMD]${NC}\n" >&4
logline "$CMD" "$cm"
update_progress_bar "$step_pos" "$C_PROGRESS" "1" "1" "$(timer "$start_time")"

return
}	#end check_idxc_status()
#---------------------------------------------------------------------------------------------------------------

## STAND ALONE SHC / IDXC

#---------------------------------------------------------------------------------------------------------------
create_standalone_shc() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates single Search Head Cluster. Parameters parsed from $1
#inputs: $1: pass all components (any order) needed and how many to create. The names the counts will be extracted
#example : create_standalone_shc "$siteSH:$SHcount $cm:1 $lm:1"
#outputs: -adjust hostname with sitename if used
#	  -always convert hostnames to upper case (to avoid lookup/compare issues)
#	  -create single deployer and as many SH hosts required
#	  -if param $1 is "AUTO" skip all user prompts and create standard cluster 3SH/1DEP
#-----------------------------------------------------------------------------------------------------

local TIME_START=$(date +%s);

#display all title with zero progress    ### DONT USE CLEAR ####
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> CLUSTERING MENU -> BUILD STAND-ALONE SEARCH HEAD CLUSTER"

server_list=""    #used by STEP#3

LMname=`echo $1| $GREP -Po '(\s*\w*-*LM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
LMcount=`echo $1| $GREP -Po '(\s*\w*-*LM):\K(\d+)'| tr -d '[[:space:]]' `
MCname=`echo $1| $GREP -Po '(\s*\w*-*MC)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
MCcount=`echo $1| $GREP -Po '(\s*\w*-*MC):\K(\d+)'| tr -d '[[:space:]]' `
DEPname=`echo $1| $GREP -Po '(\s*\w*-*DEP)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
DEPcount=`echo $1| $GREP -Po '(\s*\w*-*DEP):\K(\d+)'| tr -d '[[:space:]]' `

SHlabel=`echo $1| $GREP -Po '(\s*\w*-*LABEL):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
SHname=`echo $1| $GREP -Po '(\s*\w*-*SH)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
SHcount=`echo $1| $GREP -Po '(\s*\w*-*SH):\K(\d+)'| tr -d '[[:space:]]' `

#generate all global lists
dep_list=`docker ps -a --filter name="$DEPname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
sh_list=`docker ps -a --filter name="$SHname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
lm_list=`docker ps -a --filter name="LM|lm" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
cm_list=`docker ps -a --filter name="CM|cm" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`

osx_say "Starting stand alone SHC build, 6 steps"
#initialize status sections
clear_page_starting_from "$R_BUILD_SITE"
print_step_bar_from "$R_BUILD_SITE" "${R_BUILD_COLOR}  " "BUILDING INDEPENDENT STAND-ALONE SHC [$SHlabel]"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "" "1 2 3 4 5 6"
print_step_bar_from "$R_STEP1" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#1: Creating basic services [MC,LM,DEP]"; update_progress_bar "$R_STEP1" "$C_PROGRESS" "" "mc lm dep"
print_step_bar_from "$R_STEP2" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#2: SHC [creating $SHcount generic $SHname's hosts]"; update_progress_bar "$R_STEP2" "$C_PROGRESS" "" "sh1 sh2 sh3"
print_step_bar_from "$R_STEP3" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#3: SHC [configure deployer]"; update_progress_bar "$R_STEP3" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP4" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#4: SHC [configure members]"; update_progress_bar "$R_STEP4" "$C_PROGRESS" "" "sh1 sh2 sh3"
print_step_bar_from "$R_STEP5" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#5: SHC [bootstrap captain]"; update_progress_bar "$R_STEP5" "$C_PROGRESS" ""  "1"
print_step_bar_from "$R_STEP6" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#6: SHC [check status]"; update_progress_bar "$R_STEP6" "$C_PROGRESS" "" "1"

extract_current_cursor_position pos1; x=${pos1[0]};  y=${pos1[1]}
let R_LINE=$x+2; let R_ROLL=$x+3
print_step_bar_from "$R_LINE" "${R_LINE_COLOR}  " "                                                                                "

local start_time=$(date +%s);
local START_TIME=$(date +%s);
#--Starting STEP#1 administrative hosts---
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating Basic services [${Yellow}MC${NC},LM,DEP]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$MCname" "$MCcount" "no"; mc=$gLIST
update_progress_bar "$R_STEP1" "$C_PROGRESS" "mc" "mc lm dep" "$(timer "$start_time")"
#update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5 6" "$(timer "$START_TIME")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating Basic services [CM,${Yellow}LM${NC},DEP]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$LMname" "$LMcount" "no"; lm="$gLIST"
make_lic_slave $lm $mc  #for previous step since lm was not ready yet
make_mc_search_peer $mc $lm
update_progress_bar "$R_STEP1" "$C_PROGRESS" "lm" "mc lm dep" "$(timer "$start_time")"
#update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5 6" "$(timer "$START_TIME")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating Basic services [CM,LM,${Yellow}DEP${NC}]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$DEPname" "$DEPcount" "no"; dep="$gLIST"
make_lic_slave $lm $dep; make_mc_search_peer $mc $dep
update_progress_bar "$R_STEP1" "$C_PROGRESS" "dep" "mc lm dep" "$(timer "$start_time")"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5 6" "$(timer "$START_TIME")"
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating Basic services [CM,LN,${NC}DEP]"
#--Finished STEP#1 administrative hosts---
osx_say "Finished step 1, creating basic services"

#--Starting STEP#2 Creating SH hosts---
print_step_bar_from "$R_STEP2" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#2: SHC [creating $SHcount generic $SHname's hosts]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$SHname" "$SHcount" "yes" "$R_STEP2"; members_list="$gLIST"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "2" "1 2 3 4 5 6" "$(timer "$START_TIME")"
#--Finished STEP#2 Creating SH hosts---
osx_say "Finished step 2, creating $SHCcount generic SHC hosts"


## from this point on all hosts should be created and ready. Next steps are SHCluster configurations ##########
#DEPLOYER CONFIGURATION: (create [shclustering] stanza; set SecretKey and restart) -----

#--Starting STEP#1 Deployer configuration---
print_step_bar_from "$R_STEP3" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#3: SHC [configure deployer $dep]"
clear_page_starting_from "$R_ROLL"
configure_deployer "$dep" "$SHlabel" "$R_STEP3"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "3" "1 2 3 4 5 6" "$(timer "$START_TIME")"
#--Finished STEP#1 Deployer configuration---
osx_say "Finished step 3, configuring deployer"

printf "${LightRed}DEBUG:=> ${Yellow}In $FUNCNAME(): ${Purple}After members_list loop> param2:[$2] members_list:[$members_list] sh_list:[$sh_list]${NC}\n" >&6

#--Starting STEP#2 Cluster members configuration---
print_step_bar_from "$R_STEP4" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#4: SHC configure members [$members_list]"
config_sh_for_singlesite "$members_list" "$cm" "$mc" "$lm" "$R_STEP4"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "4" "1 2 3 4 5 6" "$(timer "$START_TIME")"
#--Finished STEP#2 Cluster members configuration---
osx_say "Finished step 4, configuring SHC members"

#--Starting STEP#3 Captain configuration---
last_field=`echo "$members_list" | rev | cut -d' ' -f1 | rev`
print_step_bar_from "$R_STEP5" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#5: SHC [bootstrap captain $last_field]"
clear_page_starting_from "$R_ROLL"
configure_captain "$members_list" "$R_STEP5"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "5" "1 2 3 4 5 6" "$(timer "$START_TIME")"
#--Finished STEP#3 Captain configuration---
osx_say "Finished step 5, boot straping captin"

#--Starting STEP#4 Check SHC status---
print_step_bar_from "$R_STEP6" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#6: SHC [check status]"
clear_page_starting_from "$R_ROLL"
check_shc_status "$members_list" "$R_STEP6"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "6" "1 2 3 4 5 6" "$(timer "$START_TIME")"
#--Finished STEP#4 Check SHC status---
osx_say "Finished step 6, checking SHC status"

clear_page_starting_from "$R_ROLL"
echo
printf "${LightGreen}Stand-Alone SH Cluster Build Completed!\n"
printf "${ACTIVE_TXT_COLOR}Cluster Label\t:${NC} $SHlabel\n"
printf "${ACTIVE_TXT_COLOR}License Master\t:${NC} $lm\n"
printf "${ACTIVE_TXT_COLOR}Master Console\t:${NC} $mc\n"
printf "${ACTIVE_TXT_COLOR}Deployer\t\t:${NC} $dep\n"
printf "${ACTIVE_TXT_COLOR}SHC Memebers\t:${NC} $members_list\n"
echo
docker_status
total_time=$(timer "$START_TIME")
osx_say "Stand alone SHC ready. Total time $total_time"


return 0
}	#create_standalone_shc()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_standalone_idxc() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates single IDX cluster. Details are parsed from $1

local start_time=$(date +%s); local START_TIME=$(date +%s);
clear_page_starting_from "$R_STEP1"

#$1 CMbasename:count   $2 IDXbasename:count  $3 LMbasename:count
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> CLUSTERING MENU -> BUILD STAND-ALONE INDEXING CLUSTER"

check_load
#Extract values from $1 if passed to us!
LMname=`echo $1| $GREP -Po '(\s*\w*-*LM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
LMcount=`echo $1| $GREP -Po '(\s*\w*-*LM):\K(\d+)'| tr -d '[[:space:]]' `
MCname=`echo $1| $GREP -Po '(\s*\w*-*MC)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
MCcount=`echo $1| $GREP -Po '(\s*\w*-*MC):\K(\d+)'| tr -d '[[:space:]]' `
CMname=`echo $1| $GREP -Po '(\s*\w*-*CM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
CMcount=`echo $1| $GREP -Po '(\s*\w*-*CM):\K(\d+)'| tr -d '[[:space:]]' `
IDXlabel=`echo $1| $GREP -Po '(\s*\w*-*LABEL):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
IDXname=`echo $1| $GREP -Po '(\s*\w*-*IDX)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
IDXcount=`echo $1| $GREP -Po '(\s*\w*-*IDX):\K(\d+)'| tr -d '[[:space:]]' `
RFcount=`echo $1| $GREP -Po '(\s*\w*-*RF):\K(\d+)'| tr -d '[[:space:]]' `
SFcount=`echo $1| $GREP -Po '(\s*\w*-*SF):\K(\d+)'| tr -d '[[:space:]]' `
#echo "LMname:$LMname LMcount:$LMcount label:$label IDXname:$IDXname IDXcount:$IDXcount CMname:$CMname CMcount:$CMcount"
#exit

cm_list=`docker ps -a --filter name="$CMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`
lm_list=`docker ps -a --filter name="$LMname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'` #global list
idx_list=`docker ps -a --filter name="$IDXname" --format "{{.Names}}"|sort| tr '\n' ' '|sed 's/: /:/g'`

osx_say "Starting stand alone IDXC build, 5 steps"
#initialize status section
clear_page_starting_from "$R_BUILD_SITE"
print_step_bar_from "$R_BUILD_SITE" "${R_BUILD_COLOR}  " "BUILDING INDEPENDENT STAND-ALONE IDXC [$IDXlabel]"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "" "1 2 3 4 5"
print_step_bar_from "$R_STEP1" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#1: Creating basic services"; update_progress_bar "$R_STEP1" "$C_PROGRESS" "" "mc lm cm"
print_step_bar_from "$R_STEP2" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#2: IDXC [creating $IDXcount generic $IDXname's hosts]"; update_progress_bar "$R_STEP2" "$C_PROGRESS" "" "idx1 idx2 idx3"
print_step_bar_from "$R_STEP3" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#3: IDXC [configure cluster master]"; update_progress_bar "$R_STEP3" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP4" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#4: IDXC [configure members]"; update_progress_bar "$R_STEP4" "$C_PROGRESS" "" "1 2 3"
print_step_bar_from "$R_STEP5" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#5: IDXC [check status]"; update_progress_bar "$R_STEP5" "$C_PROGRESS" ""  "1"

extract_current_cursor_position pos1; x=${pos1[0]};  y=${pos1[1]}
let R_LINE=$x+2; let R_ROLL=$x+3
print_step_bar_from "$R_LINE" "${R_LINE_COLOR}  " "                                                                                "
#--Starting STEP#1 administrative hosts---
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [${Yellow}MC${NC},LM,CM]";clear_page_starting_from "$R_ROLL"
create_splunk_container "$MCname" "$MCcount" "no"; mc=$gLIST
update_progress_bar "$R_STEP1" "$C_PROGRESS" "1" "1 2 3" "$(timer "$start_time")"
#update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5" "$(timer "$START_TIME")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [MC,${Yellow}LM${NC},CM]";clear_page_starting_from "$R_ROLL"
create_splunk_container "$LMname" "$LMcount" "no"; lm=$gLIST
make_lic_slave "$lm" "$mc"
make_mc_search_peer "$mc" "$lm"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "2" "1 2 3"  "$(timer "$start_time")"
#update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5" "$(timer "$START_TIME")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [MC,LM,${Yellow}CM${NC}]";clear_page_starting_from "$R_ROLL"
create_splunk_container "$CMname" "$CMcount" "no" "" "$R_ROLL"; cm=$gLIST
make_lic_slave "$lm" "$cm"; make_mc_search_peer "$mc" "$cm"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "3" "1 2 3" "$(timer "$start_time")"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5" "$(timer "$START_TIME")"
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [MC,LM,${NC}CM]";clear_page_starting_from "$R_ROLL"
osx_say "Finished step 1, creating basic services"

#create the remaining IDXs
print_step_bar_from "$R_STEP2" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#2: IDXC [creating $IDXcount generic $IDXname's hosts]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$IDXname" "$IDXcount" "yes" "$R_STEP2" "$R_ROLL" ; members_list="$gLIST"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "2" "1 2 3 4 5" "$(timer "$START_TIME")"
#--Finished STEP#1 administrative hosts---
osx_say "Finished step 2, creating $IDXcount IDXC generic hosts"

#--Starting STEP#3 ClusterMaster configuration---
print_step_bar_from "$R_STEP3" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#3: IDXC [configure cluster master $cm]"; clear_page_starting_from "$R_ROLL"
config_cm_for_singlesite "$cm" "$IDXlabel" "$R_STEP3" "$RFcount" "$SFcount"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "3" "1 2 3 4 5" "$(timer "$START_TIME")"
#--Finished STEP#3 ClusterMaster configuration---
osx_say "Finished step 3, configuring cluster master"

#--Starting STEP#4 IDXC nodes configuration---
print_step_bar_from "$R_STEP4" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#4: IDXC configure members [$members_list]"
config_idx_for_singlesite "$members_list" "$IDXlabel" "$lm" "$cm" "$R_STEP4" "$mc"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "4" "1 2 3 4 5" "$(timer "$START_TIME")"
#--Finished STEP#4 IDXC nodes configuration---
osx_say "Finished step 4, configuring IDXC members"

#--Starting STEP#5 Verifying IDXC status---
print_step_bar_from "$R_STEP5" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} "  "STEP#5: IDXC [check status]"; clear_page_starting_from "$R_ROLL"
check_idxc_status "$cm" "$R_STEP5"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "5" "1 2 3 4 5" "$(timer "$START_TIME")"
#--Finsihed STEP#5 Verifying IDXC status---
osx_say "Finished step 5, IDXC status check"

clear_page_starting_from "$R_ROLL"
echo
printf "${LightGreen}Stand-Alone IDX Cluster Build Completed!\n"
printf "${ACTIVE_TXT_COLOR}Cluster Label\t:${NC} $IDXlabel\n"
printf "${ACTIVE_TXT_COLOR}Cluster Master\t:${NC} $cm\n"
printf "${ACTIVE_TXT_COLOR}License Master\t:${NC} $lm\n"
printf "${ACTIVE_TXT_COLOR}Master Console\t:${NC} $mc\n"
printf "${ACTIVE_TXT_COLOR}IDXC Memebers\t:${NC} $members_list\n"
printf "${ACTIVE_TXT_COLOR}R-FACTOR/S-FACTOR\t:${NC} $RFcount/$SFcount\n"
echo
docker_status
total_time=$(timer "$START_TIME")
osx_say "Stand alone IDXC ready. Total time $total_time"

return 0
}	#end create_standalone_idxc()
#---------------------------------------------------------------------------------------------------------------

##### BUILD SITE(S) CLUSTERS ########

#---------------------------------------------------------------------------------------------------------------
build_singlesite_cluster() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function will build 1 CM and 1 LM then calls create_splunk_container ()

local start_time=$(date +%s); local START_TIME=$(date +%s);

#extract these values from $1 if passed to us!
LMname=`echo $1| $GREP -Po '(\s*\w*-*LM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
LMcount=`echo $1| $GREP -Po '(\s*\w*-*LM):\K(\d+)'| tr -d '[[:space:]]' `
MCname=`echo $1| $GREP -Po '(\s*\w*-*MC)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
MCcount=`echo $1| $GREP -Po '(\s*\w*-*MC):\K(\d+)'| tr -d '[[:space:]]' `
DEPname=`echo $1| $GREP -Po '(\s*\w*-*DEP)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
DEPcount=`echo $1| $GREP -Po '(\s*\w*-*DEP):\K(\d+)'| tr -d '[[:space:]]' `
CMname=`echo $1| $GREP -Po '(\s*\w*-*CM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
CMcount=`echo $1| $GREP -Po '(\s*\w*-*CM):\K(\d+)'| tr -d '[[:space:]]' `
IDXname=`echo $1| $GREP -Po '(\s*\w*-*IDX)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
IDXcount=`echo $1| $GREP -Po '(\s*\w*-*IDX):\K(\d+)'| tr -d '[[:space:]]' `
SHname=`echo $1| $GREP -Po '(\s*\w*-*SH)' | tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]' `
SHcount=`echo $1| $GREP -Po '(\s*\w*-*SH):\K(\d+)'| tr -d '[[:space:]]' `
RFcount=`echo $1| $GREP -Po '(\s*\w*-*RF):\K(\d+)'| tr -d '[[:space:]]' `
SFcount=`echo $1| $GREP -Po '(\s*\w*-*SF):\K(\d+)'| tr -d '[[:space:]]' `


label=`echo $1| $GREP -Po '(\s*\w*-*LABEL):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
SITElocation=`echo $1| $GREP -Po '(\s*\w*-*SNAME):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
SITElocation_clean=`echo $SITElocation| sed 's/_//g'` #Remove "_" if found. Used for title display only

LMname="$SITElocation""$LMname"
MCname="$SITElocation""$MCname"
DEPname="$SITElocation""$DEPname"
CMname="$SITElocation""$CMname"
IDXname="$SITElocation""$IDXname"
SHname="$SITElocation""$SHname"

clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> CLUSTERING MENU -> BUILD SINGLE-SITE CLUSTER"
extract_current_cursor_position pos1; x=${pos1[0]};  y=${pos1[1]}
let R_LINE=$x+2; let R_ROLL=$x+3

clear_page_starting_from "$R_ROLL"
idx_seq=$(seq 1 $STD_IDXC_COUNT)
sh_seq=$(seq 1 $STD_IDXC_COUNT)

osx_say "Starting single site cluster build, 10 steps"
#initialize status section
#clear_page_starting_from "$R_ROLL"
clear_page_starting_from "$R_BUILD_SITE"
print_step_bar_from "$R_BUILD_SITE" "${R_BUILD_COLOR}  " "BUILDING SINGLE-SITE CLUSTER [$SITElocation_clean]"; update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "" "1 2 3 4 5 6 7 8 9 10"

print_step_bar_from "$R_STEP1" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#1: Creating basic services"; update_progress_bar "$R_STEP1" "$C_PROGRESS" "" "mc lm cm dep"
print_step_bar_from "$R_STEP2" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#2: IDXC [creating $IDXcount hosts]"; update_progress_bar "$R_STEP2" "$C_PROGRESS" "" "$idx_seq"
print_step_bar_from "$R_STEP3" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#3: IDXC [configure CM]"; update_progress_bar "$R_STEP3" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP4" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#4: IDXC [configure members]"; update_progress_bar "$R_STEP4" "$C_PROGRESS" "" "$idx_seq"
print_step_bar_from "$R_STEP5" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#5: IDXC [check status]"; update_progress_bar "$R_STEP5" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP6" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#6: SHC [creating $SHcount hosts]"; update_progress_bar "$R_STEP6" "$C_PROGRESS" "" "$sh_seq"
print_step_bar_from "$R_STEP7" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#6: SHC [configure deployer]"; update_progress_bar "$R_STEP7" "$C_PROGRESS" "" "1 2"
print_step_bar_from "$R_STEP8" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#8: SHC [configure members]"; update_progress_bar "$R_STEP8" "$C_PROGRESS" "" "$idx_seq"
print_step_bar_from "$R_STEP9" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#9: SHC [configure captain]"; update_progress_bar "$R_STEP9" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP10" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#10: SHC [check status]"; update_progress_bar "$R_STEP10" "$C_PROGRESS" "" "1"

extract_current_cursor_position pos1; x=${pos1[0]};  y=${pos1[1]}
let R_LINE=$x+2; let R_ROLL=$x+3
print_step_bar_from "$R_LINE" "${R_LINE_COLOR}  " "                                                                                "
check_load
#Basic services
#Sequence is very important!


print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [${Yellow}MC${NC},LM,CM,DEP]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$MCname" "$MCcount" "no" "$R_STEP1" "$R_ROLL"; mc=$gLIST
update_progress_bar "$R_STEP1" "$C_PROGRESS" "mc" "mc lm cm dep" "$(timer "$start_time")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [MC,${Yellow}LM${NC},CM,DEP]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$LMname" "$LMcount" "no" "$R_STEP1" "$R_ROLL"; lm=$gLIST
make_lic_slave "$lm" "$mc"; make_mc_search_peer "$mc" "$lm"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "lm" "mc lm cm dep" "$(timer "$start_time")"
#update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5 6 7 8 9 11" "$(timer "$START_TIME")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [MC,LM,${Yellow}CM${NC},DEP]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$CMname" "$CMcount" "no"; cm=$gLIST
make_lic_slave "$lm" "$cm" ; make_mc_search_peer "$mc" "$cm"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "cm" "mc lm cm dep" "$(timer "$start_time")"
#update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [MC,LM,CM,${Yellow}DEP${NC}]"; clear_page_starting_from "$R_ROLL"
create_splunk_container "$DEPname" "$DEPcount" "no" "$R_STEP1" "$R_ROLL"; dep=$gLIST
make_lic_slave "$lm" "$dep" ; make_mc_search_peer "$mc" "$dep"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "dep" "mc lm cm dep" "$(timer "$start_time")"
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Creating basic services [MC,LM,CM,${NC}DEP]"

update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5 6 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 1, creating basic services"

#--Starting Building IDXC----------------------------------------------
local start_time=$(date +%s);	#reset for each cluster
print_step_bar_from "$R_STEP2" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#2: IDXC [creating $IDXcount hosts]"
clear_page_starting_from "$R_ROLL"
create_splunk_container "$IDXname" "$IDXcount" "yes" "$R_STEP2"; idxc_members_list="$gLIST"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "2" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 2, creating $IDXcount IDXC generic hosts"

print_step_bar_from "$R_STEP3" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#3: IDXC [configure CM]"
clear_page_starting_from "$R_ROLL"
config_cm_for_singlesite "$cm" "$label" "$R_STEP3" "$RFcount" "$RFcount"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "3" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 3, configuring cluster master"

print_step_bar_from "$R_STEP4" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#4: IDXC [configure members]"
config_idx_for_singlesite "$idxc_members_list" "$label" "$lm" "$cm" "$R_STEP4" "$mc"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "4" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 4, configuring IDXC members"

#--Verifying IDXC status---
print_step_bar_from "$R_STEP5" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#5: IDXC [check status]"
clear_page_starting_from "$R_ROLL"
check_idxc_status "$cm" "$R_STEP5"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "5" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 5, IDXC status check"
#--Finished Building IDXC------------------------------------------------------

#--Starting Building SHC-------------------------------------------------------
local start_time=$(date +%s);
print_step_bar_from "$R_STEP6" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#6: SHC [creating $SHcount hosts]"
clear_page_starting_from "$R_ROLL"
create_splunk_container "$SHname" "$SHcount" "yes" "$R_STEP6"; shc_members_list="$gLIST"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "6" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 6, creating $SHcount SHC generic hosts"

print_step_bar_from "$R_STEP7" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#7: SHC [configure deployer]"
clear_page_starting_from "$R_ROLL"
configure_deployer "$dep" "$label" "$R_STEP7"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "7" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 7, deployer configuration"

print_step_bar_from "$R_STEP8" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#8: SHC [configure members]"
config_sh_for_singlesite "$shc_members_list" "$cm" "$mc" "$lm" "$R_STEP8"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "8" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 4, configuring SHC members"

print_step_bar_from "$R_STEP9" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#9: SHC [configure captain]"
clear_page_starting_from "$R_ROLL"
configure_captain "$shc_members_list" "$R_STEP9"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "9" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
osx_say "Finished step 9, captin configuration"

print_step_bar_from "$R_STEP10" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#10: SHC [check status]"
clear_page_starting_from "$R_ROLL"
check_shc_status "$shc_members_list" "$R_STEP10"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "10" "1 2 3 4 5 6 7 8 9 10" "$(timer "$START_TIME")"
osx_say "Finished step 10, SHC status check"
#--Finished Building SHC----------------------------------------------------------------

clear_page_starting_from "$R_ROLL"
printf "${LightGreen}Single-Site Cluster Build Completed!\n"
printf "${ACTIVE_TXT_COLOR}Site Name\t\t:${NC} $SITElocation_clean\n"
printf "${ACTIVE_TXT_COLOR}Site Label\t:${NC} $label\n"
printf "${ACTIVE_TXT_COLOR}Cluster Master\t:${NC} $cm\n"
printf "${ACTIVE_TXT_COLOR}Master Console\t:${NC} $mc\n"
printf "${ACTIVE_TXT_COLOR}License Master\t:${NC} $lm\n"
printf "${ACTIVE_TXT_COLOR}Deployer\t\t:${NC} $dep\n"
printf "${ACTIVE_TXT_COLOR}SHC Memebers\t:${NC} $shc_members_list\n"
printf "${ACTIVE_TXT_COLOR}IDXC Memebers\t:${NC} $idxc_members_list\n"
printf "${ACTIVE_TXT_COLOR}R-FACTOR/S-FACTOR\t:${NC} $RFcount/$SFcount\n"
docker_status

total_time=$(timer "$START_TIME")
osx_say "single site cluster ready. Total time $total_time"

return 0
}	#build_singlesite_cluster()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
build_multisite_cluster() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function creates site-2-site cluster
#http://docs.splunk.com/Documentation/Splunk/6.4.3/Indexer/Migratetomultisite
cluster_conf1="$1"; cluster_conf2="$2"; factors_conf="$3"
clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> CLUSTERING MENU -> BUILD MULTI-SITE CLUSTER"

check_load
local START_TIME=$(date +%s);

#-----extract these values from $3 ---------------------------------------------
#factors_conf="RF:origin:1, site1:1,site2:1,site3:2,total:5 SF:origin:2,total:3"
#echo "[$factors_conf]"
site_rf=`echo $factors_conf| $GREP -Po '(\s*\w*-*RF):\K(\w.*)\s' | tr -d '[[:space:]]'`
site_sf=`echo $factors_conf| $GREP -Po '(\s*\w*-*SF):\K(\w.*)' | tr -d '[[:space:]]'`
sites_factors_list="${Green}RF:${Blue}$site_rf\t${Green}SF:${Blue}$site_sf${NC}"
#echo "RF:[$site_rf]"; echo "SF:[$site_sf]"
#------------------------------------------------------------------------------

#-----extract these values from $1 ---------------------------------------------
LMname=`echo $cluster_conf1  | $GREP -Po '(\s*\w*-*LM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
LMcount=`echo $cluster_conf1 | $GREP -Po '(\s*\w*-*LM):\K(\d+)'| tr -d '[[:space:]]' `
MCname=`echo $cluster_conf1  | $GREP -Po '(\s*\w*-*MC)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
MCcount=`echo $cluster_conf1 | $GREP -Po '(\s*\w*-*MC):\K(\d+)'| tr -d '[[:space:]]' `
CMname=`echo $cluster_conf1  | $GREP -Po '(\s*\w*-*CM)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
CMcount=`echo $cluster_conf1 | $GREP -Po '(\s*\w*-*CM):\K(\d+)'| tr -d '[[:space:]]' `
#------------------------------------------------------------------------------
#printf "cluster_conf1:[$cluster_conf1]"
#printf "cluster_conf2:[$cluster_conf2]"
#printf "factors_conf:[$factors_conf]"

clear_page_starting_from "$R_ROLL"

#-----extract these values from $2 ---------------------------------------------
#cluster_conf2="LOC:DC01 SITE:site1 IDX:4 SH:0 DEP:1 AFF:site1 LABEL:buttercup,LOC:DC02 SITE:site2 IDX:2 SH:1 AFF:site0"
defIFS="$(printf " \t\nx")"; defIFS="${defIFS%x}"	#save default IFS
IFS=","; read -a fields <<<"$cluster_conf2"			#convert to array
IFS="$defIFS"		#**IF NOT RESTORED; WIL LIMPACT ENTIRE CODE***

loc_list=""; sites_list=""
sites_idx_list="";sites_sh_list="";sites_loc_list="";sites_aff_list="";sites_dep_list=""
for (( idx=0; idx <= (${#fields[@]}-1)  ; idx++ )) ; do
    #echo "$idx: ${fields[idx]}"
	IDXname=`echo ${fields[idx]}  | $GREP -Po '(\s*\w*-*IDX)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
	IDXcount=`echo ${fields[idx]}  | $GREP -Po '(\s*\w*-*IDX):\K(\d+)'| tr -d '[[:space:]]' `
	SHname=`echo ${fields[idx]}   | $GREP -Po '(\s*\w*-*SH)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
	SHcount=`echo ${fields[idx]}  | $GREP -Po '(\s*\w*-*SH):\K(\d+)'| tr -d '[[:space:]]' `
	DEPname=`echo ${fields[idx]}   | $GREP -Po '(\s*\w*-*DEP)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
	DEPcount=`echo ${fields[idx]}  | $GREP -Po '(\s*\w*-*DEP):\K(\d+)'| tr -d '[[:space:]]' `
	LABELname=`echo ${fields[idx]} | $GREP -Po '(\s*\w*-*LABEL):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
	AFFsite=`echo ${fields[idx]}  | $GREP -Po '(\s*\w*-*AFF):\K(\w+)'| tr -d '[[:space:]]'| tr '[A-Z]' '[a-z]'`

	SITEloc=`echo ${fields[idx]}  | $GREP -Po '(\s*\w*-*LOC):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
	SITEname=`echo ${fields[idx]} | $GREP -Po '(\s*\w*-*SITE):\K(\w+)'| tr -d '[[:space:]]'| tr '[A-Z]' '[a-z]'`
	loc_list="$loc_list""$SITEloc "
	sites_list="$sites_list""$SITEname "

	#used for reporting at the end
	sites_loc_list="$sites_loc_list""${Green}$SITEloc:${Blue}$SITEname${NC}\t"
	sites_idx_list="$sites_idx_list""${Green}$SITEloc:${Blue}$IDXcount-IDXs${NC}\t"
	sites_sh_list="$sites_sh_list""${Green}$SITEloc:${Blue}$SHcount-SHs${NC}\t"
	sites_aff_list="$sites_aff_list""${Green}$SITEloc:${Blue}$AFFsite${NC}\t"
	sites_dep_list="$sites_dep_list""${Green}$SITEloc:${Blue}$DEPcount${NC}\t"
	#echo "[$SITEloc]"
#	echo "LOC:$SITEloc SITE:$SITEname IDX:$IDXcount SH:$SHcount AFF:$AFFsite"
	#echo
done
#printf "loc_list: [$loc_list]\n"
#printf "sites_list: [$sites_list]\n"
#printf "sites_loc_list: [$sites_loc_list]\n"
#printf "sites_idx_list: [$sites_idx_list]\n"
#printf "sites_sh_list:  [$sites_sh_list]\n"
#printf "sites_aff_list: [$sites_aff_list]\n"
#printf "sites_factors_list: [$sites_factors_list]\n"
#exit

#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
#example of final outputs:
# loc_list		[DC01 DC02 DC03]	#used in main loop thru all sites
# sites_list	[site1,site2,site3]	#used in docker exec command
# sites_array	[site1 site2 site3]	#used for easy access to sites_list
#
#echo "Initial values1: loc_list[$loc_list] sites_list[$sites_list]"
loc_list=`echo $loc_list|tr " " "\n"|tr "\n" " " `		#Do not sort.match user input
sites_list=`echo $sites_list|tr " " "\n"|sort|tr "\n" " "`	#sort
#echo "Initial values2: loc_list[$loc_list] sites_list[$sites_list]"
declare -a sites_array="($sites_list)"  			#convert sites_list to array for easy items reference
loc_list=`echo ${loc_list%?}`						#remove trailing space
sites_list=`echo ${sites_list%?} | sed 's/ /,/g'`	#remove trailing space & repl space with comma
#echo "LOC_LIST:[$loc_list]";echo "SITES_LIST:[$sites_list]"
#echo "SITES_ARRAY:[${sites_array[@]}]"

#sanity check
loc_list_len=`echo $loc_list|wc -w |sed 's/ //g' `		#ex: [DC01 DC02 DC03]
if [ "$loc_list_len" -eq "0" ]; then
	printf "${LightRed} Error! Sites list is zero length${NC}\n"; exit
fi


#Primary site is the 1st site
loc_list_clean=`echo $loc_list| sed 's/_//g'` #Remove "_" if found. Used for title display only
primary_loc=`echo $loc_list|awk '{print $1}'`		#where basic services CM,LM resides
primary_loc_clean=`echo $primary_loc| sed 's/_//g'` #Remove "_" if found. Used for title display only

osx_say "Starting $loc_list_len site cluster build, 9 steps"
#Initialize status section. First time!
print_step_bar_from "$R_BUILD_SITE" "${R_BUILD_COLOR}  " "BUILDING $loc_list_len-SITE CLUSTER [$loc_list_clean]"; update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "" "1 2 3 4 5 6 7 8 9"
print_step_bar_from "$R_STEP1" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#1: Basic services [$primary_loc_clean] [MC,LM,CM]"; update_progress_bar "$R_STEP1" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP2" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#2: IDXC [creating $IDXcount generic $IDXname's hosts]";update_progress_bar "$R_STEP2" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP3" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#3: IDXC [configure members]"; update_progress_bar "$R_STEP3" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP4" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#4: IDXC [check status]"; update_progress_bar "$R_STEP4" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP5" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#5: SHC [creating $SHcount generic $SHname's hosts]"; update_progress_bar "$R_STEP5" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP6" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#6: SHC [configure deployer]"; update_progress_bar "$R_STEP6" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP7" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#7: SHC [configure members]"; update_progress_bar "$R_STEP7" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP8" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#8: SHC [bootstrap captain]"; update_progress_bar "$R_STEP8" "$C_PROGRESS" "" "1"
print_step_bar_from "$R_STEP9" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#9: SHC [check status]"; update_progress_bar "$R_STEP9" "$C_PROGRESS" "" "1"

#dynamically calculate R_LINE and R_ROLL
extract_current_cursor_position pos1; x=${pos1[0]};  y=${pos1[1]}
let R_LINE=$x+2; let R_ROLL=$x+3
print_step_bar_from "$R_LINE" "${R_LINE_COLOR}  " "                                                                                "

#-----Building basic services in primary site only (exclude DEP) -------------------------------
#Sequence is very important!
local start_time=$(date +%s); local START_TIME=$(date +%s);

#append sitename to basic service hostnames (found in cluster_conf1)
MCname="$primary_loc""$MCname"; LMname="$primary_loc""$LMname"; CMname="$primary_loc""$CMname"

#highlight current site
highlight_site=$(color_selected "$primary_loc" "$loc_list_clean")
print_step_bar_from "$R_BUILD_SITE" "${R_BUILD_COLOR}  " "BUILDING $loc_list_len-SITE CLUSTER [$highlight_site]"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Basic services in primary site [${Yellow}MC${NC},LM,CM]"
clear_page_starting_from "$R_ROLL"
#printf "${DarkGray}Locations:[$loc_list] CM:[$m_cm] First_site:[$primary_loc] ${NC}\n\n" >&4

create_splunk_container "$MCname" "$MCcount" "no" ; m_mc=$gLIST
update_progress_bar "$R_STEP1" "$C_PROGRESS" "m_mc" "m_mc m_lm m_cm" "$(timer "$start_time")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Basic services in primary site [MC,${Yellow}LM${NC},CM]"
clear_page_starting_from "$R_ROLL"
create_splunk_container "$LMname" "$LMcount" "no"; m_lm=$gLIST
make_lic_slave "$m_lm" "$m_mc" ; make_mc_search_peer "$m_mc" "$m_lm"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "m_lm" "m_mc m_lm m_cm" "$(timer "$start_time")"

print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Basic services in primary site [MC,LM,${Yellow}CM${NC}]"
clear_page_starting_from "$R_ROLL"
create_splunk_container "$CMname" "$CMcount" "no" ; m_cm=$gLIST
make_lic_slave "$m_lm" "$m_cm" ; make_mc_search_peer "$m_mc" "$m_cm"
config_cm_for_multisite "$m_cm" "$sites_list" "$R_STEP1" "$site_rf" "$site_sf"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "m_cm" "m_mc m_lm m_cm" "$(timer "$start_time")"
update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "1" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
#-----Building basic services in primary site only (exclude DEP) -------------------------------
osx_say "Finished step 1, site1, creating basic services"	#site1 is  unknown at this point

enable_cm_maintenance_mode "$m_cm"

#===========Building all sites IDXC & SHC (include DEP per site) ========================

local a_item=0					#always start at first element in the array
for loc in $loc_list; do
	site=${sites_array[$a_item]}
	IDXname=`echo ${fields[$a_item]}  | $GREP -Po '(\s*\w*-*IDX)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
	IDXcount=`echo ${fields[$a_item]} | $GREP -Po '(\s*\w*-*IDX):\K(\d+)'| tr -d '[[:space:]]' `
	SHname=`echo ${fields[$a_item]}   | $GREP -Po '(\s*\w*-*SH)'| tr -d '[[:space:]]' | tr '[a-z]' '[A-Z]'`
	SHcount=`echo ${fields[$a_item]}  | $GREP -Po '(\s*\w*-*SH):\K(\d+)'| tr -d '[[:space:]]' `
	DEPname=`echo ${fields[$a_item]}  | $GREP -Po '(\s*\w*-*DEP)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
	DEPcount=`echo ${fields[$a_item]} | $GREP -Po '(\s*\w*-*DEP):\K(\d+)'| tr -d '[[:space:]]' `
	AFFsite=`echo ${fields[$a_item]}  | $GREP -Po '(\s*\w*-*AFF):\K(\w+)'| tr -d '[[:space:]]'| tr '[A-Z]' '[a-z]'`
	SITEloc=`echo ${fields[$a_item]}  | $GREP -Po '(\s*\w*-*LOC):\K(\w+)'| tr -d '[[:space:]]'| tr '[a-z]' '[A-Z]'`
	SITEname=`echo ${fields[$a_item]} | $GREP -Po '(\s*\w*-*SITE):\K(\w+)'| tr -d '[[:space:]]'| tr '[A-Z]' '[a-z]'`

	#convert basenames to include current site location
	IDXname="$loc""$IDXname"; SHname="$loc""$SHname";DEPname="$loc""$DEPname"
	highlight_site=$(color_selected "$loc" "$loc_list_clean")

	#-- initialize again starting (must reset view for each site in the loop) --- Second time!
	print_step_bar_from "$R_BUILD_SITE" "${R_BUILD_COLOR}  " "BUILDING $loc_list_len-SITE CLUSTER [$highlight_site]"
	print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#1: Basic services in primary site [MC,LM,${NC}CM]"
	print_step_bar_from "$R_STEP2" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#2: IDXC [creating $IDXcount generic $IDXname's hosts]"; update_progress_bar "$R_STEP2" "$C_PROGRESS" "" "1"
	print_step_bar_from "$R_STEP3" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#3: IDXC [configure members for multisite]"; update_progress_bar "$R_STEP3" "$C_PROGRESS" "" "1"
	print_step_bar_from "$R_STEP4" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#4: IDXC [check status]"; update_progress_bar "$R_STEP4" "$C_PROGRESS" "" "1"
	print_step_bar_from "$R_STEP5" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#5: SHC [creating $SHcount generic $SHname's hosts]"; update_progress_bar "$R_STEP5" "$C_PROGRESS" "" "1"
	print_step_bar_from "$R_STEP6" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#6: SHC [configure deployer]"; update_progress_bar "$R_STEP6" "$C_PROGRESS" "" "1"
	print_step_bar_from "$R_STEP7" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#7: SHC [configure members for multisite]"; update_progress_bar "$R_STEP7" "$C_PROGRESS" "" "1"
	print_step_bar_from "$R_STEP8" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#8: SHC [bootstrap captain]"; update_progress_bar "$R_STEP8" "$C_PROGRESS" "" "1"
	print_step_bar_from "$R_STEP9" "${INACTIVE_TXT_COLOR}${DONT_ENTER_EMOJI} " "STEP#9: SHC [check status]"; update_progress_bar "$R_STEP9" "$C_PROGRESS" "" "1"
	#-- initialize again starting (must reset view for each site in the loop) ---

	clear_page_starting_from "$R_ROLL"


	#--- create generic IDX----------------------------------------------
	local start_time=$(date +%s);
	print_step_bar_from "$R_STEP2" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#2: IDXC [creating $IDXcount generic $IDXname's hosts]"
	clear_page_starting_from "$R_ROLL"
	create_splunk_container "$IDXname" "$IDXcount" "yes" "$R_STEP2"; idxc_members_list="$gLIST"
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "2" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	#--- create generic IDX----------------------------------------------
	osx_say "Finished step 2, $site, creating $IDXcount IDXC generic hosts"

	#--- configure idx's to members----------------------------------------------
	m_cm_ip=`docker port $m_cm| awk '{print $3}'| cut -d":" -f1|head -1 `
#	highlight_site=$(color_selected "$SITElocation" "$LOCATIONSlist_clean")
	print_step_bar_from "$R_STEP3" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#3: IDXC [configure members for multisite]"
	clear_page_starting_from "$R_ROLL"

	#------------ idx loop for all idxs in the entire cluster (all sites) -----
	for idx in $idxc_members_list; do
		#printf "idx[$idx] loc[$loc] site[$site] m_cm_ip[$m_cm_ip]\n"
		config_idx_for_multisite "$idx" "$loc" "$site" "$m_cm_ip" "$R_STEP3" "$m_mc" "$m_lm"
	done
	#------------ idx loop ----
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "3" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	#--- configure idx's to members----------------------------------------------
	osx_say "Finished step 3, $site, configuring IDXC members for multi site"

	#--- Check IDXC status ----------------------------------------------
	print_step_bar_from "$R_STEP4" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#4: IDXC [check status]"
	clear_page_starting_from "$R_ROLL"
	check_idxc_status "$m_cm" "$R_STEP4"
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "4" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	sleep 3
	#--- Check IDXC status ----------------------------------------------
	osx_say "Finished step 4, $site, IDXC status check"

	#-- Building generic SHC-------------------------------------------------------
	local start_time=$(date +%s);
	print_step_bar_from "$R_STEP5" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#5: SHC [creating $SHcount generic $SHname's hosts]"
	clear_page_starting_from "$R_ROLL"
	create_splunk_container "$SHname" "$SHcount" "yes" "$R_STEP5"; shc_members_list="$gLIST"
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "5" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	#-- Building generic SHC-------------------------------------------------------
	osx_say "Finished step 5, $site, creating $SHcount SHC generic hosts"

	#-- configure deployer-------------------------------------------------------
	print_step_bar_from "$R_STEP6" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#6: SHC [configure deployer]"
	clear_page_starting_from "$R_ROLL"
	create_splunk_container "$DEPname" "$DEPcount" "no" "$R_STEP6"; dep="$gLIST"
	make_lic_slave "$m_lm" "$dep"
	configure_deployer "$dep" "$LABELname" "$R_STEP6"
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "6" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	#--Starting STEP# configure deployer-------------------------------------------------------
	osx_say "Finished step 6, $site, configuring deployer"

	#-- configure SHC members for multisite-------------------------------------------------------
	#-- sh loop -----
	site_sh_list=`echo $shc_members_list | $GREP -Po '('$SITElocation'\w+\d+)' | tr -d '\r' | tr  '\n' ' '  `
	print_step_bar_from "$R_STEP7" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#7: SHC [configure members for multisite]"
	clear_page_starting_from "$R_ROLL"
	for sh in $shc_members_list; do
		#printf "sh[$sh] SITEloc[$SITElocation] site[$site] m_cm_ip[$m_cm_ip]\n"
		config_sh_for_multisite "$sh" "$loc" "$site" "$m_cm" "$R_STEP7" "$m_mc" "$m_lm"
	done
	#--- sh loop ------
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "7" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	#-- configure SHC members for multisite-------------------------------------------------------
	osx_say "Finished step 7, $site, configuring SHC members for multi site"

	#--- Configure captain & check shc status ---------------------------------------
	print_step_bar_from "$R_STEP8" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#8: SHC [bootstrap captain]"
	clear_page_starting_from "$R_ROLL"
	configure_captain "$shc_members_list" "$R_STEP8"
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "8" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	osx_say "Finished step 8, $site, boot straping captin"

	print_step_bar_from "$R_STEP9" "${ACTIVE_TXT_COLOR}${YELLOW_LEFTHAND_EMOJI} " "STEP#9: SHC [check status]"
	clear_page_starting_from "$R_ROLL"
	check_shc_status "$shc_members_list" "$R_STEP9"
	update_progress_bar "$R_BUILD_SITE" "$C_PROGRESS" "9" "1 2 3 4 5 6 7 8 9" "$(timer "$START_TIME")"
	osx_say "Finished step 9, $site, SHC status check"
	sleep 3
	#--- Configure captain & check shc status ---------------------------------------

	let a_item++		#site array index
done	#/looping thru sites list/

disable_cm_maintenance_mode "$m_cm"

clear_page_starting_from "$R_ROLL"
printf "${LightGreen}Multi-Site Cluster Build Completed!\n"
printf "${ACTIVE_TXT_COLOR}Sites Locations\t:${NC}$sites_loc_list\n"
printf "${ACTIVE_TXT_COLOR}Cluster Master\t:${NC}$m_cm\n"
printf "${ACTIVE_TXT_COLOR}License Master\t:${NC}$lm\n"
printf "${ACTIVE_TXT_COLOR}Master Console\t:${NC}$m_mc\n"
printf "${ACTIVE_TXT_COLOR}Deployers\t\t:${NC}$sites_dep_list\n"
printf "${ACTIVE_TXT_COLOR}SHC Memebers\t:${NC}$sites_sh_list\n"
printf "${ACTIVE_TXT_COLOR}Search Affinity\t:${NC}$sites_aff_list\n"
printf "${ACTIVE_TXT_COLOR}IDXC Memebers\t:${NC}$sites_idx_list\n"
printf "${ACTIVE_TXT_COLOR}RF/SF Factors\t:${NC}$sites_factors_list\n"
docker_status
total_time=$(timer "$START_TIME")
osx_say "Multi site cluster ready. Total time $total_time"

return 0
}	#build_multisite_cluster()
#---------------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------------------
print_stats() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

START="$1"; FUNC_NAME="$2"

END=$(date +%s);
TIME=`echo $((END-START)) | awk '{print int($1/60)":"int($1%60)}'`

echo
#get unique host list  (mpty lines removed)
$GREP "exec" $CMDLOGTXT | awk '{print $5}'|$GREP -v -e '^[[:space:]]*$'|sort -u > tmp1

printf "${LightBlue}   HOST         NUMBER OF CMDS${NC}\n"  >&3
printf "${LightBlue}============    =============${NC}\n"   >&3
for host_name in `cat tmp1`; do
    count=`$GREP "$host_name" $CMDLOGTXT|$GREP  "exec"|wc -l`;
    cmd_list=`$GREP "exec" $CMDLOGTXT| $GREP $host_name| awk '{print $6,$7,$8}'| sed 's/\$//g'|sed 's/\/opt\/splunk\/bin\/splunk //g'| sort | uniq -c|sed 's/\r\n/ /g'|awk '{printf "[%s:%s %s]", $1,$2,$3}' `

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
display_system_banner() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

dockerinfo_ver=`docker info| $GREP 'Server Version'| awk '{printf $3}'| tr -d '\n' `
dockerinfo_cpu=`docker info| $GREP 'CPU' | awk '{printf $2}'| tr -d '\n' `
dockerinfo_mem1=`docker info| $GREP  'Total Memory'| awk '{printf $3}'|sed 's/GiB//g'| tr -d '\n' `
dockerinfo_mem=`echo "$dockerinfo_mem1 / 1" | bc `
#echo "DOCKER: ver:[$dockerinfo_ver]  cpu:[$dockerinfo_cpu]  totmem:[$dockerinfo_mem] "

if [ "$os" == "Darwin" ]; then
        cores=`sysctl -n hw.ncpu`
		kern_ver=`system_profiler SPSoftwareDataType|grep "Kernel Version" |awk '{print $3,$4}'`
	#	os_banner="Detected MacOS [System:$sys_ver Kernel:${Yellow}$kern_ver${NC}]"

elif [ "$os" == "Linux" ]; then
        cores=`$GREP -c ^processor /proc/cpuinfo`
fi

printf "${White}${DOLPHIN1_EMOJI}${NC}[ver:$dockerinfo_ver cpu:$dockerinfo_cpu mem:${dockerinfo_mem}GB] ${White}${COMPUTER_EMOJI}${NC} [$kern_ver cores:$cores] ${White}${OPTICALDISK_EMOJI}${NC}[$DEFAULT_SPLUNK_IMAGE] ${White}${YELLOWBOOK_EMOJI}LogLevel:${NC}[$loglevel] ${White}${TIMER_EMOJI}Timer:[$set_timer]${NC}\n"

return 0
}	#end display_system_banner()
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
	printf "Already logged in..\n"
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

local pid="$1"
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
image_name="$1"
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
cached=`docker images | $GREP $image_name`
if [ -z "$cached" ]; then
	t_start=$(date +%s)
      	#printf "    ${Purple}$image_name:${NC}["
      	printf "Downloading ${Purple}$image_name${NC}:["
	check_status=""
      	#(docker pull $hub$image_name >/dev/null) &
      	(docker pull $hub$image_name > "tmp.$$") &
	background_pid=`ps xa|$GREP "docker pull $hub$image"| awk '{print $1}'`
	spinner $background_pid
	check_status=`$GREP -i "Digest" tmp.$$`

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
extract_current_cursor_position () {
    export $1
    exec < /dev/tty
    oldstty=$(stty -g)
    stty raw -echo min 0
    echo -en "\033[6n" > /dev/tty
    IFS=';' read -r -d R -a pos
    stty $oldstty
    eval "$1[0]=$((${pos[0]:2} - 2))"
    eval "$1[1]=$((${pos[1]} - 1))"
}	#end extract_current_cursor_position()
#---------------------------------------------------------------------------------------------------------------

#---------------------------------------------------------------------------------------------------------------
download_demo_image() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

clear
#-----------show images details
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> DOWNLOAD DEMO IMAGES"
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}" " -- SELECTED AVIALABLE IMAGES FROM [$SPLUNK_DOCKER_HUB] -- "

print_step_bar_from "$R_STEP2" "${BoldWhiteOnBlue}" "        Image%-30s Created%-7s Size%-12s Author%-21s${NC}"
clear_page_starting_from "$R_STEP3"


#REPO_DEMO_IMAGES="demo-azure demo-dbconnect demo-pci"	#DEBUG
counter=1;gSplit_col=0; x=$R_STEP3; y=0
extract_current_cursor_position pos1; x=${pos1[0]};  y=${pos1[1]}

#count=`docker images --format "{{.ID}}" | wc -l`
for image_name in $REPO_DEMO_IMAGES; do
	curr_image="$image_name"
    #printf "${Purple}%-2s${NC}) ${Purple}%-40s${NC}" "$counter" "$image_name"
	image_name="$SPLUNK_DOCKER_HUB/sales-engineering/$image_name"
#	echo "cached[$cached]\n"
	created=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $7,$8}'`
    if [ -n "$created" ]; then
        author=`docker inspect $image_name |$GREP  -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
        #printf "%-12s %-7s %-10s ${NC}\n" "$created" "$size" "$author"
    else
		created="NOT CACHED!"
        #printf "${DarkGray}NOT CACHED! ${NC}\n"
    fi
	#echo "(${pos1[0]} $gsplit_col)"
		#echo "(${pos1[0]} $gsplit_col)"
	printf "${purple}%-2s${nc}) ${purple}%-40s %-12s %-7s %-10s  ${nc}\n" "$counter" "$curr_image" "$created" "$size" "$author"
#stty -echo; echo -n $'\e[6n'; read -d R x; stty echo; echo ${x#??}

	#printf "($x,$y)${purple}%-2s${nc}) ${purple}%-40s %-12s  ${nc}\n" "$counter" "$curr_image"
	extract_current_cursor_position pos1; x=${pos1[0]};  y=${pos1[1]}
#	echo "$x $y"
    let counter++
	update_progress_bar "$R_STEP1" "$C_PROGRESS" "$curr_image" "$REPO_DEMO_IMAGES"
	clear_from_if_screen_ended "$R_STEP3" "p"
#	if [ "${pos1[0]}" -ge "10" ]; then
	#		tput cup ${pos1[0]} ${pos1[1]}
#			tput cup 4 40
#		fi


done
gSplit_col=0
echo
printf "${BrownOrange}${BULB_EMOJI} Access to splunk registery is required. You will be prompted if your O2 creds are not cached (see ~/.docker/daemon.json)${NC}\n\n"
login_to_splunk_hub

#build array of images list
declare -a list=($REPO_DEMO_IMAGES)
choice=""
read -p $'Choose number to download. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice

if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi
if [ -z "$choice" ]; then
	choice=$(seq 1 $counter)		#All is selected
	printf "${DONT_ENTER_EMOJI}${LightRed} WARNING! You are about to download ALL avialable demo images..\n"
    printf "This operation may take a long time. Make sure you have enough disk-space...${NC}\n"
	read -p "Are you sure? [Y/n]? " answer
	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
        printf "${Yellow}Downloading all demo image(s)...\n${NC}"
	fi
fi
selected_count=`echo $choice| wc -w | tr -d '[[:space:]]' `
print_step_bar_from "$R_STEP1" "${ACTIVE_TXT_COLOR}" "   -- RETRIEVING [$selected_count]..."; printf "\n"
update_progress_bar "$R_STEP1" "$C_PROGRESS" "" ""
docker_status
clear_page_starting_from "$R_ROLL"

local start_time=$(date +%s);
if [ -n "$choice" ]; then
    printf "${Yellow}Downloading selected demo image(s)...\n${NC}"
	START=$(date +%s)
    for id in `echo $choice`; do
		image_name=(${list[$id - 1]})
		progress_bar_image_download "$image_name"
		docker_status "$(timer "$start_time")"
		update_progress_bar "$R_STEP1" "$C_PROGRESS" "$id" "$choice" "$(timer "$start_time")"

    done
fi

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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> DOWNLOAD 3RD PARTY IMAGES MENU"
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
	created=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $7,$8}'`
        if [ -n "$created" ]; then
        	author=`docker inspect "$image_name" |$GREP -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
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
start_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type="$1"
clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> START $type CONTAINERS"
display_all_containers "$type"

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

if [ -z "$choice" ]; then
	choice=$(seq 1 $count)		#All is selected
fi
local start_time=$(date +%s);
selected_count=`echo $choice| wc -w | tr -d '[[:space:]]' `
clear_page_starting_from "$R_STEP2"
print_step_bar_from "$R_STEP2" "${ACTION_COLOR}${YELLOW_LEFTHAND_EMOJI}  " "STARTING $selected_count CONTAINERS..."; printf "\n"
printf "${Yellow}Starting selected $type containers...\n${NC}"
#printf "${Yellow}Starting all $type containers...\n${NC}"
for id in `echo $choice`; do
	#printf "${Purple} ${list[$id - 1]}:${NC}\n"
	hostname=${list[$id - 1]}
    docker start "$hostname"
	docker_status
	update_progress_bar "$R_STEP2" "$C_PROGRESS" "$id" "$choice" "$(timer "$start_time")"
	clear_from_if_screen_ended "$R_STEP3" "p"
done

#read -p $'\033[1;32mHit <ENTER> to show new status (some change need time to take effect)...\e[0m'
#list_all_containers "$type"

return 0
}	#start_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
create_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> CREATE CONTAINERS"

#count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
clear_page_starting_from "$R_STEP2"
print_step_bar_from "$R_STEP2" "${ACTION_COLOR}${YELLOW_LEFTHAND_EMOJI}  " "CREATING CONTAINERS"; printf "\n"
update_progress_bar "$R_STEP2" "$C_PROGRESS" "" "1"
docker_status

read -p "Enter BASE HOSTNAME (default: $BASEHOSTNAME)?: " basename
if [ -z "$basename" ]; then
        basename=$BASEHOSTNAME
fi
#always convert to upper case before creating
basename=`echo $basename| tr '[a-z]' '[A-Z]'`

read -p "How many hosts to create (default 1)? " count
if [ -z "$count" ]; then
		count=1
fi
local start_time=$(date +%s);
clear_page_starting_from "$R_STEP2"
print_step_bar_from "$R_STEP2" "${ACTION_COLOR}${YELLOW_LEFTHAND_EMOJI}  " "CREATING $count CONTAINERS"; printf "\n"
update_progress_bar "$R_STEP2" "$C_PROGRESS" "" "1" "$(timer "$start_time")"
create_splunk_container "$basename" "$count" "yes" "$R_STEP2"  # ; members_list="$gLIST"
#display_all_containers "$type"
docker_status

return
}	#create_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
stop_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type="$1"
clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> STOP $type CONTAINERS"
display_all_containers "$type"

count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
	printf "No $type container found!\n"
        return 0;
fi
local start_time=$(date +%s);
#build array of containers list
declare -a list=($(docker ps -a --filter name="$type" --format "{{.Names}}" | sort | tr '\n' ' '))
#list_str=`printf '%s ' "${list[@]}"`	#convert array to str for update_progress_bar below

choice=""
read -p $'Choose number to stop. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -z "$choice" ]; then
	choice=$(seq 1 $count)		#All is selected
fi
local start_time=$(date +%s);
selected_count=`echo $choice| wc -w | tr -d '[[:space:]]' `
clear_page_starting_from "$R_STEP2"
print_step_bar_from "$R_STEP2" "${ACTION_COLOR}${YELLOW_LEFTHAND_EMOJI}  " "STOPPING $selected_count CONTAINERS..."; printf "\n"
printf "${Yellow}Stopping selected $type containers...\n${NC}"
#printf "${Yellow}Stopping all $type containers...\n${NC}"
for id in `echo $choice`; do
	#printf "${Purple} ${list[$id - 1]}:${NC}\n"
	hostname=${list[$id - 1]}
    docker stop "$hostname"
	docker_status
	update_progress_bar "$R_STEP2" "$C_PROGRESS" "$id" "$choice" "$(timer "$start_time")"
	clear_from_if_screen_ended "$R_STEP3" "p"
done
#	docker stop $(docker ps -a --filter name="$type" --format "{{.Names}}" | tr '\n' ' ')
#read -p $'\033[1;32mHit <ENTER> to show new status (some change need time to take effect)...\e[0m'
#list_all_containers "$type"

return 0
}	#stop_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
delete_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type="$1"

clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> DELETE $type CONTAINERS"
display_all_containers "$type"
#printf "\n"

count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
        printf "No $type containers found!\n"
        return 0;
fi
local start_time=$(date +%s);
#build array of containers list
declare -a list=($(docker ps -a --filter name="$type" --format "{{.Names}}" | sort | tr '\n' ' '))

choice=""
read -p $'Choose number to delete. You can select multiple numbers <\033[1;32mENTER\e[0m:All \033[1;32m B\e[0m:Go Back> ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi

if [ -z "$choice" ]; then
	choice=$(seq 1 $count)		#All is selected
fi
selected_count=`echo $choice| wc -w | tr -d '[[:space:]]' `
clear_page_starting_from "$R_STEP2"
print_step_bar_from "$R_STEP2" "${ACTION_COLOR}${YELLOW_LEFTHAND_EMOJI}  " "DELETING $selected_count CONTAINERS..."; printf "\n"
printf "${Yellow}Deleting selected $type containers...\n${NC}"
#printf "${Yellow}Stopping all $type containers...\n${NC}"
for id in `echo $choice`; do
	#printf "${Purple} ${list[$id - 1]}:${NC}\n"
	hostname=${list[$id - 1]}
    #docker stop "$hostname"
    docker rm -v -f "$hostname"
	docker_status
	update_progress_bar "$R_STEP2" "$C_PROGRESS" "$id" "$choice" "$(timer "$start_time")"
	clear_from_if_screen_ended "$R_STEP3" "p"
done


#read -p $'\033[1;32mHit <ENTER> to show new status (some change need time to take effect)...\e[0m'
#list_all_containers "$type"

return 0
}       #end delete_containers()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_all_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"

type="$1"		#container type (ex DEMO|WORKSHOP, 3RDPARTY, empty for ALL)
tagged="$2"		#hosts to be tagged during display
icon="$3"		#icon to be used for tagging during display

#curl http://169.254.169.254/latest/meta-data/public-hostname| sed 's/aws.com/aws.com \n/g'

### DONT CLEAR SCREEN HERE ####		###DONOT ADD TITLE BARS###

if [ "$AWS_EC2" == "YES" ]; then
	rm -fr aws_eip_mapping.tmp
	for i in `curl -s http://169.254.169.254/latest/meta-data/public-hostname| sed 's/aws.com/aws.com \n/g' `; do
		external_ip=`dig +short $i`
		echo  "$external_ip $i"  >> aws_eip_mapping.tmp
	done
fi
print_step_bar_from "$R_STEP2" "${BoldWhiteOnBlue}" "Host(container)%-7s State%-4s Splunkd%-1s Ver%-2s Docker IP%-5s Image%-15s     URL%-13s${NC}"
clear_page_starting_from "$R_STEP3"

ctr=0
hosts_sorted=`docker ps -a --format {{.Names}}| egrep -i "$type"| sort`

for host in $hosts_sorted ; do
    let ctr++	#container display counter (starts at zero now that we have special DOCKER-MONITOR)
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
    #imagename=`docker ps -a --filter id="$id" --format "{{.Image}}" | cut -d'/' -f2-3`  #remove repository name
    imagename=`docker ps -a --filter id="$id" --format "{{.Image}}"|rev| cut -d'/' -f1|rev`  #img only
    splunkd_ver=`docker exec "$hostname" /opt/splunk/bin/splunk version 2>/dev/null | awk '{print $2}'`
    host_line[$ctr]="$bind_ip"
    if [ "$AWS_EC2" == "YES" ]; then
		eip=`$GREP "$bind_ip" aws_eip_mapping.tmp | awk '{print $2}'`
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
	fmt_ctr="%-2s"
	if ( compare "$tagged" "$hostname"  ); then
		fmt_hostname="${DONT_ENTER_EMOJI}${DarkGray} %-18s"
		hoststate="${DarkGray} ** ${NC}"
        splunkstate="${DarkGray} ** ${NC}"
		#splunkd_ver="${DarkGray}N/A"
		#internal_ip=""
		#imagename=""
	else
		fmt_hostname="%-20s"
	fi

	fmt_hoststate="%-18b"
	fmt_splunkstate="%-18b"
	fmt_splunkver="%-6s"
	fmt_bind_ip="%-12s"
	fmt_internal_ip="%-12s"
	fmt_imagename="%-20s"
	fmt_eip="%-30s"

    if ( compare "$host_name" "DEMO" ) || ( compare "$host_name" "WORKSHOP" ) ; then
        	printf "${LightCyan}$fmt_ctr) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$ctr" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"
   	elif ( compare "$hostname" "3RDP" ); then
			open_ports=`docker port $hostname|$GREP -Po "\d+/tcp|udp"|tr -d '\n'| sed 's/tcp/tcp /g' `
        	printf "${LightPurple}$fmt_ctr) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$ctr" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$open_ports"
		#for y in $open_ports; do printf "%80s\n" "$y"; done

    elif ( compare "$hostname" "DEP" ); then
        	printf "${LightBlue}$fmt_ctr) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$ctr" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"

    elif ( compare "$hostname" "CM" ); then
        	printf "${LightBlue}$fmt_ctr) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$ctr" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"

    elif ( compare "$hostname" "MC" ); then
        	printf "${LightBlue}$fmt_ctr) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$ctr" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"

    else 	###generic
        	printf "${LightBlue}$fmt_ctr) $fmt_hostname $fmt_hoststate $fmt_splunkstate $fmt_splunkver $fmt_internal_ip $fmt_imagename $fmt_eip ${NC}" \
			"$ctr" "$hostname" "$hoststate" "$splunkstate" "$splunkd_ver" "$internal_ip" "$imagename" "$eip"
   	fi

  	if [ -z "$bind_ip" ]; then
       printf "${Red}<NOT BUILT BY THIS SCRIPT!${NC}\n"
    else
        printf "${NC}\n"
    fi

	clear_from_if_screen_ended "$R_STEP2" "p"
done

printf "count: %s\n" $ctr
local timer
local TIME_END=$(date +%s);
timer=`echo $((TIME_END - TIME_START)) | awk '{print int($1/60)":"int($1%60)}'`
docker_status "$timer"

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
#---------------------------------------------------------------------------------------------------------------
list_all_containers() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type="$1"         #container type (ex DEMO, 3RDPARTY, empty for ALL)

clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> LIST $type CONTAINERS"
print_step_bar_from "$R_STEP1" "${ACTION_COLOR}" "   -- LISTING CONTAINERS -- "
display_all_containers "$type" "$tagged"
count=$(docker ps -a --filter name="$type" --format "{{.ID}}" | wc -l)
if [ $count == 0 ]; then
        printf "\nNo $type container to list!\n"
        return 0
fi

return 0
}       #end list_all_containers()
#---------------------------------------------------------------------------------------------------------------


#### IMAGES ########

#---------------------------------------------------------------------------------------------------------------
change_default_splunk_image() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function will set the splunk version to use for building containers.

clear
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> MANAGE IMAGES -> CHANGE DEFAULT SPLUNK IMAGE MENU"
printf "\n\n"

#count=`wc -l $CMD`

printf "${Blue}Retrieving list from: [https://hub.docker.com/u/splunknbox/]...\n${NC}"
CMD="docker search splunknbox"; OUT=`$CMD`
#printf "$OUT" #| awk '{printf $1}'

retrieved_images_list=`printf "$OUT"|$GREP -v NAME|awk '{print $1" "}'| sort -r | tr -d '\n' `
declare -a list=($retrieved_images_list)
printf "${BoldWhiteOnRed}             IMAGE NAME%-22s CREATED%-7s SIZE%-15s AUTHOR%-20s${NC}\n"
counter=1
#count=`docker images --format "{{.ID}}" | wc -l`
for image_name in $retrieved_images_list; do
	if [ "$image_name" == "$DEFAULT_SPLUNK_IMAGE" ]; then
    	printf "${Purple}%-2s${NC})${YELLOW_LEFTHAND_EMOJI} ${Purple}%-40s${NC}" "$counter" "$image_name"
	else
    	printf "${Purple}%-2s${NC})  ${Purple}%-40s${NC}" "$counter" "$image_name"
	fi
	created=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $4,$5,$6}'`
	size=`docker images "$image_name" | $GREP -v REPOSITORY | awk '{print $7,$8}'`
    if [ -n "$created" ]; then
        author=`docker inspect $image_name |$GREP -i author| cut -d":" -f2|sed 's/"//g'|sed 's/,//g'`
        printf "%-12s %-7s %-10s ${NC}\n" "$created" "$size" "$author"
    else
        printf "${DarkGray}NOT CACHED! ${NC}\n"
    fi
    let counter++
	clear_from_if_screen_ended "$R_STEP2" "p"
done
#display_all_images "DEMO"
count=0
echo
choice=""
read -p $'Choose a number <\033[1;32mB\e[0m:Go Back>: ' choice
if [ "$choice" == "B" ] || [ "$choice" == "b" ]; then  return 0; fi
if [ -n "$choice" ]; then
		START=$(date +%s)
		image_name=(${list[$choice - 1]})
		progress_bar_image_download "$image_name"
		DEFAULT_SPLUNK_IMAGE="$image_name"
		printf "${BrownOrange}${WARNING_EMOJI} Subsequent container builds (except DEMOs) will use the new splunk image ${Yellow}[$image_name]${NC}\n"
	else
		return 0
fi

return 0
}	#end change_default_splunk_image()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
remove_images() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
clear
type="$1"
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> REMOVE $type IMAGES MENU"
printf "\n"
printf "Current list of all $type images downloaded on this system:\n"
display_all_images "$type"
echo

if [ "$type" == "3RDP" ]; then
	id_list=$(docker images  -a| $GREP -v "REPOSITORY" | egrep -iv "DEMO|WORKSHOP"| $GREP -iv "splunk"| awk '{print $3}'| tr '\n' ' ')
elif [ "$type" == "DEMO" ]; then
	id_list=$(docker images  -a| $GREP -v "REPOSITORY" | egrep -i "DEMO|WORKSHOP" | awk '{print $3}'| tr '\n' ' ')
else
	id_list=$(docker images  -a| $GREP -v "REPOSITORY" | awk '{print $3}'| tr '\n' ' ')
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
        	imagename=`docker images|$GREP  ${list[$id -1]} | awk '{print $1}'`
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
list_all_images() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
type="$1"
clear
if [ -z "$type" ]; then
	p_type="*"
fi
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> SHOW $type IMAGES"
print_step_bar_from "$R_STEP1" "${ACTION_COLOR}" "   -- LISTING IMAGES TYPE [$p_type] -- "
#printf "Current list of $type images downloaded on this system:\n"
display_all_images "$type"
count=`docker images --format "{{.ID}}" | wc -l`
if [ $count == 0 ]; then
        printf "\nNo $type images to list!\n"
        return 0
fi

return 0
}	#end list_all_images()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
display_all_images() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function displays custom view all images downloaded.

type="$1"		#image type to display

local TIME_START=$(date +%s);
#clean up the anoying "none" images first
#docker rmi $(docker images -a | grep "^<none>" | awk '{print $3}')
id_list=""
count=`docker images --format "{{.ID}}" | wc -l`
if [ $count == 0 ]; then
        printf "\nNo $type images to list!\n"
        return 0
fi

#-----------------
if [ "$type" == "3RDP" ]; then
	id_list=$(docker images  -a|$GREP -v "REPOSITORY"|sort|egrep -iv "DEMO|WORKSHOP"|$GREP -iv "splunk"|awk '{print $3}'| tr '\n' ' ')
elif ( compare "$type" "DEMO" ) || (compare "$type" "WORKSHOP" ); then
	id_list=$(docker images  -a| $GREP -v "REPOSITORY" |sort| egrep -i "DEMO|WORKSHOP" | awk '{print $3}'| tr '\n' ' ')
else	#show all types
	id_list=$(docker images  -a| $GREP -v "REPOSITORY"|sort | awk '{print $3}'| tr '\n' ' ')
fi
#-----------------

print_step_bar_from "$R_STEP2" "${BoldWhiteOnBlue}" "        Image%-12s Tag%-8s Create%-7s Size%-8s Repository%-21s${NC}"
clear_page_starting_from "$R_STEP3"

count=0
for id in $id_list; do
    let count++
    imagename=`docker images|$GREP  $id | awk '{print $1}' | rev | cut -d"/" -f1 | rev`
    repo=`docker images|$GREP  $id | awk '{print $1}' | cut -d"/" -f1 `
    imagetag=`docker images|$GREP  $id | awk '{print $2}'`
    created=`docker images|$GREP  $id | awk '{print $4,$5,$6}'`
    size=`docker images|$GREP  $id | awk '{print $7,$8}'`
    sizebytes=`docker images|$GREP  $id | awk '{print $7,$8}'`
	fmt_i="%-2s"; fmt_imagename="%-20s"; fmt_imagetag="%-10s";fmt_created="%-15s";fmt_size="%-12s";fmt_repo="%-12s"
    printf "${LightCyan}$fmt_i) $fmt_imagename $fmt_imagetag $fmt_created $fmt_size $fmt_repo ${NC}\n" \
			"$count" "$imagename" "$imagetag" "$created" "$size" "$repo"

	clear_from_if_screen_ended "$R_STEP3" "p"
done

printf "count: %s\n\n" $count
local timer
local TIME_END=$(date +%s);
timer=`echo $((TIME_END - TIME_START)) | awk '{print int($1/60)":"int($1%60)}'`
docker_status "$timer"

return 0
}	#end display_all_images()
#---------------------------------------------------------------------------------------------------------------

###### MISC #####
#--------------------------------------------------------
function osx_say(){
#expermintal and works on MacOS only.
string="$1"

if [ -z "$macspeak_vol" ]; then
		macspeak_vol="$MACSPEAK_VOL"
fi
osascript -e 'set volume output volume 70'

#printf "\033[1;32m$string\033[0m\n"
if [ "$set_macspeak" == "true" ] && [ "$(uname)" == "Darwin" ]; then
    say "[[volm 0.$((RANDOM%$macspeak_vol+1))]] $string"
else
	return
fi

}	#end function osx_say()
#--------------------------------------------------------

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
screen_header "${HEADER_COLOR}" "Splunk N' A Box v$GIT_VER: ${Yellow}MAIN MENU -> WIPE CLEAN SPLUNK N' BOX SYSTEM MENU"
printf "\n\n\n"
printf "${DONT_ENTER_EMOJI}${LightRed} WARNING! WARNING! WARNING!${NC}\n"
printf "${LightRed}You are about remove IP aliases, delete all containers, delete all images and remove all volumes! ${NC}\n"
printf "${LightRed}Use this option only if you want to return the system to a clean state! ${NC}\n"
printf "${LightRed}Restarting the script will recreate every thing again! ${NC}\n"
printf "\n"
read -p "Are you sure you want to proceed? [y/N]? " answer
if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
    printf "${Yellow}Stopping all containers...${NC}\n"
	docker stop $(docker ps -aq)
    printf "\n"
	printf "${Yellow}Deleting all docker containers...${NC}\n"
    docker rm -f $(docker ps -a --format "{{.Names}}");
	printf "\n"
    printf "${Yellow}Removing all docker images...${NC}\n"
	docker rmi -f $(docker images -q)
	printf "\n"
	printf "${Yellow}Removing all dokcer volumes (including dangling)...${NC}\n"
	docker volume rm $(docker volume ls -qf 'dangling=true')
    printf "\n"

    printf "${Yellow}Removing all IP aliases...${NC}\n"
	remove_ip_aliases
	printf "\n"

#sudo /Developer/Library/uninstall-devtools --mode=all

	printf "${Red}Removing all dependency packages [brew ggrep pcre bc]? ${NC}\n"
	read -p "Are you sure you want to proceed? [y/N]? " answer
    if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		#remove ggrep, pcre
		brew uninstall "grep pcre bc"

		#remove brew
		/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/uninstall)"
	#	sudo rm -rf /usr/local/Homebrew/
	fi

	printf "\n\n"
    echo -e "Life is good! Thank you for using Splunk N' A Box v$GIT_VER\n"
	printf "Please send feedback to mhassan@splunk.com \n"
	exit
fi

return 0
}	#end wipe_entire_system()
#---------------------------------------------------------------------------------------------------------------
#---------------------------------------------------------------------------------------------------------------
check_for_upgrade() {

tput cup $(($LINES-5)) $(( ( $COLUMNS - 20 )  / 2 ))
printf "Checking online version...\n"

rm -fr $TMP_DIR/online_ver.tmp		#start fresh
wget -qO $TMP_DIR/online_ver.tmp "https://raw.githubusercontent.com/mhassan2/splunk-n-box/master/VERSION.TXT"
online_ver=`cat $TMP_DIR/online_ver.tmp`
colored_online_ver=`echo $online_ver | awk -F '[.-]' '{print "\033[1;33m" $1 "\033[0;33m." $2 "\033[1;31m-" $3}'`
#new=`awk -v n1=$online_ver -v n2=$GIT_VER 'BEGIN {if (n1>n2) print ("Y");}'  `

#online_ver="5.1-15";GIT_VER="5.1-15"
n1=`echo $online_ver|sed 's/\.//g'|sed 's/-//g'`
n2=`echo $GIT_VER|sed 's/\.//g'|sed 's/-//g'`
if [ "$n1" -gt "$n2" ]; then
    upgrade="Y"
else
    upgrade="N"
	tput cup $(($LINES-5)) $(( ( $COLUMNS - 20 )  / 2 ))
	printf "                             \n"

fi
#upgrade=Y
#echo "$upgrade"
if [ "$upgrade" == "Y" ] && [ -n "$GIT_VER" ] && [ -n "$online_ver" ]; then
	#tput cup $LINES $(( ( $COLUMNS - ${#MESSAGE[10]} )  / 2 ))
#    tput cup $row $col                 #set x and y position
#	tput cup $(($LINES - 3 )) 0
#	tput el          # clear to the end of the line

	tput cup $(($LINES-5)) $(( ( $COLUMNS - 40 )  / 2 ))
	printf "Newer version [$colored_online_ver\033[0m] is available "
	read -p "Upgrade? [Y/n] " answer
	if [ -z "$answer" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
	#	tput cup $LINES 0
		tput cup $(($LINES-5)) $(( ( $COLUMNS - 40 )  / 2 ))
		printf "Downloading [$PWD/${0##*/}] >> ${NC}"
		tput cup $(($LINES-5)) $(( ( $COLUMNS - 70 )  / 2 ))
		progress_bar_pkg_download "curl -O https://raw.githubusercontent.com/mhassan2/splunk-n-box/master/${0##*/}"
		sleep 2
		#curl --max-time 5 -O https://raw.github.com/mhassan2/splunk-n-box/master/${0##*/}
		chmod 755  ${0##*/}   	#set x permission on splunknbox.sh
	#	./$(basename $0) && exit  # restart the script
		tput cup $(($LINES-4)) $(( ( $COLUMNS - 40 )  / 2 ))
		printf "${Yellow}Please restart the script!${NC}                          \n\n"
		exit

	fi
fi

return 0
}	#end check_for_upgrade
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
tput civis      #cursor invisible

COLUMNS=$(tput cols)
LINES=$(tput lines)
#echo "cols:$COLUMNS"
#echo "lines:$LINES"
colored_git_version=`echo $GIT_VER|awk -F '[.-]' '{print "\\\033[1;33m"$1"\\\033[0;33m."$2"\\\033[1;31m-" $3"\\\033[0m"}'`

#Dont prompt for upgrade if we cannot get GIT_VER ( missing ggrep)
if [ -z "$GIT_VER" ]; then
	upgrade="N"
	colored_git_version="${LightRed}*UNKNOWN*${NC}"
fi
#normal screen size 127x28
if [ "$COLUMNS" -lt "127" ] || [ "$LINES" -lt "28" ]; then
	size_warning_msg="${LightRed}For best result please expand your terminal to FULL screen [currently:$COLUMNS"x"$LINES]${NC}"
	osx_say "Your terminal settings is not ideal. Please expand it to full mode. Please set colors to dark background"
else
	size_warning_msg=""
fi

MESSAGE[1]=""
MESSAGE[2]="Welcome to Splunk N\' A Box v${colored_git_version}${NC}"
MESSAGE[3]="Splunk Docker Orchestration Tool"
MESSAGE[4]=""
MESSAGE[5]="https://github.com/mhassan2/splunk-n-box"
MESSAGE[6]="https://www.splunk.com/en_us/legal/splunk-software-license-agreement.html"
MESSAGE[7]="This script is licensed under Apache 2.0 All rights reserved Splunk Inc 2005-2018"
MESSAGE[8]="$size_warning_msg"

# Calculate x and y coordinates so that we can display $MESSAGE
# centered on the screen
x=$(( $LINES / 2 ))                  #centered on the screen
num_of_msgs=${#MESSAGE[@]}
let last_msg=$num_of_msgs+1
z=0

#last msg is dynamically calculated based on array size
MESSAGE[$last_msg]="${NC}Hit ${Yellow}<ENTER>${NC} to accept Splunk software license agreement & continue"

#-show splunknbox logo only if imgcat is installed & and jpeg file exist
# Otherwise skip with no feedback -----
condition=$(which imgcat 2>/dev/null | $GREP -v "not found" | wc -l)
if [ $condition != "0" ] && [ -e img/splunknbox_logo.png ]; then
	col=$(( ( $COLUMNS - 13 )  / 2 )); row=$(($x - 9)); tput cup $row $col
	imgcat img/splunknbox_logo.png
fi

#----------------------------------------------------------------------
#Center msgs based on length (without escape codes) & screen size
for (( i=x; i <= (x + $num_of_msgs + 1); i++)); do
        let z++
		#strip color codes from in len calculations
		msg=`printf "%s " "${MESSAGE[$z]}"`
		msg_line=$(echo $msg| sed $'s,\\\\033\\[[0-9;]*[a-zA-Z],,g'|tr -d '\n')
		msg_len=`echo $msg_line	|wc -c| tr -d '[:space:]'`

        col=$(( ( $COLUMNS - $msg_len )  / 2 ))
		row=$(($i - 4))
        tput cup $row $col                 #set x and y position
        tput bold   #set reverse video mode

		#last line #10 should print at end of screen
		if [ "$z" == "$last_msg" ]; then
			check_for_upgrade
			tput cup $(($LINES-1)) $(( ( $COLUMNS - $msg_len )  / 2 ))
		fi
		printf "$msg"

done


# Just wait for user input...
read -p "" readKey
# Start cleaning up our screen...
tput clear
tput sgr0	#reset terminal (doesn't always work)
tput rc
tput cnorm   	#cursor visible

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
#---------------------------------------------------------------------------------------------------------------
redraw() {
_debug_function_inputs  "${FUNCNAME}" "$#" "[$1][$2][$3][$4][$5]" "${FUNCNAME[*]}"
#This function will execute when the term is resized
tput setab 0
read ROWS COLUMNS < <(stty size)
#echo "$ROWS $COLUMNS"
}
#---------------------------------------------------------------------------------------------------------------

#<<<<<<<<<<<<<----------   MAIN BEGINS     ---------->>>>>>>>>>>>

#---------------------------------------------------------------------------------------------------
#The following must start at the beginning for the code since we use I/O redirection for logging
#http://stackoverflow.com/questions/8455991/elegant-way-for-verbose-mode-in-scripts/8456046
loglevel="$DEFAULT_LOG_LEVEL"
maxloglevel=7	 #The highest loglevel we use / allow to be displayed.

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.
output_file=""
checks_on_start="true"
del_on_start="false"
opt=""
macspeak_vol="0"; set_macspeak="false"
set_timer="$DEFAULT_TIMER"
while getopts "h?l:dsg:c:t:f:a :" opt; do
    case "$opt" in
    l)  loglevel="$OPTARG";;
   	s)  checks_on_start="false";;
   	d)  del_on_start="true";;
    g)  graphics="$OPTARG";;
    c)  cluster="$OPTARG";;
    t)  set_timer="$OPTARG";;
    a)  set_macspeak="true"; macspeak_vol="$OPTARG";;

	f)  output_file="$OPTARG";;
    h)
		printf "Usage:\n"
		printf "\t-s \t\tSkip startup checks if all requirements are satisfied.${LightRed}**Use with caution***${NC}\n"
		printf "\t-d \t\tDelete all containers on startup.${LightRed}**Use with caution***${NC}\n"
		printf "\t-l [3|4|5|6]\tlog level (default $DEFAULT_LOG_LEVEL)\n"
		printf "\t-t [sec]\tpause time after each container creation (default 15 or 30 sec)\n"
		printf "\t-a [vol]\tAnnounce progress on MacOS for cluster build\n"
        printf "\t-f [filename]\tSet log file name\n"
        exit 0
        ;;
    esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift
#echo "loglevel='$loglevel'   output_file='$output_file'    Leftovers: $@"
#echo "1------[$opt][$OPTARG] [${loglevel}]-----maxloglevel[$maxloglevel]"

#Start counting at 2 so that any increase to this will result in a minimum of file descriptor 3.  You should leave this alone.
#Start counting from 3 since 1 and 2 are standards (stdout/stderr).
for l in $(seq 3 $loglevel); do
    (( "$l" <= "$maxloglevel" )) && eval exec "$l>&2"  #Don't change anything higher than the maximum loglevel allowed.
done

#From the loglevel level one higher than requested, through the maximum;
for l in $(seq $(( loglevel+1 )) $maxloglevel ); do
    (( "$l" > "2" )) && eval exec "$l>/dev/null" #Redirect these to bitbucket, provided that they don't match stdout and stderr.
done
#DEBUG
#printf "%s\n" "This message is seen at verbosity level 3 and above." >&3
#printf "%s\n" "This message is seen at verbosity level 4 and above." >&4
#printf "%s\n" "This message is seen at verbosity level 5 and above." >&5
#exit
#------------------

#delete log files on restart
rm  -fr $CMDLOGBIN $CMDLOGTXT
reset
tput setab 0
clear
trap redraw WINCH
detect_os						#ggrep OSX is set here.Should be the first routine
detect_ver

if [ "$checks_on_start" == "true" ];then
	startup_checks				#contains ggrep install if missing OSX (critical command)
fi
if [ "$del_on_start" == "true" ]; then
	printf "\n"
	printf ${Yellow}"Deleting all containers....\n${NC}"
	sleep 2
	docker rm -vf $(docker ps -aq)
fi
#if [ "$cluster" == "1" ];then
#	create_standalone_idxc "AUTO"
#elif [ "$cluster" == "2" ];then
#	create_standalone_shc "AUTO"
#elif [ "$cluster" == "3" ];then
#	build_singlesite_cluster "AUTO"
#elif [ "$cluster" == "4" ];then
#	build_multisite_cluster "AUTO"
#fi
display_welcome_screen		#ggrep must installed otherwise ver check will fail
main_menu_inputs


#<<<<<<<<<<<<<----------   MAIN ENDS     ---------->>>>>>>>>>>>

##### EOF #######
