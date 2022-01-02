FROM python:3.9-slim-bullseye
LABEL maintainer="Jack Yaz <jackyaz@outlook.com>"

RUN apt-get update && apt-get -y install --no-install-recommends csvkit curl nano=5.4-2 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY crontab /etc/cron.d/crontab
RUN chmod 0644 /etc/cron.d/crontab
RUN crontab /etc/cron.d/crontab

COPY scarf.sh /scarfgatewaystats/

COPY entry.sh /
RUN chmod 0755 /entry.sh

VOLUME /scarfgatewaystats/CSVs

ENTRYPOINT ["/entry.sh"]
