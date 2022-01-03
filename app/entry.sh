#!/bin/sh
env >> /etc/environment
/scarfgatewaystats/scarf.sh
cron -f
