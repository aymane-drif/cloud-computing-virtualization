#!/bin/bash
# Detection du moteur de conteneurs. Source par les trois autres scripts.
#
# Le projet tourne sous Docker ou sous Podman. Les differences reelles sont
# dans docker-compose.yml, pas ici : pas de memlock, pas de nofile au-dela du
# plafond rootless, et le generateur de certificats sorti du cycle 'up' parce
# que podman-compose ne gere pas service_completed_successfully.

detecter_moteur() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    CE="docker compose"
    MOTEUR="docker"
  elif command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
    CE="podman compose"
    MOTEUR="podman"
  elif command -v podman-compose >/dev/null 2>&1; then
    CE="podman-compose"
    MOTEUR="podman"
  else
    echo "ERREUR : ni 'docker compose', ni 'podman compose', ni 'podman-compose' trouve." >&2
    exit 1
  fi
  export CE MOTEUR
  echo "[moteur] ${CE}"
}

# Rootless ou non. En rootless, certaines limites ne sont pas modifiables et
# c'est pour ca que le compose n'en demande aucune.
est_rootless() {
  [ "$MOTEUR" = "podman" ] && [ "$(id -u)" != "0" ]
}

# vm.max_map_count ne se regle pas au meme endroit selon le moteur et l'OS.
aide_max_map_count() {
  cat <<'AIDE'

  Linux natif :
    sudo sysctl -w vm.max_map_count=262144
    echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf

  Podman sous Windows ou macOS (la VM podman machine) :
    podman machine ssh
    sudo sysctl -w vm.max_map_count=262144
    sudo sh -c "echo 'vm.max_map_count=262144' >> /etc/sysctl.conf"
    exit

  Docker Desktop sous Windows (WSL2) :
    wsl -d docker-desktop sysctl -w vm.max_map_count=262144
  ou, de maniere persistante, dans C:\Users\<vous>\.wslconfig :
    [wsl2]
    kernelCommandLine = sysctl.vm.max_map_count=262144
  puis : wsl --shutdown

AIDE
}
