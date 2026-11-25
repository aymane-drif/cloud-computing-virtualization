#!/bin/bash
# Scenario 2 : elevation de privileges.
# Un compte sans droits tente sudo (refus), puis un compte avec droits reussit.
# Couvert par le jeu livre (5402, 5403, 5404). Rien a ecrire de notre cote.
set -u
source "$(dirname "$0")/00-lib.sh"

CIBLE="${1:-$CIBLE_B}"

attendre_cible "$CIBLE" 22 || exit 1
marquer_debut "02-escalade-sudo sur ${CIBLE}"

sshopts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)

echo "  phase 1 : stagiaire tente sudo, trois refus attendus"
for i in 1 2 3; do
  sshpass -p "Stagiaire2026" ssh "${sshopts[@]}" "stagiaire@${CIBLE}" \
    "echo mauvais | sudo -S cat /etc/shadow" >/dev/null 2>&1
  sleep 2
done

echo "  phase 2 : operateur utilise sudo legitimement"
sshpass -p "Operateur2026" ssh "${sshopts[@]}" "operateur@${CIBLE}" \
  "echo Operateur2026 | sudo -S cat /etc/shadow | head -1" >/dev/null 2>&1

marquer_fin "02-escalade-sudo"
echo "Attendu : regle 5403 (user NOT in sudoers) puis 5402 (successful sudo)"
