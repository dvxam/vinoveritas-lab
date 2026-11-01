# Journal du labo

Étapes réalisées, dans l'ordre, avec les décisions et les problèmes rencontrés. Les adresses sont dans [NETWORK.md](NETWORK.md).

## 1er novembre 2026

### 1. Serveur OVH
- Serveur dédié OVH acheté à la main dans l'espace client (pas de commande par Terraform).
- Réinstallé en **Debian 13** avec OpenTofu (`1-server/`, ressource `ovh_dedicated_server_reinstall_task`) : deux disques en RAID 1 logiciel, `/boot` de 1 Gio, le reste pour `/`. Nom d'hôte `pve`.
- `install_debian` repassé à `false` après l'installation, pour qu'un `apply` ne réinstalle pas le serveur.
- Constats sur l'image Debian d'OVH : SSH refuse root (compte `debian` avec `sudo` sans mot de passe), mot de passe SSH désactivé, interface publique `enp1s0f0`, pas de commande `sysctl` (procps absent).

### 2. WireGuard sur le serveur
- Choix : WireGuard directement sur l'hôte plutôt que dans une VM, pour ne pas dépendre d'une VM pour administrer le serveur. Un seul accès réseau pour SSH, libvirt et les VM.
- Le script de post-installation d'OVH ne tourne qu'à l'installation : WireGuard est installé par SSH (`1-server/wireguard.tf`, `terraform_data` + provisioners), relancé quand le script change.
- Tunnel `10.99.0.0/24` : serveur `10.99.0.1`, Mac `10.99.0.2`. Clé publique du Mac dans `terraform.tfvars`.

### 3. Rangement de `1-server/`
- Découpage en `terraform.tf`, `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`, un fichier par fonction (`wireguard.tf`, `packages.tf`, `libvirt.tf`), scripts dans `scripts/`.
- `.env` (identifiants OVH) ajouté au `.gitignore` : il ne l'était pas.
- Paquets de confort : `tree`, `neovim` (`packages.tf`).

### 4. Proxmox abandonné, libvirt à la place
- Proxmox aurait demandé de réinstaller le serveur ou de changer son réseau (pont `vmbr0`). Le serveur doit rester une Debian utilisable pour autre chose.
- Choix : **KVM/libvirt** sur la Debian (`1-server/libvirt.tf`) : QEMU, libvirt, UEFI (`ovmf`), TPM (`swtpm-tools`). Le compte `debian` est dans le groupe `libvirt`.
- OpenTofu pilote libvirt depuis le Mac par SSH (provider `dmacvicar/libvirt` 0.9, `qemu+sshcmd://debian@10.99.0.1/system`).
- Réseau `nat` en `192.168.206.0/24` (comme VMnet8), mode `open` : libvirt ne pose pas de règle, le NAT vers Internet est un service systemd `lab-nat`. Sinon le Mac ne pourrait pas joindre les VM par le tunnel.
- Code Proxmox et Packer supprimé ; le code complet du labo (segments, pfSense, Windows) est rangé dans `later/full-lab/`.

### 5. Code en anglais
- Noms de dossiers, fichiers, ressources, variables, commentaires et scripts traduits (`1-server/`, `2-lab/`, `later/`).
- Bloc `moved` pour la ressource renommée dans l'état (`terraform_data.paquets` → `terraform_data.packages`).
- La clé WireGuard du serveur garde sa valeur (`serveur.key` renommée en `server.key` par le script).

### 6. Première VM : debian01
- `2-lab/` : pool `lab` (`/var/lib/libvirt/images/lab`), image cloud Debian 13, disque de VM en couche au-dessus de l'image, cloud-init pour le compte et la clé SSH.
- Problèmes rencontrés :
  - **Format de l'ISO cloud-init** : le provider détecte `iso` et refuse toute autre valeur après l'`apply` → `format = "iso"`.
  - **« Permission denied » au démarrage** : AppArmor. libvirt n'ajoute pas les disques déclarés comme volumes de pool au profil AppArmor de la VM. Corrigé en déclarant les disques par leur chemin de fichier. Vérifié avec une VM de test sur le serveur.
  - **Lecture de l'adresse** : la source de données attend l'UUID de la VM, pas son numéro.
