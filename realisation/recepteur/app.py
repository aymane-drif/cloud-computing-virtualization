#!/usr/bin/env python3
"""
Recepteur de notifications.

Remplace le courriel, qui demanderait un relais SMTP sortant et rendrait la
demonstration dependante du reseau de la salle.

Son seul interet pour le projet est l'horodatage : c'est lui qui donne la
troisieme colonne de la table de latences, celle de la notification.
"""

import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8000"))
JOURNAL = os.environ.get("JOURNAL", "/var/log/recepteur/notifications.log")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_POST(self):
        recu = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + \
               f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z"
        taille = int(self.headers.get("Content-Length", "0"))
        brut = self.rfile.read(taille).decode("utf-8", "replace") if taille else ""

        try:
            charge = json.loads(brut)
            titre = charge.get("title") or charge.get("message") or "alerte"
            etat = charge.get("status", "?")
        except json.JSONDecodeError:
            titre, etat = brut[:120] or "alerte", "?"

        ligne = json.dumps({"recu_le": recu, "etat": etat, "titre": titre,
                            "charge": brut[:2000]}, ensure_ascii=False)

        with open(JOURNAL, "a", encoding="utf-8") as f:
            f.write(ligne + "\n")
        print(f"[recepteur] {recu}  {etat}  {titre}", flush=True)

        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")


if __name__ == "__main__":
    os.makedirs(os.path.dirname(JOURNAL), exist_ok=True)
    print(f"[recepteur] ecoute sur 0.0.0.0:{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
