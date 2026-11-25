#!/bin/bash
# Point de controle du jour 1 : les trois agents sont-ils actifs, et le
# cloisonnement tient-il ? Tant que ces deux points ne passent pas, rien de ce
# qui suit n'est testable.
set -u
cd "$(dirname "$0")/.."
source scripts/moteur.sh
detecter_moteur

echo
echo "== Agents enroles =="
$CE exec -T wazuh-manager /var/ossec/bin/agent_control -l || true

echo
echo "== Preuve 3 : le parc ne joint PAS l'indexeur =="
echo "   (une reussite ici serait un echec du projet)"
if $CE exec -T hote-a curl -sk -m 5 https://wazuh-indexer:9200 >/dev/null 2>&1; then
  echo "   ECHEC : hote-a atteint l'indexeur. Verifiez 'internal: true' sur net-soc."
else
  echo "   OK : connexion refusee ou expiree depuis hote-a."
fi

echo
echo "== Application metier =="
$CE exec -T attaquant curl -s -m 5 http://hote-c:8080/sante || echo "   injoignable"

echo
echo "== Lignes deja produites par l'application =="
$CE exec -T hote-c wc -l /var/log/app-metier/access.json 2>/dev/null || echo "   journal absent"

echo
echo "== Reseaux =="
if [ "$MOTEUR" = "podman" ]; then
  podman network inspect soc-sujet13_net-soc --format '{{.Name}} internal={{.Internal}}' 2>/dev/null \
    || echo "   (nom de reseau different, verifiez avec: podman network ls)"
else
  docker network inspect soc-sujet13_net-soc --format '{{.Name}} internal={{.Internal}}' 2>/dev/null \
    || echo "   (nom de reseau different, verifiez avec: docker network ls)"
fi