- Résultat : debian01 démarrée, `192.168.206.125`, joignable en SSH.

### 7. ADMIN01 et OVS (code prêt, `apply` à lancer)
- debian01 renommée **ADMIN01** (blocs `moved` ; la VM est quand même recréée car son nom change).
- ADMIN01 : `10.50.10.10/24` sur seg-admin, `192.168.206.10/24` sur nat avec la route par défaut, en attendant pfSense.
- **OVS** : Debian, DHCP sur nat (temporaire), une carte sans adresse sur chacun des 7 segments, MAC fixes.
- Les 7 segments créés comme réseaux libvirt isolés.
- `2-lab/` découpé en `network.tf`, `images.tf`, `vms.tf`, `moved.tf`, `outputs.tf`.

### 8. OVS configuré avec Ansible
- Dépôt : `ansible/` dans ce dépôt, et non plus dans `vinoveritas-infra` (WSL inaccessible depuis le Mac). Décision à consigner dans la note *Labo chez OVH*.
- Ansible installé avec Homebrew sur le Mac, collection `openvswitch.openvswitch` 2.2.2.
- Rôle `ovs` : paquet `openvswitch-switch`, un fichier `.link` par carte (renommage `seg-*` par MAC), pont `br0`, un port par segment avec son VLAN, trunk non étiqueté vers pfSense, port interne `mgmt` en VLAN 10 avec `10.50.10.2/24` (networkd).
- Problème rencontré : le cache APT de l'image est vide, donc le mode simulation (`--check`) ne trouve pas le paquet. Une vraie exécution met le cache à jour.
- Vérifié après redémarrage : `ovs-vsctl show` affiche `br0` avec les 8 ports et leurs VLAN ; `mgmt` a son adresse. Les segments sont `DOWN` tant qu'aucune VM n'y est branchée.

### 9. Ansible sur le serveur
- Ajouté à la liste `packages` de `1-server/` (`variables.tf`) : `tree`, `neovim`, `ansible`. Installé par `tofu apply` (provisioner `apt`) ; `install_debian` reste à `false`, donc aucune réinstallation.
- Version : `ansible` 12.0.0 (Debian 13), `ansible-core` 2.19.11. Vérifié par `ansible --version` ; `tofu plan` ensuite : « No changes ».
- Décision : Ansible tourne **à la fois** sur le serveur (tests) et sur ADMIN01 (démonstration du rapport). La note *Automatisation Ansible* le précise.
- Non fait : les collections `ansible.windows` et `microsoft.ad` ne sont pas installées sur le serveur.

### 10. Rôles devtools et admin pour ADMIN01 (écrits, pas encore lancés)
- `devtools`, réutilisable sur d'autres VM : git, tmux, tree, ripgrep, fd, fzf, compilateur C ; Neovim 0.12.6 (version officielle, somme SHA-256 vérifiée), car Debian 13 fournit 0.10.4 alors que LazyVim demande au moins 0.11.2 ; starter LazyVim copié une fois dans `~/.config/nvim`, puis plugins installés sans ouvrir Neovim.
- `admin`, propre à ADMIN01 : Ansible, git, collection `openvswitch.openvswitch` 2.2.2.
- Playbook `ansible/admin01.yml` ; ADMIN01 ajouté à l'inventaire (`192.168.206.10`).
- Une police Nerd Font est à installer côté Mac, dans le terminal, pour les icônes de LazyVim.

