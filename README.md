**See  _Splunk-n-box-screens.docx_  for screenshots!**

##Introduction:

Have you ever wanted to create a multi-site cluster environment in your lab but you don’t have the resources for it? Have you ever wondered how does bucket replication translates on the file system level? Have you ever wanted to create portable Splunk classroom but it is cost prohibitive? How about changing critical configuration without worrying about messing up your production environment?
If you are like me; you must have dealt with similar challenges.


Like with most people, you probably attempted to solve the problem by either throwing more hardware at it, or by using some sort of VM technology that does not scale well without additional resources and cost. Well, I have a solution for you! But before that I would like to welcome you to the world of docker, the game changer that brought micro services to reality. Imagine that with a click of a button you are able to create 3-sites cluster, each location running 3-SHs and 10-IDXs. Or maybe just instantly create a portable lab environment for testing or training purposes. 
You may have heard of docker, or you may even experiment with it trying to figure out how can I use it to help my Splunk needs. But learning docker technology by itself is not helpful unless its used in a context of specific app like Splunk. To help my customers (and myself) I have created a wrapper bash script (around 1200 lines) to manage Splunk instances builds. *The script will allow you to create a pre-configured large number of Splunk infrastructure components without having to learn a single docker command and with minimal resources requirements (CPU, memory, HD space).*

In my small test environment I was able to quickly bring upward of 40+ Splunk docker containers for a classroom lab using low powered Intel NUC device (i3 16GB ram, 128G SSD). What’s really impressive about docker is the resouce utilization on docker-host was extremely tiny compaired to a VM based build. I need to emphasize that I have not tested my script under heavy load (either user traffic or data ingestion), however, I believe is just a matter of sizing the hardware appropriately.

##Script feature list:

- Extensive Error checking when configuring the containers
- Adaptive load control (throttling if exceeds 4xcores) during cluster build
- Built-in dynamic host names and IPs allocation
- Automatically create & configure large number of Splunk hosts very fast
- Different levels of logging (show docker commands executed)
- Complete multi and single site cluster builds including CM and DEP servers
- Manual and auto (standard configurations)
- Modular design that can easily be converted to a higher-level language like python
- Custom login screen (helpful for lab & Search Parties scenarios)
- Low resources requirements
- Eliminate the need to learn docker (but you should)
- MAC OSX support


##Where to get it?

I have posted the source code on github https://github.com/mhassan2/splunk-n-box

Please download and install in your lab. The script was tested on Ubuntu 16.04. I am guessing running on equivalent Linux distribution will not be a problem. Windows and OSX do not support c-blocks natively, therefore there is an additional layer of virtualization (Oracle VBOX to be specific) required, which really defeat the purpose of micro servers concept. Additionally the scripts heavily utilizes NATing to allow Splunk containers to be visible to the outside world, which means you probably have to NAT 2-3 times to achieve the same goal using non-Linux host OS.

##How does it work?

Once you have your Ubuntu up and running please follow the instructions for installing docker https://docs.docker.com/engine/installation/linux/ubuntulinux/
Please be aware that Ubunto 14.04 did not work very well for me. There is a bug around mounting docker volumes. Your mileage may vary if you decide to use CentOS or equivalent Linux distribution. For OSX see https://github.com/docker/dcus-hol-2016/tree/master/docker-developer

When the scripts runs for the first time it checks to see if you have any IP aliases available (the range specified in the script). If not; then it will configure IP aliases 192.168.1.100-200. The aliased IPs will be automatically mapped, at container creation time, to the internal docker IP space (172.18.0.0/24). You should be able to point your browser to any NATed IP on port 8000 and that will get you directly to the container. During my research I haven’t seen many people using that technique and they opt for changing the ports or using a proxy docker. My approach is to keep the standard Splunk ports (8000, 8089, 9997,etc) and use iptable NATs to make the containers visible to the outside world.  This will save you a lot of headache when dealing with creating large number of Splunk containers (aka hosts). Running under OSX then I used private network segment 10.0.0.0/24. The assumption is you dont need to NAT to the outside world and evetything will be local to your MAC laptop.

