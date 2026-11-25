#!/bin/bash
# Demarrage d'un hote du parc : journaux, ssh, agent, et l'application si demande.
set -e

AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname)}"
MANAGER="${WAZUH_MANAGER:-wazuh-manager}"

echo "[parc] hote ${AGENT_NAME}, gestionnaire ${MANAGER}"

# 1. rsyslog, sinon /var/log/auth.log n'existe jamais et rien n'est detectable
touch /var/log/auth.log /var/log/syslog
rsyslogd
sleep 1

# 2. sshd, cible des scenarios 1 et 4
/usr/sbin/sshd

# 3. Application metier, uniquement sur l'hote qui la porte
if [ "${APP_METIER:-non}" = "oui" ]; then
  echo "[parc] demarrage de l'application metier dossiers"
  mkdir -p /var/log/app-metier
  touch /var/log/app-metier/access.json /var/log/app-metier/access.log
  python3 /opt/app-metier/app.py >> /var/log/app-metier/service.log 2>&1 &
  sleep 1
fi

# 4. Agent Wazuh : configuration puis enrolement
printf '%s' "${WAZUH_REGISTRATION_PASSWORD:-EnrolParc2026!}" > /var/ossec/etc/authd.pass
chmod 640 /var/ossec/etc/authd.pass
chown root:wazuh /var/ossec/etc/authd.pass

sed -e "s|__MANAGER__|${MANAGER}|g" \
    -e "s|__AGENT_NAME__|${AGENT_NAME}|g" \
    /etc/wazuh-agent/ossec.conf.tpl > /var/ossec/etc/ossec.conf

# Le gestionnaire met une trentaine de secondes a accepter les enrolements
for i in $(seq 1 30); do
  if /var/ossec/bin/agent-auth -m "${MANAGER}" -A "${AGENT_NAME}" \
       -P "$(cat /var/ossec/etc/authd.pass)" 2>&1 | tee /tmp/enrol.log | grep -q "Valid key"; then
    echo "[parc] enrolement reussi pour ${AGENT_NAME}"
    break
  fi
  echo "[parc] gestionnaire pas encore pret, tentative ${i}/30"
  sleep 5
done

/var/ossec/bin/wazuh-control start

echo "[parc] ${AGENT_NAME} est pret"
tail -f /var/ossec/logs/ossec.log
