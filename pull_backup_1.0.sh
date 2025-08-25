#!/bin/bash
# pull-backup.sh
# Script lancé sur le serveur de sauvegarde pour aller chercher les fichiers
# avec sauvegardes incrémentielles (rsync --link-dest)
# + rotation automatique
# Auteur : Authentik
# Date : $(date +%Y-%m-%d)

set -euo pipefail

# === VARIABLES ===
REMOTE_HOST="user@IP_DE_LA_MACHINE_SOURCE"   # machine à sauvegarder
REMOTE_PATH="/"                             # chemin distant à sauvegarder
LOCAL_BACKUP_ROOT="/chemin/vers/destination" # répertoire local de sauvegarde
RETENTION_DAYS=7                            # nombre de jours de sauvegarde à conserver

DATE=$(date +%F)
BACKUP_DIR="$LOCAL_BACKUP_ROOT/$DATE"
LATEST_LINK="$LOCAL_BACKUP_ROOT/latest"      # pointeur vers la dernière sauvegarde
PKG_LIST="$BACKUP_DIR/package-list.txt"

# === CREATION DU DOSSIER LOCAL ===
mkdir -p "$BACKUP_DIR"

# === SAUVEGARDE LISTE DES PAQUETS (via SSH) ===
echo "[INFO] Récupération de la liste des paquets depuis $REMOTE_HOST ..."
ssh "$REMOTE_HOST" 'dpkg --get-selections' > "$PKG_LIST"

# === DETERMINATION DE LA SAUVEGARDE PRECEDENTE ===
if [ -d "$LATEST_LINK" ]; then
  LINK_DEST="--link-dest=$LATEST_LINK"
  echo "[INFO] Sauvegarde incrémentielle (comparaison avec $LATEST_LINK)"
else
  LINK_DEST=""
  echo "[INFO] Première sauvegarde complète"
fi

# === SAUVEGARDE DES FICHIERS (via rsync pull incrémentiel) ===
rsync -aAXHv \
  --delete \
  --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
  $LINK_DEST \
  "$REMOTE_HOST:$REMOTE_PATH" "$BACKUP_DIR/"

# === MISE A JOUR DU LIEN SYMBOLIQUE "latest" ===
rm -f "$LATEST_LINK"
ln -s "$BACKUP_DIR" "$LATEST_LINK"

echo "[OK] Sauvegarde de $REMOTE_HOST terminée avec succès ($(date))"

# === ROTATION DES SAUVEGARDES ===
echo "[INFO] Suppression des sauvegardes plus anciennes que $RETENTION_DAYS jours ..."
find "$LOCAL_BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "[OK] Rotation terminée ($(date))"
