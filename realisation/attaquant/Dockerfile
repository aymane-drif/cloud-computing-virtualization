# Le poste d'attaque. Ce n'est pas une menace modelisee, c'est un instrument de
# mesure : il produit a la demande les evenements que la chaine doit qualifier,
# et il les horodate.
FROM docker.io/library/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl sshpass openssh-client nmap netcat-openbsd \
      python3 jq procps iputils-ping \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /attaques
CMD ["sleep", "infinity"]
