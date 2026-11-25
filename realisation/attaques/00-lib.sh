#!/bin/bash
# Fonctions communes a tous les scenarios.
#
# La seule chose importante ici est marquer_debut : chaque attaque ecrit son
# heure de depart dans mesures/starts.log. Sans cette ligne, les latences de la
# section Tests ne sont pas mesurables et il faut tout rejouer.

MESURES="${MESURES:-/mesures}"
CIBLE_A="${CIBLE_A:-hote-a}"
CIBLE_B="${CIBLE_B:-hote-b}"
CIBLE_C="${CIBLE_C:-hote-c}"
APP_URL="${APP_URL:-http://hote-c:8080}"

horodatage() {
  date -u +%Y-%m-%dT%H:%M:%S.%3NZ
}

marquer_debut() {
  local nom="$1"
  mkdir -p "$MESURES"
  local t
  t="$(horodatage)"
  echo "${t} debut ${nom}" | tee -a "${MESURES}/starts.log"
  echo
  echo "=============================================================="
  echo "  ${nom}"
  echo "  debut : ${t}"
  echo "=============================================================="
  echo
}

marquer_fin() {
  local nom="$1"
  local t
  t="$(horodatage)"
  echo "${t} fin ${nom}" | tee -a "${MESURES}/starts.log"
  echo
  echo "--- ${nom} termine a ${t} ---"
  echo
}

attendre_cible() {
  local hote="$1" port="$2"
  for _ in $(seq 1 30); do
    if nc -z -w 2 "$hote" "$port" 2>/dev/null; then return 0; fi
    sleep 2
  done
  echo "ERREUR : ${hote}:${port} injoignable" >&2
  return 1
}