##Splunk image:

I used outcoldman image as basis of this work. But for some reason it was pulled out of docker registry website. You still can get it here:  https://github.com/outcoldman/docker-splunk

Here is his instructions for getting the image (remember to include the trailing dot):


```
git clone https://github.com/outcoldman/docker-splunk.git 
cd docker-splunk/splunk 
docker build --tag="$USER/splunk" .
```

If that doesn’t work for you then try another “splunk” image on the registry https://hub.docker.com/. Or you can make your own-stripped down Splunk image. If there is enough interest I will probably post my own but at this point what’s out there should work.

##Linux installation:
 
For differnt linux distributions/version see:  https://docs.docker.com/engine/installation/

If you want the docker-host be be able to resolve host IPs (optional) install dnsmasq (google for your Linux flavor). 
Change DNSSERVER="192.168.2.100"  to point the caching dns server. This does not work on OSX yet!


##MAC OSX installation:
``` 
Note: 
1. Do not use older boot2docker stuff. If you google OSX docker install you will see references to that every where. DO NOT USE! Starting docker 1.12 Orcale VBOX is no longer used, a new hypervisor is used xhyve.
2. Perfromance on OSX is noticeably less than Linux runs. So be aware that you may not be able to bring up as many containers will similar hardware resources.
 ``` 
 
Install Xcode Command Line Tools: https://hackercodex.com/guide/mac-osx-mavericks-10.9-configuration/
```
xcode-select --install   (this is an optional step. You may not need it)
```

Install docker & Tool box : https://docs.docker.com/engine/installation/mac/


Install brew packages management: http://www.howtogeek.com/211541/homebrew-for-os-x-easily-installs-desktop-apps-and-terminal-utilities

``` 
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

```
brew update
```

Install Gnu grep (ggrep) to get PCRE regex support. The script will not work without it: http://apple.stackexchange.com/questions/193288/how-to-install-and-use-gnu-grep-in-osx

``` 
brew tap homebrew/dupes; brew install grep 
```

Configure docker for maximum CPU and Memory usage. The number of containers you can create is heavily dependant on resource.

```
Click on Docker Icon -> Preference -> General -> slide everthing all the way to the right
```



##Configuration and setup:

You may need to adjust the script to match your network space. Or you can simply use the defaults if your routed network is 192.168.1.0/24. In my lab, the docker-host is 192.168.1.100 it’s also where I ran my dnsmasq (DNS caching server). If you prefer not to use dnsmasq; then just use actual container IPs in your browser. The first container you create will start at 192.168.1.101 and last one will end at 192.168.1.200 (OSX version network used 10.0.0.0/24 ). If you wish to setup your docker-host with permanent IP aliases see this link http://askubuntu.com/questions/585468/how-do-i-add-an-additional-ip-address-to-an-interface-in-ubuntu-14

```shell

#Network stuff
ETH_OSX="lo0"                   #default interface to use with OSX OSX
ETH_LINUX="eno1"                #default interface to use with Linux
GREP_OSX="/usr/local/bin/ggrep"
GREP_LINUX="/bin/grep"

#IP aliases range to create. Must use routed network if you want reach host from outside
#OSX will space will not be routed and just local to the laptop.
#LINUX is routed and hosts can be reached from anywhere in the network
START_ALIAS_LINUX="192.168.1.100";      END_ALIAS_LINUX="192.168.1.200"
START_ALIAS_OSX="10.0.0.100";           END_ALIAS_OSX="10.0.0.200"

DNSSERVER="192.168.2.100"               #if running dnsmasq if used. Set to docker-host machine

