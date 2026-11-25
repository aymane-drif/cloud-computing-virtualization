#!/bin/bash
# Resultat negatif 1 : un faux positif provoque.
#
# Un administrateur legitime se trompe trois fois de mot de passe, et un agent
# consulte quelques dossiers hors de sa plage par erreur.
#
# ATTENDU : la chaine reste SILENCIEUSE. C'est ce qui valide le seuil.
# Si une alerte sort ici, le seuil est trop bas et le tableau de bord se
# remplira de bruit en production.
set -u
source "$(dirname "$0")/00-lib.sh"

CIBLE="${1:-$CIBLE_A}"

attendre_cible "$CIBLE" 22 || exit 1
marquer_debut "06-faux-positif (doit rester silencieux)"

sshopts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -o ConnectTimeout=3 -o PreferredAuthentications=password \
         -o PubkeyAuthentication=no)

echo "  trois echecs d'authentification espaces, comme un humain qui se trompe"
for i in 1 2 3; do
  sshpass -p "oups${i}" ssh "${sshopts[@]}" "operateur@${CIBLE}" true >/dev/null 2>&1
  sleep 8
done

echo "  quatre consultations hors plage, comme un agent qui se trompe de dossier"
for numero in 910 925 933 944; do
  dossier=$(printf "DOS-%06d" "${numero}")
  curl -s -o /dev/null --max-time 5 "${APP_URL}/dossiers/${dossier}?user=s.alaoui"
  sleep 6
done

marquer_fin "06-faux-positif"
echo "Attendu : AUCUNE alerte de niveau >= 10."
echo "Si une alerte apparait, le seuil de 100120 ou de 5712 est trop bas."
