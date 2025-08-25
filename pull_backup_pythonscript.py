#!/usr/bin/env python3
"""
pull_backup.py
Script de sauvegarde incrémentielle (pull) en Python
- Récupère la liste des paquets installés
- Fait une sauvegarde incrémentielle avec rsync --link-dest
- Met à jour un lien "latest"
- Supprime les sauvegardes plus anciennes que X jours

Auteur : [Ton Nom]
Date : 2025-08-25
"""

import os
import subprocess
import datetime
import shutil
from pathlib import Path

# === VARIABLES ===
REMOTE_HOST = "user@IP_DE_LA_MACHINE_SOURCE"  # machine à sauvegarder
REMOTE_PATH = "/"                             # chemin distant à sauvegarder
LOCAL_BACKUP_ROOT = Path("/chemin/vers/destination")  # répertoire local de sauvegarde
RETENTION_DAYS = 7                            # nombre de jours de sauvegarde à conserver

# === PATHS ===
DATE = datetime.date.today().strftime("%Y-%m-%d")
BACKUP_DIR = LOCAL_BACKUP_ROOT / DATE
LATEST_LINK = LOCAL_BACKUP_ROOT / "latest"
PKG_LIST = BACKUP_DIR / "package-list.txt"

# === COMMANDES ===
EXCLUDES = [
    "/dev/*", "/proc/*", "/sys/*", "/tmp/*",
    "/run/*", "/mnt/*", "/media/*", "/lost+found"
]

def run_cmd(cmd: list, capture=False):
    """Exécute une commande shell en affichant la sortie."""
    try:
        if capture:
            result = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
            return result.strip()
        else:
            subprocess.check_call(cmd)
    except subprocess.CalledProcessError as e:
        print(f"[ERREUR] Commande échouée : {' '.join(cmd)}")
        print(e.output if hasattr(e, "output") else str(e))
        raise


def main():
    print(f"[INFO] Démarrage sauvegarde {DATE} depuis {REMOTE_HOST}")

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    # === 1. Sauvegarde de la liste des paquets ===
    print("[INFO] Récupération de la liste des paquets...")
    pkg_cmd = ["ssh", REMOTE_HOST, "dpkg --get-selections"]
    with open(PKG_LIST, "w") as f:
        result = run_cmd(pkg_cmd, capture=True)
        f.write(result + "\n")

    # === 2. Détermination de la sauvegarde précédente ===
    if LATEST_LINK.exists() and LATEST_LINK.is_dir():
        link_dest = f"--link-dest={LATEST_LINK.resolve()}"
        print(f"[INFO] Sauvegarde incrémentielle (comparaison avec {LATEST_LINK})")
    else:
        link_dest = ""
        print("[INFO] Première sauvegarde complète")

    # === 3. Rsync incrémentiel ===
    rsync_cmd = [
        "rsync", "-aAXHv", "--delete"
    ]
    for e in EXCLUDES:
        rsync_cmd.append(f"--exclude={e}")
    if link_dest:
        rsync_cmd.append(link_dest)
    rsync_cmd.extend([f"{REMOTE_HOST}:{REMOTE_PATH}", str(BACKUP_DIR)])

    print("[INFO] Lancement de rsync...")
    run_cmd(rsync_cmd)

    # === 4. Mise à jour du lien latest ===
    if LATEST_LINK.exists() or LATEST_LINK.is_symlink():
        LATEST_LINK.unlink()
    LATEST_LINK.symlink_to(BACKUP_DIR)

    print(f"[OK] Sauvegarde terminée avec succès : {BACKUP_DIR}")

    # === 5. Rotation des sauvegardes ===
    print(f"[INFO] Suppression des sauvegardes plus anciennes que {RETENTION_DAYS} jours...")
    now = datetime.datetime.now()
    for item in LOCAL_BACKUP_ROOT.iterdir():
        if item.is_dir() and item.name.startswith("20"):  # répertoires datés
            try:
                backup_date = datetime.datetime.strptime(item.name, "%Y-%m-%d")
                age_days = (now - backup_date).days
                if age_days > RETENTION_DAYS:
                    print(f"[INFO] Suppression {item} (âge {age_days} jours)")
                    shutil.rmtree(item)
            except ValueError:
                continue

    print("[OK] Rotation terminée.")


if __name__ == "__main__":
    main()
