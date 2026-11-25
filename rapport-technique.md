# Rapport technique · Surveillance et détection d'incidents

Projet CI2 · module Cloud Computing et virtualisation · Pr. Oussama Hamal
Sujet 13 · Deux personnes · Deux semaines · Aucun coût

Un parc Linux de trois hôtes sous surveillance, cinq scénarios d'attaque scriptés, et une matrice qui dit ce que la chaîne détecte et ce qu'elle manque. Le sujet 13 demande un système de surveillance, de détection et d'alerte : la difficulté réelle n'est pas de le faire fonctionner, puisque Wazuh arrive avec plusieurs milliers de règles, mais de prouver qu'on l'a compris.

Ce rapport traite cette difficulté de front : un cinquième scénario frappe une application dont le format de journal est inconnu de l'outil, le jeu de règles livré ne voit rien, et nous écrivons le décodeur et les règles qui comblent ce trou.

## Étude et analyse

Un parc de serveurs Linux produit des journaux en permanence, et ces journaux posent quatre problèmes qui n'ont rien à voir entre eux.

Ils sont **dispersés** : chaque machine garde les siens, et une intrusion qui touche trois machines se lit à trois endroits. Ils sont **volumineux** : personne ne lit `/var/log/auth.log` ligne par ligne, donc un événement important est noyé. Ils sont **locaux** : un attaquant qui obtient les droits d'administration efface les traces de son passage, et la preuve disparaît avec elles. Et ils sont **muets** : un journal ne réveille personne, il attend d'être lu.

Une chaîne de surveillance répond aux quatre, mais par quatre mécanismes distincts qu'il faut savoir nommer séparément : la centralisation, la qualification par règles, l'expédition immédiate hors de la machine surveillée, et la notification.

Le troisième mérite d'être souligné. L'agent envoie chaque événement au gestionnaire au moment où il se produit, et non à la lecture : quand l'attaquant vide `/var/log`, l'événement est déjà parti. C'est le seul mécanisme de la chaîne qui protège la preuve elle-même, et c'est la réponse à la question de savoir pourquoi un agent plutôt qu'une lecture à distance périodique.

### Objectifs, formulés comme vérifiables

| Verbe de l'énoncé | Objectif | Vérification |
| --- | --- | --- |
| Surveiller | Trois hôtes Linux, journaux système, journaux de service et contrôle d'intégrité, sur un canal chiffré | Agents actifs dans la console ; capture réseau illisible |
| Détecter | Cinq scénarios scriptés, dont un volontairement non couvert par le jeu de règles livré | Matrice de détection, colonne ruleset par défaut |
| Alerter | Tableaux de bord alimentés par l'indexeur, une règle évaluée périodiquement, un destinataire qui horodate | Journal du récepteur, comparé à l'heure de l'attaque |

### Les deux besoins non fonctionnels qui font la différence

L'événement quitte l'hôte immédiatement. La démonstration prend dix secondes : on lance la force brute SSH, on vide `/var/log/auth.log` sur l'hôte, et l'alerte est toujours affichée. Cela montre d'un coup pourquoi la centralisation n'est pas une commodité mais une mesure de sécurité.

Le parc ne joint pas l'indexeur. Un hôte compromis ne doit pas pouvoir atteindre la base des alertes pour les altérer. C'est une propriété d'architecture, elle se lit sur le diagramme de déploiement, et elle se vérifie par un refus de connexion.

### Ce que le projet ne prétend pas faire

Pas de réponse active automatique. Le mécanisme existe et se configure en quelques lignes, mais une règle de blocage déclenchée par un faux positif coupe l'accès d'un administrateur légitime. Une règle écrite dans la semaine et testée sur cinq scénarios n'a pas le droit de décider seule. Nous décrivons le mécanisme, nous ne l'armons pas.

Pas de notification par courriel ni par messagerie : l'une demande un relais SMTP sortant, l'autre un compte extérieur, et les deux produiraient une démonstration dépendante du réseau de la salle.

Pas de mesure de tenue en charge au-delà d'un ordre de grandeur, dont la portée est discutée en section Tests.

## Architecture technique

Trois vues normalisées, parce qu'un jury pose des questions à trois échelles. Les figures complètes sont dans le dossier de projet ; ce rapport en donne la lecture.

### Vue de contexte, modèle C4 niveau 1

