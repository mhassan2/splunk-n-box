The script will allow you to create a pre-configured large number of Splunk infrastructure components without having to learn a single docker command and with minimal resources requirements (CPU, memory, HD space). 

Features highlights:
-Extensive Error checking
-Load control (throttling) if exceeds 4xcores
-Built-in dynamic host names and IP allocation
-Create and configure large number of Splunk hosts very fast
-Different logging levels (show docker commands executed)
-Complete multi and single site cluster builds including CM and DEP servers
-Manual and auto (standard configurations)
-Modular design that can easily be converted to a higher-level language like python
-Custom login screen (helpful for lab & Search Parties scenarios)
-Low resources requirements
-Eliminate the need to learn docker (but you should)


How to use:
The only possible configurations you may need to make are listed below. Or you can simply use the defaults if your routed network is 192.168.1.0/24. In my lab the docker-host is 192.168.1.100 it’s also where I run my dnsmasq caching DNS server. If you don’t want use dnsmasq you; then just use actual IPs in your browser. The container you create will start at 192.168.1.130 and last one will end at 192.168.1.250. If you wish to set your docker-host with permanent IP aliases see this link http://askubuntu.com/questions/585468/how-do-i-add-an-additional-ip-address-to-an-interface-in-ubuntu-14

ETH="eth0"
BASEIP="192.168.1"      #must be routed network. We are using class C here!
BASEOCTET4="129"
START_OCTET4="130"
END_OCTET4="250"
DNSSERVER="192.168.1.100"       #if running dnsmasq on the host machine 192.168.1.100

#SPLUNK_IMAGE="outcoldman/splunk:6.4.2"  #taken offline by outcoldman
SPLUNK_IMAGE="root/splunk"
BASEHOSTNAME="IDX"

STEPS:
You have the ability to control verbosity level by using –v switch. I used I/O redirection to control verbosity (and logging level). 

create-splunk.sh –v3 

Create few hosts then point your browser to test. Push the server to the limits to see how many host can you create before your system crashes.

Choose option C

Add license file(s) to your containers. Make sure you have your all your license file directory is accessible by the script. This option will be overridden if the host becomes a license-slave

Choose option 6


The real fun start on the second clustering-menu, it’s where you will be able to instantly creating the entire environment. Select any item from the first 4 choices and watch the script creating everything for you.
-Once you get familiar with things move on to the manual option (5-8) where you will be able to specify exact hostname and how many “hosts” to create.
-Validate the actions by pointing your browser to any host you create. 

There are few optional items that I add to the container build that is OS related; it’s up to you if you want to install those items. 
-screenfitch  : banner screen show host info at ssh login
-bashrc:  customized bash file


