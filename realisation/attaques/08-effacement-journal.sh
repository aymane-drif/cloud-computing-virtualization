#!/bin/bash
# La demonstration d'expedition immediate.
#
# C'est le test qui explique en dix secondes pourquoi la centralisation est une
# mesure de securite et non une commodite d'exploitation.
#
# FILMEZ CETTE SEQUENCE. L'enchainement attaque, effacement, alerte toujours
# presente est plus convaincant en video qu'en deux images, et la video sert
# aussi de secours en soutenance.
set -u
source "$(dirname "$0")/00-lib.sh"

CIBLE="${1:-$CIBLE_A}"

attendre_cible "$CIBLE" 22 || exit 1
marquer_debut "08-effacement-journal sur ${CIBLE}"

sshopts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)

echo "  1. force brute, pour produire des lignes dans auth.log"
TENTATIVES=20 "$(dirname "$0")/01-bruteforce-ssh.sh" "$CIBLE"

echo
echo "  2. l'alerte doit etre visible dans la console. Verifiez-la."
read -r -p "     Alerte visible ? Entree pour effacer le journal... " _

echo "  3. lignes dans auth.log AVANT effacement :"
sshpass -p "Operateur2026" ssh "${sshopts[@]}" "operateur@${CIBLE}" \
  "wc -l /var/log/auth.log"

echo "  4. effacement par l'attaquant"
sshpass -p "Operateur2026" ssh "${sshopts[@]}" "operateur@${CIBLE}" \
  "echo Operateur2026 | sudo -S truncate -s 0 /var/log/auth.log"

echo "  5. lignes APRES effacement :"
sshpass -p "Operateur2026" ssh "${sshopts[@]}" "operateur@${CIBLE}" \
  "wc -l /var/log/auth.log"

marquer_fin "08-effacement-journal"
echo
echo "Le journal source est vide. L'alerte est toujours dans l'indexeur."
echo "Captures 17a (journal vide) et 17b (alerte presente)."
