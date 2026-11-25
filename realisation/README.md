# Sujet 13 · Surveillance et détection d'incidents

Parc Linux de trois hôtes sous surveillance Wazuh, cinq scénarios d'attaque
scriptés, et une matrice qui dit ce que la chaîne détecte et ce qu'elle manque.

Tout tourne en local, sans coût, sur un poste à 24 Go de RAM.

---

## Ce qui porte le projet

Quatre scénarios sur cinq sont détectés par le jeu de règles livré avec Wazuh.
C'est utile mais ça ne prouve rien : n'importe qui peut installer Wazuh et
déclencher une force brute.

Le cinquième scénario attaque une application dont Wazuh ne connaît pas le
format de journal. Le jeu livré reste muet, le tableau de bord reste vert
pendant toute l'attaque, et c'est nous qui écrivons le décodeur et les règles
qui comblent le trou.

**Le silence initial est la capture la plus importante du projet, et elle ne se
refait pas.** Voir la section Démonstration, étape 5.

---

## Prérequis

| Élément | Minimum | Vérification |
| --- | --- | --- |
| RAM libre | 8 Go | `free -h` |
| Disque | 20 Go | `df -h .` |
| Docker **ou** Podman | Docker 24+ / Podman 4.4+ | `docker compose version` ou `podman compose version` |
| `vm.max_map_count` | 262144 | `sysctl vm.max_map_count` |

Le réglage `vm.max_map_count` est la panne numéro un de la première heure, et
elle n'a aucun rapport avec la quantité de mémoire disponible :

```bash
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
```

Sous Windows ou macOS, ce réglage se fait **dans la machine virtuelle**, pas
sur l'hôte. `scripts/preparer.sh` détecte le cas et affiche la commande exacte
pour votre moteur.

---

## Docker ou Podman

Les deux fonctionnent, sans fichier séparé. `scripts/moteur.sh` détecte
`docker compose`, `podman compose` ou `podman-compose` et les trois scripts
s'adaptent.

Trois choix du `docker-compose.yml` existent pour que Podman rootless passe :

**Pas de `memlock`.** Podman rootless refuse `memlock: -1`
(`setrlimit RLIMIT_MEMLOCK: Operation not permitted`) et l'indexeur ne démarre
pas du tout. `bootstrap.memory_lock` est donc à `false`. Conséquence réelle :
le tas JVM peut être transféré sur disque. Sans importance sur un poste de
développement, à remettre à `true` en production avec les limites qui vont
avec. C'est une limite à citer dans le rapport, pas à cacher.

**`nofile` à 65536, pas 655360.** Même raison : au-delà du plafond rootless,
`setrlimit` échoue.

**Le générateur de certificats est hors du cycle `up`.** Il porte
`profiles: ["setup"]` et `scripts/preparer.sh` le lance une fois. La raison est
que `podman-compose` ne gère pas `depends_on: condition:
service_completed_successfully` (issue 575 du projet, ouverte depuis 2022), et
un `depends_on` de ce type aurait rendu le fichier inutilisable sous Podman.
Cette mise à l'écart est de toute façon plus propre : générer des certificats
n'est pas une étape de démarrage, c'est une étape d'installation.

Les images sont pleinement qualifiées (`docker.io/...`) parce que Podman n'a
pas de registre par défaut et demanderait sinon quel registre utiliser.

Sous Podman rootful (`sudo podman`), aucune de ces contraintes ne s'applique,
mais rien n'oblige à y passer.

---

## Mise en route

```bash
cp .env.example .env     # changez les mots de passe
./scripts/preparer.sh    # vérifie le système, génère les certificats
./scripts/demarrer.sh    # démarre dans l'ordre : indexeur, gestionnaire, interfaces, parc
./scripts/verifier.sh    # point de contrôle du jour 1
```

L'ordre de démarrage n'est pas cosmétique. Un `docker compose up -d` global
fait échouer le gestionnaire, qui essaie d'écrire dans un indexeur pas encore
prêt, et on perd une heure à chercher une mauvaise cause.

Accès :

- Console Wazuh : <https://localhost:8443>
- Grafana : <http://localhost:3000>
- L'indexeur n'est joignable depuis aucun des deux réseaux exposés, et c'est
  volontaire.

