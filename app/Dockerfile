FROM python:3.9-slim-bullseye
LABEL maintainer="Jack Yaz <jackyaz@outlook.com>"

RUN apt-get update && apt-get -y install --no-install-recommends csvkit=1.0.5-2 curl=7.74.0-1.3+deb11u1 cron=3.0pl1-137 nano=5.4-2 jq=1.6-2.1 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY crontab /etc/cron.d/crontab
RUN chmod 0644 /etc/cron.d/crontab
RUN crontab /etc/cron.d/crontab

COPY scarf.sh /scarfgatewaystats/
RUN chmod 0755 /scarfgatewaystats/scarf.sh

COPY entry.sh /
RUN chmod 0755 /entry.sh

VOLUME /scarfgatewaystats/CSVs

ENTRYPOINT ["/entry.sh"]
