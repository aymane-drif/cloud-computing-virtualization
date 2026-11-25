#!/bin/bash
# Scenario 4 : balayage de ports depuis l'attaquant.
#
# NOTE HONNETE, a reprendre dans le rapport :
# dans un conteneur, un balayage n'est PAS detecte par les journaux du pare-feu.
# iptables -j LOG ecrit dans le journal noyau de l'hote, pas dans celui du
# conteneur, et un conteneur n'a pas son propre kmsg. La source reelle ici est
# sshd, qui journalise chaque connexion ouverte puis abandonnee par le scan
# ("Did not receive identification string"). C'est une signature legitime et
# c'est celle que le jeu livre exploite (regle 5701).
set -u
source "$(dirname "$0")/00-lib.sh"

CIBLE="${1:-$CIBLE_B}"

attendre_cible "$CIBLE" 22 || exit 1
marquer_debut "04-scan-ports vers ${CIBLE}"

echo "  balayage TCP connect sur 1-1024"
nmap -sT -p 1-1024 --max-retries 1 --host-timeout 60s "$CIBLE" || true

echo "  puis quinze ouvertures sans handshake sur le port 22"
for i in $(seq 1 15); do
  (exec 3<>/dev/tcp/"${CIBLE}"/22; exec 3<&-; exec 3>&-) 2>/dev/null
  sleep 1
done

marquer_fin "04-scan-ports"
echo "Attendu : regle 5701 'Did not receive identification string', puis correlation"
