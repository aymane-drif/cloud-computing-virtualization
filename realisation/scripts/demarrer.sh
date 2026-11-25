#!/bin/bash
# Demarrage dans l'ordre. L'ordre compte : un demarrage simultane fait echouer
# le gestionnaire, qui essaie d'ecrire dans un indexeur pas encore pret, et on
# perd une heure a chercher une mauvaise cause.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/moteur.sh
detecter_moteur

echo "== 1. Indexeur, seul =="
$CE up -d wazuh-indexer
printf "   attente"
pret=non
for _ in $(seq 1 60); do
  if $CE exec -T wazuh-indexer curl -sk https://localhost:9200 >/dev/null 2>&1; then
    echo " pret."
    pret=oui
    break
  fi
  printf "."
  sleep 5
done
if [ "$pret" = "non" ]; then
  echo
  echo "   L'indexeur n'a pas repondu en 5 minutes. Journaux :"
  echo "     $CE logs wazuh-indexer | tail -40"
  echo "   Cause la plus frequente : vm.max_map_count."
  exit 1
fi

echo "== 2. Gestionnaire =="
$CE up -d wazuh-manager
sleep 20

echo "== 3. Interfaces =="
$CE up -d wazuh-dashboard grafana recepteur
sleep 10

echo "== 4. Le parc =="
$CE up -d hote-a hote-b hote-c attaquant

echo
echo "Les agents mettent jusqu'a deux minutes a s'enroler."
echo "Verification :  ./scripts/verifier.sh"
echo
echo "Console Wazuh : https://localhost:8443   (admin / voir .env)"
echo "Grafana       : http://localhost:3000    (admin / voir .env)"