#Full PATH is dynamic  based on OS type (see detect_os() )
FILES_DIR="splunk_docker_script_github"  #place anything needs to copy to container here
LIC_FILES_DIR="licenses_files"
VOL_DIR="docker-volumes"
```

##Container host names rules:

When you get comfortable navigating around the options you will soon discover that it is so easy to pop up hosts all the time. Inconsistent hostnames will lead to confusion. That actually happened to me! Therefore I am enforcing standard host naming convention. You have the option to override that behavior in the “manual” mode. But remember the script relies on host names as a way to evaluate the host role. Diverting from the standard disrupts the logic in certain functions [like show_groups() ]. The script will automatically assign a sequence host number next to the base host name. For example in some functions you will be prompted to enter Indexer name; you should enter IDX only. The script will find the next unused sequence number and IP address and use it (example IDX01, IDX02, IDX03,..etc). That logic does not apply to the “site” portion of the hostname. The script will use the following naming convention:
```
IDX : Indexer
SH  : Search Head
DS  : Deployment Server
LM  : License Manager
CM  : Cluster Master
DEP : Search Head Cluster Deployer
HF  : Heavy Forwarder
UF  : Universal Forwarder
```

##How to use:

You have the ability to control verbosity level by using –v switch. I used I/O redirection to control verbosity (and logging level). 

```
create-splunk.sh –v3 
```

Experiment with creating few hosts then point your browser to them. Push the server to the limits to see how many host can you create before your system crashes. I was able to create 80 hosts (4 site-2-site cluster 20IDX 3SH each) on a single Intel NUC SKull device (i7 32GB 1TB SSD). Load avg shot to 20 during the build, but went down to 6 once the cluster stablized. Please be aware that it will take 10+ minutes (depending on number of memebers on the cluster) to reach a stable cluster state.

```Choose option C```

Add license file(s) to your containers. Make sure you have your all your license files in a directory accessible by the script. This option will be overridden if the host becomes a license-slave

```Choose option 6```

The real fun starts on the second clustering-menu. Select any item from the first 1-4 choices then watch the script create everything for you. Once you get familiar with things; then move to the “manual” mode options 5-8. In manual mode you will be able to specify exact hostnames and how many “hosts” to create. Please follow the standard described above. Validate the actions by pointing your browser to any host you create. 


##Navigation:

There are two menu screens the main menu. Here is a brief explanation of important options on the main menu:

`C) Create containers` : Allows you to choose the container name and how many “hosts” to create. Good option if you are to doing a                               search party or just classroom with stand alone Splunk instances.

`D) Delete container`  :  Allows you to delete all containers in the system

`R) Remove all volumes`: Docker does not remove any container artifact when deleted or shutdown. You can clean and save disk space using                          this option.

`4) Show hosts by group`:Useful for displaying categories of the environment by function. It will show all cluster-masters (CM) and possible                          members associated with it. The same goes for Deployer (DEP) servers.

The rest of the options are self-explanatory


###List of functions:
```
echo_logline()
setup_ip_aliases ()
check_load ()
detect_os ()		 ####### NOT USED YET ########
contains()
add_license_file ()
reset_splunk_passwd ()
pausing ()
restart_splunkd ()
display_output ()
host_status ()     ####### NOT USED YET ########
make_lic_slave ()
check_host_exist ()		 ####### NOT USED YET ########
show_all_containers ()
splunkd_status_all ()
show_groups ()
custom_login_screen ()
assign_server_role ()		 ####### NOT USED YET ########
create_single_splunkhost ()
create_generic_splunk ()
create_single_shc ()
create_single_idxc ()
build_single_site ()
build_multi_site_cluster ()
display_menu2 ()
clustering_menu ()
display_menu ()
```


##Note:
There are few optional items (open source) are not part of my work. I added them to the container build for troubleshooting,it’s up to you if you want to install them. You may want to exclude them to keep the container footprint small.

-[screenfetch](http://tuxtweaks.com/2013/12/install-screenfetch-linux/)  : banner screen show host info at ssh login

-bashrc:  customized bash file
