#!/bin/bash
# A lancer une seule fois, avant le premier demarrage.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/moteur.sh
detecter_moteur

echo "== 1. Fichier .env =="
if [ ! -f .env ]; then
  cp .env.example .env
  echo "   .env cree depuis .env.example. Changez les mots de passe avant de continuer."
else
  echo "   .env existe deja, inchange."
fi
set -a; source .env; set +a

echo "== 2. vm.max_map_count =="
# Le reglage vit dans le noyau qui fait tourner les conteneurs. Sous Windows ou
# macOS ce n'est PAS le noyau de l'hote, c'est celui de la VM podman machine, et
# 'sysctl' n'existe meme pas dans Git Bash. On regarde donc au bon endroit.
regle_max_map_count() {
  local lu
  # Cas 1 : Linux natif, sysctl repond ici.
  if lu=$(sysctl -n vm.max_map_count 2>/dev/null) && [ -n "$lu" ]; then
    if [ "$lu" -ge 262144 ]; then
      echo "   ${lu} sur cet hote, suffisant."
      return 0
    fi
    echo "   ${lu} sur cet hote, insuffisant."
    aide_max_map_count
    return 1
  fi

  # Cas 2 : pas de sysctl ici. Si podman est la, la valeur qui compte est
  # celle de la VM.
  if command -v podman >/dev/null 2>&1; then
    echo "   pas de sysctl sur cet hote : lecture dans la VM podman."
    if ! lu=$(podman machine ssh sudo sysctl -n vm.max_map_count 2>/dev/null | tr -d "\r"); then
      echo "   la VM podman ne repond pas. Est-elle demarree ? 'podman machine start'"
      return 1
    fi
    echo "   VM podman : ${lu}"
    if [ -n "$lu" ] && [ "$lu" -ge 262144 ]; then
      echo "   suffisant."
      return 0
    fi
    echo "   insuffisant, application du reglage dans la VM..."
    podman machine ssh sudo sysctl -w vm.max_map_count=262144 >/dev/null 2>&1
    podman machine ssh "sudo sh -c 'grep -q vm.max_map_count /etc/sysctl.conf || echo vm.max_map_count=262144 >> /etc/sysctl.conf'" >/dev/null 2>&1
    lu=$(podman machine ssh sudo sysctl -n vm.max_map_count 2>/dev/null | tr -d "\r")
    if [ -n "$lu" ] && [ "$lu" -ge 262144 ]; then
      echo "   applique et persiste : ${lu}"
      return 0
    fi
    echo "   l'application a echoue. A faire a la main :"
    aide_max_map_count
    return 1
  fi

  echo "   impossible de lire vm.max_map_count depuis cet hote."
  aide_max_map_count
  return 1
}

regle_max_map_count || exit 1

if est_rootless; then
  echo "== 2b. Podman rootless detecte =="
  echo "   Le compose ne demande aucune limite memlock ni nofile elevee,"
  echo "   donc rien a faire. Si vous voyez 'setrlimit: Operation not permitted',"
  echo "   c'est que le docker-compose.yml a ete modifie."
fi

echo "== 3. Mot de passe d'enrolement des agents =="
printf '%s' "${AGENT_ENROLLMENT_PASSWORD}" > config/wazuh/manager/authd.pass
chmod 600 config/wazuh/manager/authd.pass
echo "   config/wazuh/manager/authd.pass ecrit (non commite)."

echo "== 4. Certificats =="
if [ -f config/wazuh_indexer_ssl_certs/root-ca.pem ]; then
  echo "   deja generes, on garde."
else
  # Lance a la main, hors du cycle 'up' : voir le commentaire du service
  # generator dans docker-compose.yml.
  $CE --profile setup run --rm generator
  cp config/wazuh_indexer_ssl_certs/root-ca.pem \
     config/wazuh_indexer_ssl_certs/root-ca-manager.pem
  echo "   generes."
fi

echo
echo "Pret. Demarrage : ./scripts/demarrer.sh"
