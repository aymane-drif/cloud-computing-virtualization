#!/bin/bash
# Scenario 1 : force brute SSH.
# Couvert par le jeu de regles livre (5710, 5712). Rien a ecrire de notre cote.
# Attendu : alerte de niveau 10, regle 5712, agent hote-a.
set -u
source "$(dirname "$0")/00-lib.sh"

CIBLE="${1:-$CIBLE_A}"
TENTATIVES="${TENTATIVES:-20}"

attendre_cible "$CIBLE" 22 || exit 1
marquer_debut "01-bruteforce-ssh vers ${CIBLE}"

for i in $(seq 1 "$TENTATIVES"); do
  sshpass -p "motdepasse${i}" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=3 \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    "operateur@${CIBLE}" "true" >/dev/null 2>&1
  echo "  tentative ${i}/${TENTATIVES}"
  sleep 1
done

marquer_fin "01-bruteforce-ssh"
echo "Attendu : regle 5712, niveau 10, 'Multiple authentication failures'"
