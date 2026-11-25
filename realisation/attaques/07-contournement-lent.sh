#!/bin/bash
# Resultat negatif 2 : une enumeration qui echappe a notre propre regle.
#
# Meme attaque que le scenario 5, mais etalee au-dela de la fenetre de
# correlation : 40 refus repartis sur plusieurs minutes, soit moins de 25 refus
# dans n'importe quelle fenetre de 30 secondes.
#
# ATTENDU : aucune alerte. Ce n'est pas un echec, c'est une mesure du perimetre
# de notre regle, et le dire vaut mieux que de le taire.
set -u
source "$(dirname "$0")/00-lib.sh"

UTILISATEUR="${UTILISATEUR:-k.tazi}"
REQUETES="${REQUETES:-40}"
DELAI_S="${DELAI_S:-5}"       # 40 x 5 s = 200 s, soit 6 refus par fenetre de 30 s

marquer_debut "07-contournement-lent (doit echapper a la regle 100120)"

echo "  ${REQUETES} requetes espacees de ${DELAI_S} s"
echo "  soit environ $(awk "BEGIN{printf \"%.1f\", 30/${DELAI_S}}") refus par fenetre de 30 s, contre un seuil de 25"
echo

for i in $(seq 0 $((REQUETES - 1))); do
  dossier=$(printf "DOS-%06d" $((100 + i)))
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
         "${APP_URL}/dossiers/${dossier}?user=${UTILISATEUR}")
  printf "  %s -> %s\n" "$dossier" "$code"
  sleep "$DELAI_S"
done

marquer_fin "07-contournement-lent"
echo "Attendu : AUCUNE alerte 100120."
echo "A documenter dans le rapport comme angle mort connu et mesure."
