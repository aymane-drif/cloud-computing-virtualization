#!/bin/bash
# Scenario 5 : enumeration de dossiers par un compte legitime.
#
# C'EST LE SCENARIO QUI PORTE LE PROJET.
#
# Un compte valide parcourt des centaines d'identifiants hors de sa plage de
# droits. Chaque requete prise isolement est un refus banal. La rafale est une
# exfiltration par balayage.
#
# Aucune regle livree avec Wazuh ne couvre ce cas, parce qu'il depend d'une
# regle metier (qui a droit a quelle plage) que l'outil ne peut pas deviner.
#
# ORDRE OBLIGATOIRE, ne pas sauter d'etape :
#   1. lancer ce script AVANT d'avoir installe local_rules.xml
#   2. capturer la console vide     -> 09b
#   3. capturer les evenements bruts -> 09c
#   4. seulement ensuite, installer les regles et relancer -> 10
# L'ordre inverse detruit la preuve et elle ne se refait pas.
set -u
source "$(dirname "$0")/00-lib.sh"

UTILISATEUR="${UTILISATEUR:-m.bennani}"     # compte legitime, plage 1 a 500
REQUETES="${ENUM_REQUESTS:-40}"
DELAI_MS="${ENUM_DELAY_MS:-300}"
DEBUT_PLAGE="${DEBUT_PLAGE:-900}"           # hors de sa plage : refus garantis

if ! curl -fsS --max-time 5 "${APP_URL}/sante" >/dev/null 2>&1; then
  echo "ERREUR : application metier injoignable sur ${APP_URL}" >&2
  echo "Verifier que hote-c tourne avec APP_METIER=oui" >&2
  exit 1
fi

marquer_debut "05-enumeration ${UTILISATEUR} vers ${APP_URL}"

refus=0
for i in $(seq 0 $((REQUETES - 1))); do
  numero=$((DEBUT_PLAGE + i))
  dossier=$(printf "DOS-%06d" "$numero")
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
         "${APP_URL}/dossiers/${dossier}?user=${UTILISATEUR}")
  [ "$code" = "403" ] && refus=$((refus + 1))
  printf "  %s -> %s\n" "$dossier" "$code"
  sleep "$(awk "BEGIN{print ${DELAI_MS}/1000}")"
done

marquer_fin "05-enumeration"
echo "${refus} refus produits sur ${REQUETES} requetes."
echo
echo "Seuil de la regle 100120 : 25 refus en 30 secondes, meme user, meme source."
echo
echo "SANS nos regles  : aucune alerte. C'est la preuve 9, a capturer maintenant."
echo "AVEC nos regles  : alerte 100120 niveau 10. C'est la preuve 10."
