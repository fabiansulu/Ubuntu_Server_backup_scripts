SAUVEGARDE DES DOSSIERS (REPERTOIRES) D'UN SERVEUR UBUNTU
Par Authentik

Option 1 : SIMPLE RSYNC SCRIPT
-------------------------
Étapes d’installation :

Rends le script exécutable :
sudo chmod +x /usr/local/bin/backup.sh

Configure la crontab root pour lancer la sauvegarde tous les jours à 2h :
sudo crontab -e

et ajoute :
0 2 * * * /usr/local/bin/backup.sh

# Sauvegarde de la liste des paquets installés
dpkg --get-selections > /chemin/vers/destination/package-list.txt

# Sauvegarde des dossiers du système avec rsync en excluant les dossiers à ne pas copier
rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /chemin/vers/destination/
Il faut remplacer /chemin/vers/destination/ par le répertoire de destination de la sauvegarde.

Ce script assure que la liste des paquets est mise à jour juste avant la synchronisation complète du système via rsync.

Veillez à ce que le script soit exécutable avec :

bash
sudo chmod +x /usr/local/bin/backup.sh
Et dans la crontab (exécutée en root), il suffit de lancer le script régulièrement, par exemple tous les jours à 2h :

text
0 2 * * * /usr/local/bin/backup.sh


Option 2 : En cours de test
-------------------------