Le système étudié est la chaîne de surveillance ; le parc est un système voisin qu'elle observe. Cette frontière empêche le projet de dériver vers de l'administration système, et elle justifie que le parc soit minimal.

L'attaquant figure dans le schéma, étiqueté banc d'essai. Ce n'est pas une menace modélisée, c'est un instrument de mesure : il produit à la demande les événements que la chaîne doit qualifier, et il les horodate. Sans lui, il n'y aurait rien à détecter et donc rien à mesurer. Le déclarer comme instrument plutôt que comme menace évite une confusion que beaucoup de dossiers de sécurité entretiennent.

### Vue des conteneurs, modèle C4 niveau 2

| Conteneur | Rôle | Pourquoi il est là |
| --- | --- | --- |
| wazuh-manager | Reçoit les événements, les décode, applique les règles, produit les alertes | Le seul endroit où la détection a lieu. Tout le reste transporte ou affiche. |
| wazuh-indexer | Stocke et rend recherchables les alertes | Source unique de vérité. Les deux interfaces la lisent, aucune ne détient de copie. |
| wazuh-dashboard | Console native d'investigation | Sert à régler les règles pendant le développement. |
| Grafana | Tableaux de bord et règle d'alerte | Nommé dans l'énoncé. Porte la restitution et la génération d'alertes. |
| récepteur | Service HTTP qui journalise chaque notification | Remplace le courriel, et donne un horodatage de notification exploitable. |
| 3 agents | Lisent les journaux, calculent les sommes de contrôle, expédient | Dans le parc, pas dans la pile. Ce sont eux qui font sortir la preuve. |

Le choix de deux interfaces n'est pas une redondance, et savoir le dire vaut un point. La console native connaît la structure des alertes Wazuh : c'est un outil d'investigation, utilisé pour plonger dans un événement et mettre une règle au point. Grafana agrège, compare dans le temps, évalue une condition et notifie : c'est un outil de restitution et d'alerting. Nous réglons dans la première et nous présentons dans la seconde.

### Vue de déploiement, UML 2.5

Cette vue porte la seule décision de sécurité qui soit structurelle plutôt qu'ajoutée. Deux réseaux Docker séparés : `net-parc`, où vivent les hôtes surveillés et l'attaquant, et `net-soc`, déclaré `internal: true`, où vivent l'indexeur et les interfaces.

Le gestionnaire est le seul conteneur attaché aux deux. Il reçoit les événements d'un côté et écrit les alertes de l'autre. Aucun hôte du parc n'a de route vers l'indexeur : un hôte compromis peut mentir sur ce qu'il envoie, il ne peut pas effacer ce qui est déjà stocké.

Cette décision vaut mieux qu'une liste de durcissements. On peut durcir une machine par vingt réglages, et chacun peut être oublié. Un cloisonnement réseau est une propriété de la topologie : il ne dépend pas d'un réglage juste, il découle de la structure, et il se vérifie en direct par une connexion qui expire.

### Limites de cette architecture

Un seul gestionnaire : sa panne arrête la détection, et les agents gardent leurs événements en file d'attente pendant un temps limité avant d'en perdre. Un seul nœud d'indexation : les alertes ne sont pas répliquées, et le volume stocké est borné par le disque du poste.

Et la limite la plus importante, parce qu'elle est conceptuelle : la chaîne détecte ce que les règles décrivent. Une attaque qui ne ressemble à aucune règle ne produit aucune alerte, et le tableau de bord reste vert. Le cinquième scénario existe précisément pour rendre cette limite visible au lieu de la laisser implicite.

## Choix technologiques

L'énoncé nomme quatre technologies : Linux, Wazuh, Grafana, Docker. Le projet s'y tient, et chaque ajout est justifié par un besoin de la section Tests.

