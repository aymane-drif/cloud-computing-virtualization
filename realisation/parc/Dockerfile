# Un hote Linux du parc : sshd, rsyslog, sudo, et l'agent Wazuh.
FROM docker.io/library/debian:bookworm-slim

ARG WAZUH_VERSION=4.9.2-1

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release \
      openssh-server rsyslog sudo procps iproute2 net-tools \
      python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

# Depot officiel Wazuh
RUN curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH \
      | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import \
 && chmod 644 /usr/share/keyrings/wazuh.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
      > /etc/apt/sources.list.d/wazuh.list \
 && apt-get update \
 && WAZUH_MANAGER="placeholder" apt-get install -y wazuh-agent=${WAZUH_VERSION} \
 && apt-mark hold wazuh-agent \
 && rm -rf /var/lib/apt/lists/*

# Comptes de la demonstration
RUN useradd -m -s /bin/bash operateur && echo 'operateur:Operateur2026' | chpasswd \
 && usermod -aG sudo operateur \
 && useradd -m -s /bin/bash stagiaire && echo 'stagiaire:Stagiaire2026' | chpasswd \
 && mkdir -p /run/sshd

# Le binaire surveille par le controle d'integrite (scenario 3)
RUN mkdir -p /usr/local/bin \
 && printf '#!/bin/sh\n# sauvegarde nocturne du parc\nrsync -a /srv/data/ /srv/backup/\n' \
      > /usr/local/bin/sauvegarde.sh \
 && chmod 755 /usr/local/bin/sauvegarde.sh

# rsyslog doit ecrire auth.log, c'est la source des scenarios 1, 2 et 4
RUN sed -i 's|^\$ModLoad imklog|#\$ModLoad imklog|' /etc/rsyslog.conf || true \
 && sed -i 's|^module(load="imklog")|#module(load="imklog")|' /etc/rsyslog.conf || true

COPY ossec.conf.tpl /etc/wazuh-agent/ossec.conf.tpl
COPY entrypoint.sh /usr/local/sbin/entrypoint.sh
COPY app-metier/ /opt/app-metier/

RUN chmod +x /usr/local/sbin/entrypoint.sh \
 && mkdir -p /var/log/app-metier

EXPOSE 22
ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
