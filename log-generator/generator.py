import socket, time, random, datetime

ETUDIANTS = [
    {"nom": "AZIAGBEGNON", "prenom": "Koami Jonathan",              "groupe": 1, "login": "k.aziagbegnon"},
    {"nom": "BANKATI",      "prenom": "Mabibè",                      "groupe": 1, "login": "m.bankati"},
    {"nom": "KLOUGAN",      "prenom": "Kossi Samson",                "groupe": 2, "login": "k.klougan"},
    {"nom": "de SOUZA",     "prenom": "Felicia Odette",              "groupe": 2, "login": "f.desouza"},
    {"nom": "DOH-BARRY",    "prenom": "Harmonia",                    "groupe": 3, "login": "h.dohbarry"},
    {"nom": "DONOU",        "prenom": "Séfako Félicité",             "groupe": 3, "login": "s.donou"},
    {"nom": "EDIM",         "prenom": "Joseph-Kingsley Chris-Joris", "groupe": 4, "login": "j.edim"},
    {"nom": "FOIYEME",      "prenom": "Nounifou",                    "groupe": 4, "login": "n.foiyeme"},
    {"nom": "FOLLY",        "prenom": "Kokou Claude",                "groupe": 5, "login": "k.folly"},
    {"nom": "KUEVIAKOE",    "prenom": "Ekue Ormad Trésor",           "groupe": 5, "login": "e.kueviakoe"},
    {"nom": "LAWSON-DJITO", "prenom": "Latévi Steven Antoine",       "groupe": 6, "login": "l.lawsondjito"},
    {"nom": "POTCHONA",     "prenom": "Essosolam Justin",            "groupe": 6, "login": "e.potchona"},
    {"nom": "AMEDON",       "prenom": "Roland",                      "groupe": 6, "login": "r.amedon"},
]

COURS = [
    {"code": "BD101",  "nom": "Big Data",   "page": "/cours/bigdata",    "tp": "tp_hadoop", "prof": "AMADJI DOSSOU"},
    {"code": "ALG101", "nom": "Algorithme", "page": "/cours/algorithme", "tp": "tp_tri",    "prof": "Prof. Kpoti"},
    {"code": "MGT101", "nom": "Management", "page": "/cours/management", "tp": "tp_projet", "prof": "Prof. Agbeko"},
    {"code": "JAV101", "nom": "Java",       "page": "/cours/java",       "tp": "tp_poo",    "prof": "Prof. Dossou"},
]

INFO = [
    lambda e, c: f"[{c['code']}] {e['login']} (Gr.{e['groupe']}) connecté → {c['page']}",
    lambda e, c: f"[{c['code']}] Cours {c['nom']} ({c['prof']}) consulté par {e['prenom']} {e['nom']} (234ms)",
    lambda e, c: f"[{c['code']}] Note soumise — {e['login']} : {c['nom']} = {random.randint(10,20)}/20",
    lambda e, c: f"[{c['code']}] TP {c['tp']}.zip uploadé par {e['login']} (Groupe {e['groupe']})",
    lambda e, c: f"[{c['code']}] Groupe {e['groupe']} : rapport {c['nom']} soumis par {e['prenom']}",
    lambda e, c: f"[{c['code']}] Exercice {c['nom']} validé — {e['nom']} {e['prenom']}",
    lambda e, c: f"[{c['code']}] PDF cours_{c['nom'].lower()}.pdf téléchargé par {e['login']}",
]

WARN = [
    lambda e, c: f"[{c['code']}] Connexion échouée : {e['login']} ({random.randint(2,4)}ème essai)",
    lambda e, c: f"[{c['code']}] Devoir {c['nom']} non rendu — {e['nom']} {e['prenom']} (délai dépassé)",
    lambda e, c: f"[{c['code']}] Session {e['login']} expirée pendant TP {c['tp']}",
    lambda e, c: f"[{c['code']}] Charge CPU élevée pendant examen {c['nom']} : {random.randint(78,95)}%",
    lambda e, c: f"[{c['code']}] Tentative soumission en double — {e['login']} : {c['nom']}",
]

ERROR = [
    lambda e, c: f"[{c['code']}] Upload échoué : {e['login']}_{c['tp']}.zip — quota dépassé",
    lambda e, c: f"[{c['code']}] Timeout lecture HDFS pendant cours {c['nom']} (30s)",
    lambda e, c: f"[{c['code']}] Fichier corrompu : {e['login']}_rapport_{c['nom'].lower()}.pdf",
    lambda e, c: f"[{c['code']}] DataNode unreachable — perte logs {c['nom']} Groupe {e['groupe']}",
    lambda e, c: f"[{c['code']}] Erreur notation : etudiant_id={e['login']} introuvable en base",
]


def send():
    while True:
        try:
            with socket.socket() as s:
                s.connect(("flume", 44444))
                print("[generator] Connecté à Flume :44444", flush=True)
                while True:
                    e = random.choice(ETUDIANTS)
                    c = random.choice(COURS)
                    r = random.random()
                    if r < 0.70:
                        level, pool = "INFO", INFO
                    elif r < 0.90:
                        level, pool = "WARN", WARN
                    else:
                        level, pool = "ERROR", ERROR
                    msg = random.choice(pool)(e, c)
                    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                    line = f"[{level}] {ts} - {msg}\n"
                    s.sendall(line.encode())
                    time.sleep(1)
        except Exception as ex:
            print(f"[generator] Reconnexion dans 5s : {ex}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    send()