### 11. Accès SSH du serveur vers ADMIN01 (écrit, pas encore lancé)
- Rôle `server_access`, appliqué à ADMIN01 dans `admin01.yml` : clé ed25519 créée pour `debian` sur le serveur, autorisée sur ADMIN01, clé d'hôte d'ADMIN01 ajoutée aux `known_hosts` du serveur, alias `admin01` dans `~/.ssh/config`.
- Le serveur entre dans l'inventaire Ansible sous le nom `pve` (`10.99.0.1`, compte `debian`, sans rebond).
- Réutilisable : appliquer le rôle à une autre VM lui donne le même accès.

### 12. Cockpit sur le serveur
- But : une interface graphique pour voir les VM et ouvrir leur console dans le navigateur (utile pour installer pfSense et les Windows).
- Tout est dans `1-server/cockpit.tf` (variables, ressource, sortie) et `1-server/scripts/cockpit.sh.tftpl`. Interrupteur `cockpit_enabled` : `false` puis `tofu apply` désinstalle Cockpit du serveur ; on supprime ensuite les deux fichiers.
- Paquets `cockpit-ws`, `cockpit-bridge`, `cockpit-system`, `cockpit-machines`, **sans les recommandés** : le paquet `cockpit` aurait installé NetworkManager, alors que le réseau est géré par systemd-networkd.
- Écoute **uniquement sur `10.99.0.1:9090`** (surcharge de `cockpit.socket`, `FreeBind` pour démarrer avant `wg0`).
- Connexion avec le mot de passe de `debian`, qui n'en avait pas : à définir à la main (`sudo passwd debian`), pour ne pas mettre de secret dans l'état OpenTofu. SSH refuse les mots de passe (`PasswordAuthentication no`, vérifié), donc ce mot de passe n'ouvre pas SSH.
- Règle : Cockpit sert à regarder et à démarrer ou arrêter les VM ; créer ou modifier une VM reste le rôle de `2-lab/`.
- Vérifié : `ss` montre l'écoute sur `10.99.0.1:9090` seulement ; HTTP 200 par le tunnel, rien sur l'IP publique ; NetworkManager absent.
- Problème rencontré : la session se coupait (« Disconnected »), surtout en ouvrant la page Machines. Le journal montrait `cockpit-bridge` planter : `sd_bus_attach_event: Invalid argument`, puis `channel is already open`.
  - Cause : la page Machines ouvre aussi le bus D-Bus de session de `debian` (libvirt en `qemu:///session`). `dbus-user-session` a été installé avec Cockpit, mais le gestionnaire de session de `debian`, lancé avant et maintenu par les connexions SSH, n'avait pas démarré son `dbus.socket` : `/run/user/1000/bus` n'existait pas. Au deuxième essai d'ouverture de ce bus, `cockpit-bridge` plante au lieu de renvoyer une erreur.
  - Reproduit sans navigateur, en envoyant les messages du protocole Cockpit à `cockpit-bridge --debug` (deux ouvertures du bus de session).
  - Corrigé dans le script : il démarre `dbus.socket` dans les gestionnaires de session déjà lancés (`runuser … systemctl --user start dbus.socket`). Après un redémarrage, le socket démarre de lui-même.
  - Avant de trouver la cause, Cockpit est passé à la version de `trixie-backports` (368, cockpit-machines 357) : même plantage, ce n'était pas la cause. La version des backports est gardée, comme le conseille le projet Cockpit pour Debian.
  - Vérifié : le bus de session existe, `org.libvirt` répond sur le bus de session et sur le bus système, plus de plantage. Ces mises à jour ont aussi exercé la désinstallation (purge par la ressource OpenTofu), qui fonctionne.

