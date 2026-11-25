# Plan d'exécution · Surveillance et détection d'incidents

Projet CI2 · module Cloud Computing et virtualisation · Pr. Oussama Hamal
Sujet 13 · Deux personnes · Dix jours ouvrés

Ce document est destiné aux deux personnes qui réalisent le projet. Il dit quoi faire, dans quel ordre, et surtout quoi vérifier avant de passer à l'étape suivante.

## Le premier jour

Un seul objectif : **les trois agents visibles dans la console du gestionnaire**. Rien d'autre ne compte, et rien de ce qui suit n'est testable tant que ce point n'est pas atteint.

Avant toute chose, sur l'hôte :

```
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
```

Sans ce réglage, l'indexeur démarre puis s'arrête, et le message d'erreur dans ses journaux est explicite mais il faut savoir aller le lire. C'est la panne numéro un de la première heure, et elle n'a rien à voir avec la quantité de mémoire disponible.

Ordre de démarrage, et il importe : l'indexeur d'abord, seul, et on attend qu'il réponde. Puis le gestionnaire. Puis la console. Puis le parc. Un démarrage simultané fait échouer le gestionnaire, qui essaie d'écrire dans un indexeur pas encore prêt, et on perd une heure à chercher une mauvaise cause.

Le point de contrôle du soir du jour 1 : les trois agents affichés comme actifs. Si ce n'est pas le cas, on ne continue pas, on cherche. Les causes les plus fréquentes sont une clé d'enregistrement non transmise, un nom d'hôte en doublon qui fait que le deuxième agent écrase le premier, et une erreur de nom de réseau Docker.

## Répartition à deux

Une séparation par couche, décidée au jour 1 et tenue.

**Personne A, la pile de surveillance.** Les conteneurs de la pile, les agents, les décodeurs, les règles, la mise au point avec `wazuh-logtest`. C'est la partie la plus technique et la plus longue.

**Personne B, le parc et la restitution.** Les trois hôtes Linux, l'application fictive et son journal, les cinq scripts d'attaque, Grafana avec sa source et ses tableaux de bord, le récepteur webhook, les mesures de latence.

Le point de rencontre obligatoire est le scénario 5 : B produit le journal, A écrit la règle qui le lit. Les deux doivent être dans la même pièce ce jour-là.

Chacun écrit la partie du rapport qui correspond à sa couche, au fil de l'eau et pas à la fin. Un paragraphe écrit le soir du jour où le travail a été fait est juste ; le même paragraphe écrit le dernier jour est approximatif.

## Semaine 1

### Jours 1 et 2, la pile

Les deux réseaux Docker, avec `net-soc` déclaré interne. L'indexeur, le gestionnaire, la console. Les trois hôtes du parc, chacun avec son agent.

Vérification du jour 2 : depuis un hôte du parc, une tentative de connexion vers l'indexeur doit échouer par expiration. C'est la preuve que le cloisonnement fonctionne, et c'est à capturer tout de suite parce que c'est une figure du rapport.

### Jour 3, scénarios 1 et 2

La force brute SSH puis l'élévation de privilèges. Les deux sont couverts par le jeu de règles livré, donc le travail consiste à écrire les scripts et à vérifier que l'alerte apparaît.

Chaque script écrit son heure de début dans un fichier dédié. Prendre cette habitude dès le premier script : sans cela, les latences de la section Tests ne sont pas mesurables et il faut tout refaire.

Vérification : deux alertes visibles dans la console, chacune avec son identifiant de règle noté dans un carnet. Ces identifiants serviront à la matrice.

### Jour 4, scénarios 3 et 4

Le contrôle d'intégrité en mode temps réel sur un répertoire de binaires, puis l'altération d'un fichier. Le balayage de ports depuis le conteneur attaquant, avec les journaux du pare-feu local comme source.

Le piège du jour 4 : le contrôle d'intégrité en mode périodique ne déclenche qu'au prochain cycle, qui peut être long. Il faut `realtime="yes"` sur le répertoire surveillé, sinon on conclut à tort que la détection ne fonctionne pas.

### Jour 5, le test d'effacement et la bascule

Le test de résistance à l'effacement : lancer le scénario 1, vider `/var/log/auth.log` sur l'hôte, montrer que l'alerte est toujours affichée. À filmer ou capturer, c'est une pièce de la soutenance.

Puis la bascule vers la semaine 2 : écrire l'application fictive et son journal, pour que le scénario 5 puisse commencer lundi sans temps mort.

Point de contrôle de fin de semaine 1 : quatre scénarios détectés, quatre identifiants de règle notés, le cloisonnement et l'effacement capturés. Si ce n'est pas le cas, le week-end sert à rattraper, et le scénario 5 est le seul élément qu'on ne peut pas sacrifier.

## Semaine 2, jours 1 et 2

Le scénario 5, dans cet ordre exact. Ne pas intervertir.

**Un.** L'application fictive écrit son journal. Format JSON, un enregistrement par requête, avec l'utilisateur, l'adresse source, l'identifiant de dossier demandé et le code de réponse.

**Deux.** L'agent lit ce fichier, avec `log_format` positionné à `json`. Vérifier dans la console que les événements arrivent et que les champs sont interrogeables. C'est ici qu'on constate que Wazuh décode le JSON nativement, et c'est un bon moment pour le noter dans le rapport.

**Trois.** L'attaque d'énumération : un compte légitime parcourt des centaines d'identifiants en quelques secondes, dont la plupart renvoient un refus.

**Quatre, et c'est le plus important.** Constater le silence. Aucune alerte, tableau de bord vert pendant toute l'attaque. **Capturer cet écran.** C'est la preuve que le trou existe, et sans cette capture, la correction qui suit n'a plus rien à démontrer. Beaucoup d'équipes oublient cette étape et ne peuvent plus la refaire une fois les règles écrites.

