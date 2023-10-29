FROM debian:bookworm-slim
LABEL maintainer="Jack Yaz <jackyaz@outlook.com>"

RUN apt update && apt -y install --no-install-recommends csvkit curl cron nano jq ca-certificates \
 && apt clean \
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