| Technologie | Rôle | Justification | Statut |
| --- | --- | --- | --- |
| Linux | Les trois hôtes surveillés | Nommé dans l'énoncé. Fournit les journaux système et les mécanismes de contrôle d'intégrité. | Énoncé |
| Wazuh | Agents, gestionnaire, décodeurs, règles, indexeur | Nommé dans l'énoncé. Porte les étapes 1 à 3 de la chaîne. | Énoncé |
| Grafana | Tableaux de bord et règle d'alerte | Nommé dans l'énoncé. Porte l'étape 4, celle que l'énoncé appelle génération d'alertes. | Énoncé |
| Docker | Toute la pile et tout le parc | Nommé dans l'énoncé. Permet aussi les deux réseaux cloisonnés. | Énoncé |
| Source OpenSearch | Connecte Grafana à l'indexeur | Greffon de Grafana. L'indexeur Wazuh est un OpenSearch, donc c'est la source prévue. | Greffon |
| récepteur maison | Reçoit et horodate les notifications | Vingt lignes de Python. Sans lui, la latence de notification n'est pas mesurable. | Écrit par nous |
| Scripts d'attaque | Produisent les cinq scénarios | Boucles shell et `curl`. Chacun écrit son heure de début, référence des latences. | Écrit par nous |

### Ce qui a été écarté, et pourquoi

Pas de pile Elastic séparée. L'indexeur livré avec Wazuh est déjà un moteur de recherche de cette famille : en ajouter une seconde dupliquerait le stockage et doublerait la consommation mémoire sans rien démontrer de plus.

Pas de réponse active, pour la raison donnée en Étude et analyse. Pas de notification par courriel ni par messagerie, pour éviter une démonstration qui dépend du réseau de la salle.

### Consommation mémoire, chiffrée à l'avance

Avec 24 Go disponibles sur le poste, la pile complète tient sans arbitrage. L'ordre de grandeur, utile pour répondre à la question en soutenance :

```
wazuh-indexer      2 a 3 Go   tas Java, poste dominant
wazuh-manager      1 a 1,5 Go
wazuh-dashboard    0,5 a 1 Go
grafana            ~200 Mo
3 agents + parc    ~150 Mo chacun
recepteur          negligeable
                   ---------
total              5 a 6,5 Go
```

Un réglage reste obligatoire quelle que soit la mémoire disponible : `vm.max_map_count` doit valoir au moins 262144 sur l'hôte, sinon l'indexeur refuse de démarrer. C'est la panne la plus fréquente de la première heure, et elle n'a rien à voir avec la quantité de RAM.

## Les cinq scénarios d'attaque

Le cœur du projet. Chaque scénario est un script qui écrit son heure de début dans un fichier, pour que la latence de détection soit mesurée et non estimée.

| # | Scénario | Source observée | Mécanisme de détection | Règle |
| --- | --- | --- | --- | --- |
| 1 | Force brute SSH, 20 tentatives en 30 s | `/var/log/auth.log` | Corrélation par fréquence, même IP source | Jeu livré |
| 2 | Élévation de privilèges, `sudo` refusé puis accepté | `/var/log/auth.log` | Règles chaînées, `if_matched_sid` | Jeu livré |
| 3 | Altération d'un binaire système | Contrôle d'intégrité, mode temps réel | Somme de contrôle modifiée | Jeu livré |
| 4 | Balayage de ports depuis l'attaquant | Journaux du pare-feu local | Fréquence, ports distincts | Jeu livré |
| 5 | Application maison, format de journal inconnu | `/var/log/app-metier/access.json` | **Décodeur et règles écrits par nous** | **Aucune** |

### Le scénario 5, et pourquoi il porte le projet

Les quatre premiers scénarios sont détectés par des règles que Wazuh livre. C'est utile : cela montre que la chaîne fonctionne de bout en bout, et cela donne quatre latences à mesurer. Mais cela ne prouve pas que nous avons compris comment la détection fonctionne. N'importe qui peut installer Wazuh et déclencher une force brute.

Le scénario 5 introduit une application fictive, un service interne de consultation de dossiers, qui écrit un journal dans un format que l'outil ne connaît pas. L'attaque consiste en une énumération : un compte légitime parcourt des centaines d'identifiants de dossiers en quelques secondes, dont la plupart renvoient un refus. C'est le profil d'une exfiltration par balayage, et c'est précisément le genre d'attaque qu'aucun jeu de règles génériques ne peut connaître, parce qu'elle dépend de la logique métier de l'application.

Avec le jeu livré, le résultat est un silence complet. Les événements arrivent au gestionnaire, mais aucune règle ne les concerne, donc aucune alerte n'est produite. **Le tableau de bord reste vert pendant l'attaque.** C'est la démonstration la plus importante de la soutenance, et elle doit être montrée avant la correction.

### Le décodeur