---

## Architecture des réseaux

C'est la décision de conception du projet, et elle se lit dans
`docker-compose.yml` :

| Réseau | Qui y est | Rôle |
| --- | --- | --- |
| `net-parc` | hôtes, application, attaquant, gestionnaire | le parc surveillé |
| `net-soc` | gestionnaire, indexeur, console, Grafana, récepteur | `internal: true` |
| `net-admin` | console, Grafana | l'accès navigateur depuis le poste |

Le gestionnaire est le seul conteneur attaché à `net-parc` et `net-soc`. Un
hôte compromis peut mentir sur ce qu'il envoie, il ne peut pas effacer ce qui
est déjà stocké.

Un cloisonnement réseau vaut mieux qu'une liste de durcissements : il ne dépend
pas d'un réglage juste, il découle de la structure, et il se vérifie en direct
par une connexion qui expire.

---

## Les scénarios

| # | Script | Source | Couvert par le jeu livré ? |
| --- | --- | --- | --- |
| 1 | `01-bruteforce-ssh.sh` | `/var/log/auth.log` | Oui, règle 5712 |
| 2 | `02-escalade-sudo.sh` | `/var/log/auth.log` | Oui, règles 5402 / 5403 |
| 3 | `03-integrite-binaire.sh` | syscheck temps réel | Oui, règle 550 |
| 4 | `04-scan-ports.sh` | `/var/log/auth.log` via sshd | Oui, règle 5701 |
| 5 | `05-enumeration.sh` | `access.json` | **Non. Règles 100100 à 100120, écrites par nous** |
| — | `06-faux-positif.sh` | mixte | Doit rester silencieux |
| — | `07-contournement-lent.sh` | `access.json` | Échappe volontairement à notre règle |
| — | `08-effacement-journal.sh` | `/var/log/auth.log` | Démonstration d'expédition immédiate |

Lancement, toujours depuis le conteneur attaquant :

```bash
docker compose exec attaquant /attaques/05-enumeration.sh
```

Chaque script écrit son heure de début dans `mesures/starts.log`. Sans cette
ligne, les latences ne sont pas mesurables et il faut tout rejouer.

---

## Note honnête sur le scénario 4

Dans un conteneur, un balayage de ports n'est **pas** détecté par les journaux
du pare-feu. `iptables -j LOG` écrit dans le journal noyau de l'hôte, pas dans
celui du conteneur, et un conteneur n'a pas son propre `kmsg`.

La source réelle ici est `sshd`, qui journalise chaque connexion ouverte puis
abandonnée par le scan (« Did not receive identification string », règle 5701).
C'est une signature légitime, et c'est une limite à énoncer dans le rapport
plutôt qu'à masquer. Sur du matériel réel avec un pare-feu hôte, la source
serait le journal du pare-feu et le résultat serait le même.

---

## Démonstration, dans l'ordre

L'ordre des étapes 4 à 7 est contraint. L'inverser détruit une preuve qui ne se
refait pas.

1. **Montrer les trois agents actifs** dans la console.
2. **Montrer le cloisonnement** : `./scripts/verifier.sh`, la connexion de
   `hote-a` vers l'indexeur expire.
3. **Jouer les scénarios 1 à 4**, une alerte visible pour chacun.
4. **Retirer les règles locales** si elles sont déjà en place :
   ```bash
   docker compose exec wazuh-manager sh -c '> /var/ossec/etc/rules/local_rules.xml'
   docker compose restart wazuh-manager
   ```
5. **Jouer le scénario 5 et capturer le silence.** Trois images : le script en
   cours avec son horodatage, la console filtrée à zéro alerte, et les
   événements bruts qui arrivent quand même. La troisième est celle qui
   transforme la capture en argument : sans elle, un jury peut croire que
   l'agent ne lisait pas le fichier, ce qui serait une panne et non une
   démonstration.
6. **Remettre les règles** et redémarrer le gestionnaire.
7. **Rejouer le scénario 5.** Alerte 100120, niveau 10. Capturer.
8. **Jouer l'effacement** : `08-effacement-journal.sh`. À filmer.
9. **Jouer les deux négatifs**, 06 et 07. Aucune alerte, et c'est le résultat
   attendu.