### 13. SIEM01 et rôle Wazuh (VM créée, Wazuh pas encore installé)
- VM dans un fichier à part, `2-lab/siem01.tf` (sans toucher à `vms.tf`) : Debian 13, 4 vCPU, 8 Gio, 50 Gio, dimensionnement Wazuh pour 1 à 25 agents. `10.50.20.30/24` sur seg-siem, `192.168.206.30/24` sur nat avec la route par défaut (temporaire, comme ADMIN01). MAC `02:50:00:00:20:30` et `:31`.
- Rôle `wazuh` + playbook `ansible/siem01.yml` : assistant d'installation officiel (`wazuh-install.sh -a`, version 4.14), lancé une fois (`creates` sur `wazuh-install-files.tar`), en tâche de fond (10 à 20 min). Puis dépôt APT Wazuh désactivé (conseil Wazuh : pas de mise à jour partielle) et services activés. `verify.yml` : services, ports 443, 1514, 1515, 9200, 55000, page de connexion du tableau de bord.
- Choix : l'assistant plutôt que les rôles `wazuh-ansible` (lourds, à télécharger depuis GitHub).
- Debian 13 absente de la liste des systèmes recommandés par Wazuh : option `-i` (`wazuh_ignore_check`), à signaler dans le rapport.
- Le mot de passe admin du tableau de bord reste sur SIEM01 (`/root/wazuh-install-files.tar`), jamais dans le dépôt.
- `tofu apply` fait : SIEM01 tourne. `inventory.yml` n'est pas encore modifié : ajouter `siem01` (`ansible_host: 192.168.206.30`).
- Premier lancement du playbook interrompu pendant l'installation des outils (apt), avant l'assistant : rien de Wazuh sur la VM.