Première surprise du projet, et il faut savoir l'expliquer : Wazuh décode le JSON nativement. Si l'agent lit le fichier avec `log_format` positionné à `json`, chaque clé devient un champ interrogeable sans qu'une seule ligne de décodeur soit écrite.

Nous écrivons donc le décodeur pour la variante texte du même journal, celle produite par le mode de secours de l'application, et nous documentons les deux chemins. Cela donne le décodeur à montrer, avec son `prematch`, son `regex` et son `order`, et cela donne surtout la bonne réponse à la question de soutenance : pourquoi n'avez-vous pas écrit de décodeur pour le JSON ? Parce qu'il n'en faut pas, et c'est un point qu'un étudiant qui a seulement suivi un tutoriel ne sait pas.

### Les règles

C'est là que tout le travail se concentre, et c'est l'inverse de ce qu'on attend.

Une règle de base qualifie un refus d'accès au niveau 3, informatif. Une règle de corrélation compte ces refus : au-delà d'un seuil dans une fenêtre de temps donnée, avec la même adresse source et le même utilisateur, le niveau monte à 10 et l'alerte est produite. Le choix du seuil est un arbitrage explicite entre faux positifs et détection tardive, et nous le documentons avec le raisonnement plutôt qu'avec une valeur sortie de nulle part.

Chaque règle est mise au point avec `wazuh-logtest`, qui prend une ligne de journal et affiche le décodeur retenu, les champs extraits et la règle déclenchée. C'est l'outil qui transforme l'écriture de règles en travail méthodique au lieu d'essais successifs.

## Réalisation

Deux semaines, deux personnes, une répartition par couche.

### Semaine 1

Mise en place de la pile : les deux réseaux Docker, l'indexeur avec son réglage `vm.max_map_count`, le gestionnaire, la console, les trois hôtes du parc avec leurs agents. Le point de passage obligatoire du premier jour est la visibilité des trois agents dans la console, parce que tant qu'un agent ne se connecte pas, rien de ce qui suit ne peut être testé.

Puis les quatre premiers scénarios, un par un, chacun validé par une alerte visible avant de passer au suivant. Cette discipline évite la situation où quatre scripts sont écrits et aucun ne fonctionne, sans savoir lequel est en cause.

### Semaine 2

Le scénario 5, dans l'ordre suivant : l'application fictive et son journal, l'attaque d'énumération, la constatation du silence et sa capture, puis le décodeur, puis les règles, puis la validation par `wazuh-logtest`, puis la détection en bout de chaîne.

Ensuite Grafana : source OpenSearch, tableaux de bord, règle d'alerte avec un intervalle d'évaluation court, récepteur webhook. Et enfin la matrice de détection, les mesures de latence, le dossier et la soutenance.

### Répartition

La séparation est franche. Une personne tient la pile de surveillance et les règles : conteneurs, agents, décodeur, règles, mise au point. L'autre tient le parc et la restitution : hôtes, application fictive, scripts d'attaque, Grafana, récepteur, mesures.

Les deux se rejoignent sur le scénario 5, qui est le seul endroit où les deux couches doivent être écrites ensemble : l'un produit le journal, l'autre écrit la règle qui le lit.

## Sécurité

### Le cloisonnement, décision structurelle

Déjà décrit en Architecture. Il se vérifie en direct : depuis un hôte du parc, une tentative de connexion vers l'indexeur expire. C'est une démonstration de dix secondes qui vaut plus qu'un paragraphe.

### Le chiffrement du canal agent-gestionnaire

Les agents communiquent avec le gestionnaire sur un canal chiffré avec une clé propre à chaque agent, établie à l'enregistrement. Sans cela, les journaux circuleraient en clair sur le réseau du parc, et un attaquant placé sur ce réseau pourrait les lire, ou pire, injecter de faux événements pour noyer les vrais.

La vérification est une capture réseau : le trafic entre un hôte et le gestionnaire est illisible. C'est une capture d'écran à mettre dans le dossier.

### Les droits de l'agent

L'agent lit des journaux et calcule des sommes de contrôle. Dans un conteneur, il reçoit le point de montage en lecture seule, de sorte qu'une compromission de l'agent ne permette pas de modifier ce qu'il surveille. C'est le principe du moindre privilège appliqué à un composant de sécurité, ce qui est souvent oublié : un outil de surveillance est lui-même une surface d'attaque.