---

## Mesures

```bash
# 1. exporter les alertes de l'indexeur
docker compose exec wazuh-indexer curl -sk -u admin:"$INDEXER_PASSWORD" \
  "https://localhost:9200/wazuh-alerts-*/_search?size=500&sort=timestamp:desc" \
  > mesures/alertes.json

# 2. exporter le journal du récepteur
docker compose logs recepteur --no-log-prefix > mesures/notifications.log

# 3. dépouiller
python3 mesures/depouiller.py
```

Produit `mesures/latences.csv` et un résumé en médiane et étendue. Pas de
moyenne, pas de valeur unique : une latence unique n'a pas de sens sur un
système dont la charge varie.

---

## Arborescence

```
realisation/
  docker-compose.yml          trois réseaux, dix services
  .env.example                mots de passe, jamais commités
  scripts/
    preparer.sh               vérifications système, certificats
    demarrer.sh               démarrage dans l'ordre
    verifier.sh               point de contrôle du jour 1
  config/wazuh/
    manager/rules/local_rules.xml       nos règles, tout le travail du sujet
    manager/decoders/local_decoder.xml  notre décodeur, mode dégradé
    indexer/opensearch.yml
  parc/
    Dockerfile                hôte Linux : sshd, rsyslog, sudo, agent Wazuh
    ossec.conf.tpl            config agent, syscheck realtime
    entrypoint.sh
    app-metier/app.py         l'application du scénario 5
  attaquant/Dockerfile        nmap, sshpass, curl
  attaques/                   les huit scripts
  recepteur/app.py            horodate les notifications
  grafana/                    source, tableau de bord, règle d'alerte, webhook
  mesures/depouiller.py       les trois horodatages, médiane et étendue
  captures/                   le dossier de preuves, voir INDEX.md
```

---

## Pièges connus

| Symptôme | Cause | Parade |
| --- | --- | --- |
| L'indexeur s'arrête après quelques secondes | `vm.max_map_count` trop bas | Le régler, puis relancer |
| Le gestionnaire échoue au démarrage | Indexeur pas encore prêt | `./scripts/demarrer.sh`, pas `up -d` global |
| Un agent n'apparaît pas | Nom d'hôte en doublon, ou mot de passe d'enrôlement absent | `docker compose logs hote-b` |
| Le contrôle d'intégrité ne déclenche pas | Mode périodique au lieu de temps réel | `realtime="yes"` dans `ossec.conf.tpl` |
| La règle 100120 ne déclenche jamais | Seuil au-dessus de ce que le script produit | Compter d'abord, puis choisir le seuil |
| Grafana ne voit aucune donnée | Motif d'index ou plage de temps | Vérifier d'abord dans la console native |

---

## Ce qui a été vérifié, et ce qui ne l'a pas été

Honnêteté sur l'état du dépôt au moment de la rédaction.

**Vérifié :** la syntaxe de tous les fichiers. Le `docker-compose.yml` est du
YAML valide avec dix services et trois réseaux, les deux fichiers XML sont bien
formés, les scripts shell passent `bash -n`, les fichiers Python passent
l'analyse syntaxique, le tableau de bord Grafana est du JSON valide.

**Non vérifié :** l'exécution. La pile n'a pas été démarrée, les images n'ont
pas été construites, et aucune alerte n'a été produite. Les points les plus
susceptibles de demander un ajustement au premier démarrage :

1. L'enrôlement des agents, qui dépend du timing entre le gestionnaire et les
   hôtes. Le script `entrypoint.sh` réessaie trente fois sur deux minutes.
2. Le montage des certificats, dont les chemins varient légèrement entre les
   versions 4.8 et 4.10 de Wazuh.
3. `same_field` dans la règle 100120, dont la syntaxe exacte pour les champs
   JSON personnalisés mérite d'être confirmée avec `wazuh-logtest` avant de
   compter dessus.

Le jour 1 sert à ça. Mettez la règle 100120 au point avec `wazuh-logtest` avant
de la tester de bout en bout :

```bash
docker compose exec wazuh-manager /var/ossec/bin/wazuh-logtest
```
