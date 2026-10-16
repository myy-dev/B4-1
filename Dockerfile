FROM ubuntu:24.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server ufw acl cron procps iproute2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/agent-lab
COPY app/ ./app/
COPY scripts/ ./scripts/
RUN chmod +x ./scripts/*.sh

EXPOSE 20022/tcp 15034/tcp

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD pgrep -u agent-admin -x agent-app >/dev/null \
        && ss -H -ltn 'sport = :15034' | grep -q .

ENTRYPOINT ["/opt/agent-lab/scripts/start.sh"]