**Cinq.** Écrire la règle de base, qui qualifie un refus au niveau 3. Vérifier avec `wazuh-logtest`.

**Six.** Écrire la règle de corrélation, qui compte les refus dans une fenêtre de temps avec la même source et le même utilisateur, et monte au niveau 10 au-delà du seuil. Vérifier avec `wazuh-logtest`.

**Sept.** Relancer l'attaque. L'alerte apparaît. Capturer.

**Huit.** Le décodeur pour la variante texte du journal, celle du mode de secours de l'application. Il n'est pas indispensable à la détection, puisque le JSON est décodé nativement, mais il est indispensable au dossier : c'est le décodeur qu'on montre, avec son `prematch`, son `regex` et son `order`.

## Semaine 2, jours 3 à 5

### Jour 3, Grafana et le récepteur

La source OpenSearch pointée sur l'indexeur, avec les identifiants et le motif d'index des alertes. Deux ou trois tableaux de bord : alertes par niveau dans le temps, alertes par hôte, les dernières alertes en liste.

La règle d'alerte, avec un intervalle d'évaluation court pour que la démonstration ne fasse pas attendre le jury. Le récepteur webhook, vingt lignes de Python qui journalisent chaque notification avec son horodatage.

Vérification : relancer un scénario, et lire dans le journal du récepteur une ligne horodatée. C'est la quatrième étape de la chaîne, celle que l'énoncé appelle génération d'alertes.

### Jour 4, les mesures

Chaque scénario rejoué plusieurs fois, avec les trois horodatages relevés : début de l'attaque, production de l'alerte, arrivée de la notification. Médiane et étendue, pas une valeur unique.

Les deux scénarios négatifs : le faux positif provoqué, qui doit rester silencieux, et la variante lente du scénario 5, qui doit échapper à la règle. Les deux sont documentés comme résultats, pas comme échecs.

L'ordre de grandeur en charge, avec la phrase qui en limite la portée écrite juste à côté du chiffre.

### Jour 5, la matrice et le dossier

La matrice de détection complète, avec sa ligne négative. Les captures rassemblées et nommées. Le rapport relu par les deux personnes, y compris les parties écrites par l'autre.

La soutenance répétée une fois en entier, chronomètre en main.

## Le dépôt

```
soc-detection/
  docker-compose.yml
  net/                     deux reseaux, dont net-soc interne
  wazuh/
    manager/
      ossec.conf
      rules/
        local_rules.xml    regle de base + regle de correlation
      decoders/
        local_decoder.xml  pour la variante texte
    agent/
      ossec.conf           avec log_format json et syscheck realtime
  parc/
    hote-a/ hote-b/ hote-c/
    app-metier/            application fictive + journal
  attaques/
    01-bruteforce-ssh.sh
    02-escalade-sudo.sh
    03-integrite-binaire.sh
    04-scan-ports.sh
    05-enumeration.sh      le scenario qui porte le projet
  grafana/
    datasource.yml
    dashboards/
    alerting/
  recepteur/
    app.py                 journalise chaque notification
  mesures/
    latences.csv
    matrice-detection.md
  docs/
    rapport.md
    captures/
  README.md
```

Chaque script d'attaque commence par écrire son heure de début. Chaque capture est nommée par le scénario qu'elle illustre. Le `README` donne la séquence de démarrage et le réglage `vm.max_map_count`, parce que c'est ce qui bloque quiconque reprend le dépôt.

## Pièges et parades

**L'indexeur refuse de démarrer.** `vm.max_map_count` trop bas. Le symptôme est un conteneur qui s'arrête quelques secondes après le lancement. Lire ses journaux, pas ceux du gestionnaire.

**Démarrage simultané.** Le gestionnaire échoue parce que l'indexeur n'est pas prêt. Démarrer dans l'ordre, et attendre.

**Un agent ne se connecte pas.** Clé d'enregistrement absente, ou nom d'hôte en doublon. Deux agents avec le même nom et le second remplace le premier dans la console, ce qui donne l'illusion qu'un agent a disparu.

**Le contrôle d'intégrité ne déclenche pas.** Mode périodique au lieu de temps réel. Mettre `realtime="yes"`.

**La règle de corrélation ne déclenche jamais.** Le seuil est trop haut par rapport à ce que le script produit, ou la fenêtre de temps est plus courte que la durée de l'attaque. Compter d'abord ce que le script génère, puis choisir le seuil.

**Grafana ne voit aucune donnée.** Le motif d'index est faux, ou la plage de temps du tableau de bord ne couvre pas les alertes. Vérifier le motif dans la console native d'abord.

**Le silence du scénario 5 n'a pas été capturé.** Impossible à refaire une fois les règles écrites. C'est la seule erreur de ce plan qui ne se rattrape pas, donc la capture se fait au moment prévu et pas plus tard.

## Checklist avant la soutenance

- [ ] Les trois agents actifs dans la console
- [ ] Les cinq scénarios rejouables en une commande chacun
- [ ] Le silence du scénario 5 capturé avant correction
- [ ] L'alerte du scénario 5 capturée après correction
- [ ] Le refus de connexion du parc vers l'indexeur capturé
- [ ] L'alerte survivant à l'effacement du journal capturée
- [ ] La capture réseau montrant le canal chiffré
- [ ] La matrice de détection complète, avec sa ligne négative
- [ ] Les latences mesurées, médiane et étendue
- [ ] Les deux scénarios négatifs documentés
- [ ] Le rapport relu par les deux personnes
- [ ] La soutenance répétée une fois en entier
- [ ] Le dépôt propre, avec un `README` qui permet à un tiers de tout relancer
