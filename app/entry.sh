#!/bin/sh
env >> /etc/environment
/scarfgatewaystats/scarf.sh

exec cron -f -l 2
