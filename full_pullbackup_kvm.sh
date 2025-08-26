#!/bin/bash
set -euo pipefail

# --- Variables de configuration ---
KVM_HOST="authentik@192.168.56.1"         # Serveur KVM source
BACKUP_BASEDIR="/home/backupuser/backups" # Destination locale
DATE=$(date +%Y%m%d%H%M%S)
LOGFILE="$BACKUP_BASEDIR/kvm_pullbackup_all_${DATE}.log"

echo "=== Pull backup démarré depuis $KVM_HOST à $(date) ===" | tee -a "$LOGFILE"

# --- Lister toutes les VMs sur le serveur source ---
VM_LIST=$(ssh -o BatchMode=yes "$KVM_HOST" \
    "sudo /usr/bin/virsh list --name --all | grep -v '^$' | grep -v '^[- ]'") || true

if [ -z "$VM_LIST" ]; then
    echo "[!] Aucune VM trouvée sur $KVM_HOST" | tee -a "$LOGFILE"
    exit 0
fi

# --- Boucle sur chaque VM ---
for VM_NAME in $VM_LIST; do
    echo ">>> Sauvegarde VM: $VM_NAME" | tee -a "$LOGFILE"

    # Déterminer le disque principal (qcow2)
    MAIN_DISK_PATH=$(ssh -o BatchMode=yes "$KVM_HOST" \
        "sudo /usr/bin/virsh domblklist $VM_NAME --details | awk '/disk/ {print \$4; exit}'")
    MAIN_DISK_TARGET=$(ssh -o BatchMode=yes "$KVM_HOST" \
        "sudo /usr/bin/virsh domblklist $VM_NAME --details | awk '/disk/ {print \$3; exit}'")

    echo "[*] Disque principal détecté: $MAIN_DISK_PATH (target: $MAIN_DISK_TARGET)" | tee -a "$LOGFILE"

    # Dossier local
    BACKUP_DIR="$BACKUP_BASEDIR/$VM_NAME"
    mkdir -p "$BACKUP_DIR"

    # Vérifier si le full existe déjà
    FULL_FILE="$BACKUP_DIR/$(basename $MAIN_DISK_PATH)"
    if [ ! -f "$FULL_FILE" ]; then
        echo "[*] Aucun full backup trouvé, copie complète du disque principal..." | tee -a "$LOGFILE"
        ssh -o BatchMode=yes "$KVM_HOST" "sudo cat $MAIN_DISK_PATH" \
            | dd of="$FULL_FILE" status=progress bs=64M \
            >> "$LOGFILE" 2>&1 || {
                echo "[!] Erreur transfert FULL $VM_NAME" | tee -a "$LOGFILE"
                continue
            }
        echo "[✓] Full backup terminé pour $VM_NAME" | tee -a "$LOGFILE"
    else
        echo "[*] Full backup déjà présent pour $VM_NAME, passage aux incrémentielles..." | tee -a "$LOGFILE"
    fi

    # --- Sauvegarde incrémentielle (overlay) ---
    # 1. Créer snapshot
    SNAP_NAME="backup_${VM_NAME}_${DATE}"
    echo "[*] Création snapshot $SNAP_NAME" | tee -a "$LOGFILE"
    ssh -o BatchMode=yes "$KVM_HOST" \
        "sudo /usr/bin/virsh snapshot-create-as --domain $VM_NAME $SNAP_NAME --disk-only --atomic --no-metadata" \
        >> "$LOGFILE" 2>&1 || {
            echo "[!] Erreur création snapshot $VM_NAME" | tee -a "$LOGFILE"
            continue
        }

    # 2. Déterminer disque overlay (snapshot)
    OVERLAY_PATH=$(ssh -o BatchMode=yes "$KVM_HOST" \
        "sudo /usr/bin/virsh domblklist $VM_NAME --details | awk '/disk/ {print \$4; exit}'")
    OVERLAY_TARGET=$(ssh -o BatchMode=yes "$KVM_HOST" \
        "sudo /usr/bin/virsh domblklist $VM_NAME --details | awk '/disk/ {print \$3; exit}'")

    echo "[*] Overlay détecté: $OVERLAY_PATH (target: $OVERLAY_TARGET)" | tee -a "$LOGFILE"

    # 3. Sauvegarde overlay
    echo "[*] Sauvegarde overlay vers $BACKUP_DIR" | tee -a "$LOGFILE"
    ssh -o BatchMode=yes "$KVM_HOST" "sudo cat $OVERLAY_PATH" \
        | dd of="$BACKUP_DIR/$(basename $OVERLAY_PATH).overlay_${DATE}" status=progress bs=64M \
        >> "$LOGFILE" 2>&1 || {
            echo "[!] Erreur transfert overlay $VM_NAME" | tee -a "$LOGFILE"
            continue
        }

    # 4. Fusion snapshot
    echo "[*] Fusion snapshot dans disque principal (blockcommit)" | tee -a "$LOGFILE"
    ssh -o BatchMode=yes "$KVM_HOST" \
        "sudo /usr/bin/virsh blockcommit $VM_NAME $OVERLAY_TARGET --active --verbose --pivot" \
        >> "$LOGFILE" 2>&1 || {
            echo "[!] Erreur blockcommit $VM_NAME" | tee -a "$LOGFILE"
            continue
        }

    echo "[✓] Sauvegarde incrémentielle terminée pour $VM_NAME" | tee -a "$LOGFILE"
done

echo "=== Pull backup terminé à $(date) ===" | tee -a "$LOGFILE"
exit 0

# --- Crédit ---
# Script d'automatisation sauvegarde KVM (pull mode)
# Adapté par Authentik, 2025