### Ce qui n'est pas fait, et pourquoi

Pas de réponse active, pour la raison déjà donnée. Pas de signature des alertes stockées : l'indexeur est inaccessible depuis le parc, ce qui est la protection retenue, mais un attaquant qui atteindrait le réseau de supervision pourrait altérer les alertes. Le dire est plus honnête que de le taire.

Pas de gestion des secrets au-delà des variables d'environnement du fichier de composition, et nous notons que dans un contexte réel, cela relèverait d'un coffre.

## Tests et validation

### La matrice de détection

Le livrable central. Pour chacun des cinq scénarios : la source du journal, la règle déclenchée, le niveau, la latence mesurée, et une colonne qui indique si le jeu de règles livré suffit.

Cette matrice contient une ligne où la réponse est non, et c'est ce qui la rend crédible. Un tableau où tout est vert ne prouve rien d'autre que l'absence de test du cas difficile.

### Les mesures de latence

Trois horodatages par scénario : l'heure de début de l'attaque, écrite par le script lui-même ; l'heure de production de l'alerte, lue dans l'indexeur ; l'heure d'arrivée de la notification, lue dans le journal du récepteur.

Les deux latences qui en découlent, détection et notification, sont mesurées sur plusieurs répétitions, et nous donnons la médiane et l'étendue plutôt qu'une valeur unique. Une latence unique n'a pas de sens sur un système dont la charge varie.

### Le test de résistance à l'effacement

Celui qui fait le plus d'effet et qui tient en trois commandes : lancer le scénario 1, vider `/var/log/auth.log` sur l'hôte, montrer que l'alerte est toujours là.

Il valide la propriété d'expédition immédiate, et il est de loin la meilleure réponse à la question de savoir pourquoi un agent plutôt qu'une collecte périodique à distance.

### L'ordre de grandeur en charge

Un générateur produit un volume croissant d'événements par seconde, et nous observons jusqu'où le gestionnaire suit avant que la file d'attente ne grossisse.

Portée de ce test, à énoncer clairement : c'est une mesure sur un poste de travail, avec des conteneurs partageant le même disque. Le chiffre obtenu ne se transpose pas à un déploiement réel. Il sert à savoir si notre démonstration tient, et à montrer que nous savons qu'un tel système a une limite.

### Les deux scénarios négatifs

Un faux positif provoqué : un administrateur légitime se trompe trois fois de mot de passe. La chaîne doit rester silencieuse, ce qui valide le seuil de la règle de fréquence.

Une attaque hors couverture : une variante du scénario 5 qui contourne notre propre règle, par exemple une énumération plus lente que la fenêtre de corrélation. Elle n'est pas détectée, et nous le documentons. Cela montre qu'une règle de détection a un périmètre, et que connaître ce périmètre fait partie du travail.

## Bilan

### Ce que le projet démontre

Les quatre mécanismes de la chaîne, nommés et vérifiés séparément. Un cloisonnement réseau qui protège la base des alertes par la structure plutôt que par un réglage. Une expédition immédiate dont l'effet est démontré par un effacement de journaux. Et un décodeur avec ses règles, écrits pour un format que l'outil ne connaissait pas, avec le silence initial capturé comme preuve du besoin.

### Les trois points forts à défendre en soutenance

Le scénario 5 avec son silence puis sa détection : c'est la seule partie du projet qu'un tutoriel ne donne pas.

Le fait que le JSON ne demande aucun décodeur : contre-intuitif, et révélateur d'une lecture réelle de la documentation.

La matrice avec sa ligne négative et le scénario de contournement : un projet de détection qui annonce son propre angle mort est plus solide qu'un projet qui affiche cinq alertes vertes.

### Les limites assumées

Un gestionnaire et un nœud d'indexation uniques, donc aucune tolérance de panne. Pas de réponse active. Une mesure de charge valable sur le poste et nulle part ailleurs. Et la limite de fond : la détection est bornée par les règles, et nous l'avons mesurée au lieu de la supposer.

### Ce qu'une suite ajouterait

Un deuxième nœud d'indexation pour la réplication des alertes. Un coffre pour les secrets. Un enrichissement des alertes par des indicateurs de compromission externes. Et une mise à l'épreuve des règles par une personne qui ne les a pas écrites, ce qui est la seule façon honnête de trouver les angles morts restants.
