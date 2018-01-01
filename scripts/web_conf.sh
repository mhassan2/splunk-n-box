#!/bin/bash

#used for testing building web.conf. Run from /opt/splunk/system/local

fullhostname="HOST03"; cluster_label="cluster1"; vip="192.168.1.1"
USERADMIN="admin"; USERPASS="hello"; VERSION="2.9"; SPLUNK_IMAGE="splunknbox/splunk_6.5.1"; container_ip="172.0.0.0"

#LINE1="<font color=\"#867979\">name:    </font><font color=\"#FF9033\"> $hosttxt</font><font color=\"#FFB833\">$hostnum</font>"
LINE1="<font color=\"#867979\">name:    </font><font color=\"#FF9033\"> $fullhostname</font>"
LINE2="<font color=\"#867979\">cluster: </font><font color=\"#FF9033\"> $cluster_label</font>"
LINE3="<font color=\"#867979\">IP:      </font><font color=\"#FF9033\"> $vip</font>"
LINE4="<font color=\"#867979\">User: </font> <font color=\"red\">$USERADMIN</font> &nbsp&nbsp<font color=\"#867979\">Password:</font> <font color=\"red\"> $USERPASS</font></H3><H2></font>"
LINE5="<font color=\"#867979\">Created using Splunk N' Box v$VERSION: [v4.4-23] $SPLUNK_IMAGE]</font>"

#custom_web_conf="[settings]\nlogin_content =<div align=\"right\" style=\"border:1px solid green\"><CENTER>
#<H1>$LINE1<BR/></H1>
#<H1>$LINE2<BR/></H1>
#<H1>$LINE3<BR/>$LINE4 <BR><BR></H1>
#<H4>$LINE5</H4></H2>
#</CENTER>
#</div> <p>This data is auto-generated at container build time (container internal IP=$container_ip)</p>\n"

custom_web_conf="[settings]\nlogin_content =<div align=\"right\" style=\"border:1px solid green\"><CENTER><H1>$LINE1<BR/></H1><H1>$LINE2<BR/></H1><H1>$LINE3<BR/>$LINE4 <BR><BR></H1><H4>$LINE5</H4></H2></CENTER></div> <p>This data is auto-generated at container build time (container internal IP=$container_ip)</p>\n"

printf "$custom_web_conf" > web.conf  #run in /opt/splunk/system/local

#restarting splunkweb may not work with 6.5+
/opt/splunk/bin/splunk restart splunkweb -auth admin:hello
