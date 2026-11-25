#!/usr/bin/env python3
"""
Depouillement des mesures de latence.

Rapproche trois horodatages par scenario :
  1. debut de l'attaque      -> mesures/starts.log, ecrit par le script lui-meme
  2. production de l'alerte  -> export de l'indexeur, mesures/alertes.json
  3. arrivee de la notification -> journal du recepteur, mesures/notifications.log

Produit mesures/latences.csv et un resume en mediane et etendue, parce qu'une
valeur unique n'a aucun sens sur un systeme dont la charge varie.

Usage :
  docker compose exec wazuh-indexer curl -sk -u admin:$INDEXER_PASSWORD \
    "https://localhost:9200/wazuh-alerts-*/_search?size=500&sort=timestamp:desc" \
    > mesures/alertes.json
  docker compose logs recepteur --no-log-prefix > mesures/notifications.log
  python3 mesures/depouiller.py
"""

import csv
import json
import os
import statistics
import sys
from datetime import datetime

ICI = os.path.dirname(os.path.abspath(__file__))


def lire_ts(valeur):
    if not valeur:
        return None
    valeur = valeur.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(valeur)
    except ValueError:
        return None


def charger_debuts():
    chemin = os.path.join(ICI, "starts.log")
    if not os.path.exists(chemin):
        print(f"manquant : {chemin}", file=sys.stderr)
        return []
    debuts = []
    for ligne in open(chemin, encoding="utf-8"):
        morceaux = ligne.split(None, 2)
        if len(morceaux) >= 3 and morceaux[1] == "debut":
            t = lire_ts(morceaux[0])
            if t:
                debuts.append({"scenario": morceaux[2].strip(), "debut": t})
    return debuts


def charger_alertes():
    chemin = os.path.join(ICI, "alertes.json")
    if not os.path.exists(chemin):
        print(f"manquant : {chemin}", file=sys.stderr)
        return []
    donnees = json.load(open(chemin, encoding="utf-8"))
    alertes = []
    for hit in donnees.get("hits", {}).get("hits", []):
        src = hit.get("_source", {})
        t = lire_ts(src.get("timestamp"))
        if not t:
            continue
        alertes.append({
            "t": t,
            "regle": src.get("rule", {}).get("id"),
            "niveau": src.get("rule", {}).get("level"),
            "description": src.get("rule", {}).get("description", ""),
            "agent": src.get("agent", {}).get("name", ""),
        })
    return sorted(alertes, key=lambda a: a["t"])


def charger_notifications():
    chemin = os.path.join(ICI, "notifications.log")
    if not os.path.exists(chemin):
        return []
    notifs = []
    for ligne in open(chemin, encoding="utf-8"):
        ligne = ligne.strip()
        if not ligne.startswith("{"):
            continue
        try:
            n = json.loads(ligne)
        except json.JSONDecodeError:
            continue
        t = lire_ts(n.get("recu_le"))
        if t:
            notifs.append({"t": t, "titre": n.get("titre", "")})
    return sorted(notifs, key=lambda n: n["t"])


def premier_apres(elements, instant, fenetre_s=300):
    for e in elements:
        delta = (e["t"] - instant).total_seconds()
        if 0 <= delta <= fenetre_s:
            return e, delta
    return None, None


def main():
    debuts = charger_debuts()
    alertes = charger_alertes()
    notifs = charger_notifications()

    if not debuts:
        print("Aucun debut d'attaque. Les scripts ecrivent-ils dans starts.log ?")
        return 1

    lignes = []
    for d in debuts:
        alerte, lat_detect = premier_apres(alertes, d["debut"])
        notif, lat_notif = (None, None)
        if alerte:
            notif, lat_notif = premier_apres(notifs, alerte["t"], 120)
        lignes.append({
            "scenario": d["scenario"],
            "debut_attaque": d["debut"].isoformat(),
            "regle": alerte["regle"] if alerte else "",
            "niveau": alerte["niveau"] if alerte else "",
            "agent": alerte["agent"] if alerte else "",
            "latence_detection_s": round(lat_detect, 2) if lat_detect is not None else "",
            "latence_notification_s": round(lat_notif, 2) if lat_notif is not None else "",
            "detecte": "oui" if alerte else "non",
        })

    sortie = os.path.join(ICI, "latences.csv")
    with open(sortie, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(lignes[0].keys()))
        w.writeheader()
        w.writerows(lignes)

    print(f"{len(lignes)} scenarios depouilles -> {sortie}\n")
    print(f"{'scenario':<42} {'regle':>7} {'niv':>4} {'detect s':>9} {'notif s':>8}")
    print("-" * 75)
    for l in lignes:
        print(f"{l['scenario'][:42]:<42} {str(l['regle']):>7} {str(l['niveau']):>4} "
              f"{str(l['latence_detection_s']):>9} {str(l['latence_notification_s']):>8}")

    mesurees = [l["latence_detection_s"] for l in lignes
                if isinstance(l["latence_detection_s"], float)]
    if mesurees:
        print()
        print(f"Latence de detection : mediane {statistics.median(mesurees):.2f} s, "
              f"etendue {min(mesurees):.2f} a {max(mesurees):.2f} s "
              f"sur {len(mesurees)} mesures")
        print("A reporter tel quel dans le rapport. Pas de moyenne, pas de valeur unique.")

    non_detectes = [l["scenario"] for l in lignes if l["detecte"] == "non"]
    if non_detectes:
        print("\nNon detectes (attendu pour 06 et 07) :")
        for s in non_detectes:
            print(f"  - {s}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
