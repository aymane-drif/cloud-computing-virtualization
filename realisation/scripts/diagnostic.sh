#!/bin/bash
# Collecte tout ce qu'il faut pour diagnostiquer un demarrage qui echoue.
#
#   ./scripts/diagnostic.sh > diagnostic.txt 2>&1
#
# Puis coller le contenu de diagnostic.txt. Une seule commande, une seule
# sortie, plutot que dix allers-retours.
cd "$(dirname "$0")/.."
source scripts/moteur.sh 2>/dev/null && detecter_moteur 2>/dev/null || CE="docker compose"

echo "##### MOTEUR #####"
echo "CE=${CE}"
podman --version 2>/dev/null || true
docker --version 2>/dev/null || true
$CE version 2>&1 | head -5

echo
echo "##### VM / NOYAU #####"
uname -a
echo "vm.max_map_count = $(sysctl -n vm.max_map_count 2>/dev/null || echo '?')"
echo "ulimit -l = $(ulimit -l)"
echo "ulimit -n = $(ulimit -n)"
free -h 2>/dev/null | head -2
df -h . 2>/dev/null | tail -1

echo
echo "##### ETAT DES SERVICES #####"
$CE ps -a 2>&1

echo
echo "##### RESEAUX #####"
if command -v podman >/dev/null 2>&1; then
  podman network ls 2>&1
  podman network inspect soc-sujet13_net-soc 2>&1 | grep -i -E '"name"|internal' | head -5
else
  docker network ls 2>&1 | grep -E 'soc-sujet13|NETWORK'
  docker network inspect soc-sujet13_net-soc --format '{{.Name}} internal={{.Internal}}' 2>&1
fi

echo
echo "##### CERTIFICATS #####"
ls -la config/wazuh_indexer_ssl_certs/ 2>&1 | head -15

echo
echo "##### INDEXEUR, 60 dernieres lignes #####"
$CE logs --tail 60 wazuh-indexer 2>&1

echo
echo "##### GESTIONNAIRE, 40 dernieres lignes #####"
$CE logs --tail 40 wazuh-manager 2>&1

echo
echo "##### HOTE-A, 40 dernieres lignes #####"
$CE logs --tail 40 hote-a 2>&1

echo
echo "##### AGENTS ENROLES #####"
$CE exec -T wazuh-manager /var/ossec/bin/agent_control -l 2>&1 | head -20

echo
echo "##### FIN #####"