### 14. pfSense
- `2-lab/pfsense.tf`, à part de `vms.tf` : VM `pfsense` (2 vCPU, 2 Gio, disque vide de 16 Gio), WAN `em0` sur nat (DHCP, joue le réseau de l'école), LAN `em1` sur seg-trunk (trunk 802.1Q vers OVS). MAC `02:50:00:00:00:01` et `:02`.
- ISO pfSense CE 2.7.2 (dernière version CE publiée en ISO ; 2.8 seulement par l'installeur en ligne de Netgate) : téléchargée et décompressée sur le serveur par SSH (`terraform_data`), somme SHA-256 vérifiée. Variables `server_host`, `server_user`, `ssh_private_key_path` ajoutées à `2-lab/variables.tf`.
- Installation pilotée à la console depuis le Mac (`virsh screenshot` + `virsh send-key`) : UFS (2 Gio de RAM, ZFS déconseillé sous 8 Gio), disque entier.
- **Problème : pfSense ne voyait aucune carte réseau** (« No interfaces found », puis arrêt). Essayé e1000, e1000e, virtio : sans effet. Cause : le provider ne met ni `<acpi/>` ni `<apic/>` dans la VM. Linux s'en passe, FreeBSD non (sans ACPI, pas d'énumération PCIe sur q35 ; sur i440fx, panique « A valid RSDP was not found »). Corrigé par `features = { acpi = true, apic = {} }`. Cartes e1000 gardées : `em0`/`em1`, comme dans le rapport.
- Console, minimum pour qu'Ansible prenne la suite : WAN = `em0` (DHCP, `192.168.206.167`), VLAN 10 sur `em1`, LAN = `em1.10` en `10.50.10.1/24` sans DHCP, interface web en HTTPS, SSH activé. Mot de passe `admin` encore celui par défaut.
- **Problème : ADMIN01 ne joignait ni OVS (`10.50.10.2`) ni pfSense.** Deux causes :
  - la VM OVS avait été reconstruite (nouvelle adresse `192.168.206.166`) sans Open vSwitch : `inventory.yml` mis à jour, `ovs.yml` relancé ;
  - dans OVS, les cartes `seg-*` restaient désactivées (`DOWN`, sans `UP`) : OVS les met dans `br0` sans les activer. La remarque de l'étape 8 (« DOWN tant qu'aucune VM n'y est branchée ») était fausse. Corrigé dans le rôle `ovs` : `10-ports.network` (networkd) active ces cartes sans leur donner d'adresse.
- Vérifié depuis ADMIN01 : ping de `10.50.10.2` (OVS) et `10.50.10.1` (pfSense), ports 22 et 443 de pfSense ouverts.
- Incident : un `tofu apply` lancé pour pfSense a aussi appliqué le code SIEM01 en cours d'écriture. Ensuite, les `apply` pfSense sont limités par `-target`.

### 15. pfSense configuré avec Ansible
- Rôle `pfsense` (collection `pfsensible.core` 0.7.1) + playbook `ansible/pfsense.yml`. Données dans `host_vars/pfsense.yml`, reprises de la Mission 2 : zones, adresses, matrice des flux.
- Accès : pfSense est joint par ADMIN01 (`ProxyJump` dans `inventory.yml`), compte `admin`. Premier lancement avec le mot de passe par défaut (`-e ansible_password=pfsense`, `sshpass` installé sur le Mac avec Homebrew) ; le rôle pose ensuite les clés SSH du Mac et de `debian@pve`, et un mot de passe aléatoire. Mot de passe et hash dans `ansible/secrets/pfsense.yml`, ignoré par Git.
- Fait : nom `pfsense.vinoveritas.local`, fuseau Europe/Paris ; VLAN 20, 30, 40 et interfaces SERVEURS, POSTES, SAUVEGARDE (LAN renommé ADMIN) ; DHCP sur POSTES (`.100` à `.199`, DNS = DC01) ; résolveur DNS sur ADMIN, SERVEURS, SAUVEGARDE (pas POSTES, X5) ; journaux (pare-feu, système, authentification) vers SIEM01 en syslog ; alias (machines, réseaux privés, ports) ; une règle par flux autorisé (F1 à F25), F21 et F22 créées désactivées ; règles « allow all » de la console supprimées (l'anti-lockout reste).
- NAT sortant : mode automatique, il couvre déjà les 4 réseaux (table `tonatsubnets`) ; pas de règle à écrire.
- Choix : les flux refusés (X1 à X8) n'ont pas de règle à eux : ils tombent sur la règle de blocage par défaut de pfSense, qui est journalisée.
- Vérifié (`verify.yml`, `verify_from_admin.yml`) : adresses des 4 zones, dhcpd et unbound actifs, chaque règle chargée (et F21, F22, « allow all » absentes), NAT des 4 réseaux, syslog vers SIEM01 ; depuis ADMIN01, 22 et 443 ouverts sur `10.50.10.1`, DNS fermé (seul OVS y a droit). Second lancement : aucun changement.
- Limites : les machines derrière pfSense passent encore par leur lien nat ; les règles ne sont donc pas encore testées en vrai trafic. F18 n'ouvre que le 443 : les sources APT devront être en `https://`. Pas d'ICMP vers pfSense (absent de la matrice).

## À faire
- Exporter `config.xml` de pfSense dans le dépôt (sans les secrets).
- Passer la route par défaut d'ADMIN01 (puis des autres VM) sur pfSense, et retirer les liens nat temporaires.
- Définir le mot de passe de `debian` (`ssh debian@10.99.0.1 sudo passwd debian`) pour se connecter à Cockpit.
- Lancer `ansible-playbook admin01.yml` (rôles devtools, admin et server_access).
- Ajouter `192.168.206.0/24` aux `AllowedIPs` du tunnel du Mac (déjà fait pour la connexion par `-J`, pas encore pour un accès direct).
- Remplacer `admin_user = "root"` par un compte nommé, puis reconstruire ADMIN01 et OVS.
- Pare-feu de l'hôte : SSH est encore ouvert sur l'IP publique (clé seule).
- Mettre à jour la note *Labo chez OVH avec Proxmox et Terraform* : elle décrit encore Proxmox et Packer, et le dépôt d'infra.
- Ansible sur ADMIN01 : cloud-init doit installer Ansible et cloner ce dépôt.
- SIEM01 : ajouter l'hôte à `inventory.yml`, puis `ansible-playbook siem01.yml`. Le rôle `wazuh` reçoit aussi le syslog de pfSense (F26) : bloc `<remote>` ajouté à `ossec.conf` (514/udp, seule `10.50.20.1` acceptée), vérifié par `verify.yml` ; écrit mais pas encore lancé.
