#!/usr/bin/env python3
"""
Application metier fictive : consultation de dossiers administratifs.

Son seul role dans le projet est de produire un journal dans un format que le
jeu de regles livre avec Wazuh ne connait pas. C'est ce qui rend le scenario 5
possible.

Deux chemins d'ecriture :
  - nominal  : access.json, une ligne JSON par requete, decode nativement
  - degrade  : access.log, une ligne texte a plat, qui demande notre decodeur

Routes :
  GET /dossiers/<id>?user=<nom>   consultation, 200 ou 403 selon les droits
  GET /sante                      sonde
  POST /mode/degrade              bascule en ecriture texte
  POST /mode/nominal              retour en JSON
"""

import json
import os
import random
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

LOG_DIR = os.environ.get("APP_LOG_DIR", "/var/log/app-metier")
JSON_LOG = os.path.join(LOG_DIR, "access.json")
TEXT_LOG = os.path.join(LOG_DIR, "access.log")
PORT = int(os.environ.get("APP_PORT", "8080"))

# Chaque agent n'a de droits que sur sa propre plage de dossiers.
# C'est cette regle metier qui rend l'enumeration detectable : un compte qui
# sort de sa plage produit des refus, et Wazuh ne peut pas deviner cette regle.
PLAGES = {
    "m.bennani": (1, 500),
    "s.alaoui": (501, 1000),
    "k.tazi": (1001, 1500),
}

_mode = {"degrade": False}
_lock = threading.Lock()


def horodatage():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + \
           f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z"


def journaliser(user, src_ip, action, dossier_id, status, latence_ms):
    ts = horodatage()
    with _lock:
        if _mode["degrade"]:
            ligne = (f"{ts} dossiers user={user} src={src_ip} action={action} "
                     f"dossier={dossier_id} status={status}\n")
            with open(TEXT_LOG, "a", encoding="utf-8") as f:
                f.write(ligne)
        else:
            enregistrement = {
                "ts": ts,
                "app": "dossiers",
                "user": user,
                "src_ip": src_ip,
                "action": action,
                "dossier_id": dossier_id,
                "status": status,
                "latency_ms": latence_ms,
            }
            with open(JSON_LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps(enregistrement, ensure_ascii=False) + "\n")


def autorise(user, numero):
    bas, haut = PLAGES.get(user, (0, -1))
    return bas <= numero <= haut


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # on ecrit notre propre journal, pas celui de http.server

    def _repondre(self, code, corps):
        donnees = json.dumps(corps).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(donnees)))
        self.end_headers()
        self.wfile.write(donnees)

    def do_POST(self):
        chemin = urlparse(self.path).path
        if chemin == "/mode/degrade":
            _mode["degrade"] = True
            self._repondre(200, {"mode": "degrade"})
        elif chemin == "/mode/nominal":
            _mode["degrade"] = False
            self._repondre(200, {"mode": "nominal"})
        else:
            self._repondre(404, {"erreur": "route inconnue"})

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/sante":
            self._repondre(200, {"etat": "ok", "mode": "degrade" if _mode["degrade"] else "nominal"})
            return

        if not url.path.startswith("/dossiers/"):
            self._repondre(404, {"erreur": "route inconnue"})
            return

        debut = time.time()
        dossier_id = url.path.split("/dossiers/", 1)[1]
        params = parse_qs(url.query)
        user = params.get("user", ["anonyme"])[0]
        src_ip = self.headers.get("X-Forwarded-For") or self.client_address[0]

        try:
            numero = int(dossier_id.replace("DOS-", ""))
        except ValueError:
            numero = -1

        permis = autorise(user, numero)
        status = 200 if permis else 403
        latence = int((time.time() - debut) * 1000) + random.randint(3, 18)

        journaliser(user, src_ip, "consult", dossier_id, status, latence)
        self._repondre(status, {"dossier": dossier_id, "autorise": permis})


def trafic_legitime():
    """
    Bruit de fond : des agents qui consultent leurs propres dossiers.

    Sans ce trafic, le tableau de bord est vide et le test de faux positif n'a
    aucun sens, parce qu'il n'y a rien a distinguer d'une attaque.
    """
    time.sleep(5)
    while True:
        user = random.choice(list(PLAGES))
        bas, haut = PLAGES[user]
        numero = random.randint(bas, haut)
        # une fois sur vingt, l'agent se trompe de dossier : c'est normal
        if random.random() < 0.05:
            numero = random.randint(1, 1500)
        status = 200 if autorise(user, numero) else 403
        journaliser(user, f"172.30.0.{random.randint(20, 40)}", "consult",
                    f"DOS-{numero:06d}", status, random.randint(8, 45))
        time.sleep(random.uniform(1.5, 4.0))


if __name__ == "__main__":
    os.makedirs(LOG_DIR, exist_ok=True)
    threading.Thread(target=trafic_legitime, daemon=True).start()
    print(f"[app-metier] ecoute sur 0.0.0.0:{PORT}, journal {JSON_LOG}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
