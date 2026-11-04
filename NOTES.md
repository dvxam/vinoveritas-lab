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

### 16. DC01 (installation lancée, promotion à faire)
- `2-lab/windows.tf` : table des VM Windows (DC01 seul pour l'instant, FS01 ira dans la même table). Windows Server 2022 en évaluation (180 jours), anglais, ISO de l'Evaluation Center téléchargée sur le serveur (5 Go, pas de somme publiée par Microsoft). Disque SATA et carte e1000e : Windows a les pilotes, pas besoin de l'ISO VirtIO. ACPI et APIC ajoutés, comme pour pfSense.
- Installation sans intervention : `2-lab/windows/autounattend.xml.tftpl` (disque MBR, édition Standard Desktop Experience, nom, IP fixe `10.50.20.10/24`, passerelle et DNS `10.50.20.1`, clavier français, fuseau de Paris, licence d'évaluation acceptée avec l'accord de l'utilisateur), sur un petit ISO construit sur le serveur (`xorriso`, droits 600 car il contient le mot de passe). Au premier démarrage, `setup-winrm.ps1` active WinRM en HTTPS (certificat auto-signé), pare-feu Windows limité au réseau ADMIN.
- Mot de passe Administrator : `ansible/secrets/windows.yml` (non versionné), lu à la fois par `windows.tf` et par Ansible. Il est aussi dans l'état OpenTofu (local).
- Ansible depuis ADMIN01 (WinRM 5986, F11) : rôle `admin` complété (rsync, route `10.50.0.0/16` par pfSense, `/etc/netplan/60-lab-zones.yaml`) ; DC01 dans `inventory.yml` (groupe `windows`) ; rôle `dc01` + `dc01.yml` : AD DS, forêt `vinoveritas.local` (NetBIOS `VINOVERITAS`), DNS sur lui-même, redirection vers pfSense (F9), heure prise sur pfSense, RDP ouvert au réseau ADMIN. `verify.yml` : domaine, PDC, résolution d'un nom du domaine et d'un nom Internet.
- Limite : certificat WinRM non vérifié (`ansible_winrm_server_cert_validation: ignore`), à remplacer par `ansible_winrm_ca_trust_path` et à signaler dans le rapport.
- À partir d'ici, l'utilisateur lance lui-même `tofu apply` et `ansible-playbook`.

### 17. FS01 (code prêt, `apply` et playbook à lancer par l'utilisateur)
- `2-lab/windows.tf` : FS01 ajouté à la table Windows (`10.50.20.20/24` sur seg-fs, DNS = DC01, MAC `02:50:00:00:20:20`), avec un second disque de 40 Gio pour les partages (`libvirt_volume.windows_data`). `tofu plan` : 4 ressources ajoutées, DC01 inchangé.
- Rôle commun `windows_base` (RDP ouvert au seul réseau ADMIN, F11), sorti du rôle `dc01` et utilisé par `dc01.yml` et `fs01.yml`.
- Rôle `fs01` + `fs01.yml` : DNS vers DC01, jonction au domaine, rôles FS-FileServer et FS-Resource-Manager (quotas, filtrage de fichiers), lecteurs CD déplacés en Y: et Z: pour que le disque de données prenne D:, disque initialisé en GPT et formaté en NTFS (« Data »). `verify.yml` : membre du domaine, rôle installé, D: en NTFS, SMB à l'écoute.
- Pas encore : les partages et les groupes AD par service (Mission 1, mesure 5).

### 18. Premier lancement de `dc01.yml` (échec, corrigé)
- Lancé depuis le serveur (`debian@pve`) : `windows_admin_password` indéfini. Deux raisons : `secrets/windows.yml` n'est pas versionné (absent du clone du serveur), et le serveur n'a pas de route vers les zones `10.50.x.x` (seul ADMIN01 en a une, par pfSense).
- `dc01.yml` et `fs01.yml` vérifient maintenant ces deux points en premier, avec un message clair.
- Constaté au passage sur pfSense : DC01 sort en HTTPS (F10) ; ses essais en HTTP (80) et NTP direct (123) sont bloqués et journalisés (X6). WinRM 5986 joignable depuis ADMIN01 une fois le premier démarrage de Windows terminé.

### 19. Partages de FS01 (code prêt, à lancer par l'utilisateur)
- Matrice des droits dans `ansible/group_vars/windows/shares.yml`, identique à la section 3 du brouillon de la mission 5 : 6 services (Direction, RH, Comptabilite, Informatique, Commercial, Logistique) + Commun.
- Rôle `ad_groups` (DC01), méthode AGDLP : OU `Groupes`, un `GG_<service>` global par service, un `DL_<partage>_RW` local de domaine par partage, et un `DL_<partage>_RO` quand un autre service lit. Appartenances posées avec `members.set` : la matrice est la seule source.
- Rôle `file_shares` (FS01) : SMB 1 désactivé, accès non chiffré refusé ; `D:\Partages` réservé aux administrateurs et à SYSTEM (héritage depuis `D:` coupé) ; un dossier par partage, NTFS Modifier pour `_RW`, Lecture et exécution pour `_RO` ; droits de partage reprenant la matrice (pas de « Tout le monde ») ; chiffrement SMB et énumération basée sur l'accès sur chaque partage.
- Playbook `ansible/file_shares.yml` (depuis ADMIN01, après `dc01.yml` et `fs01.yml`) ; `verify.yml` des deux rôles : membres de chaque `DL_`, chiffrement, ABE, droits de partage exacts, NTFS sans Everyone / Users / Authenticated Users / Domain Users.
- Pas encore : comptes utilisateurs (mission 4), audit des accès, BitLocker, clichés instantanés, quotas.

### 20. Comptes du domaine (lancé et vérifié)
- Liste dans `ansible/group_vars/windows/users.yml`, reprise dans le nouveau brouillon de la mission 4 : 15 personnes fictives, 2 ou 3 par service, identifiant `prenom.nom` (20 caractères au plus, vérifié).
- Rôle `ad_users` + playbook `ansible/ad_users.yml` (lance aussi `ad_groups`) : OU `Utilisateurs` avec une sous-OU par service, OU `Administrateurs` ; chaque compte dans l'OU et le `GG_` de son service ; comptes `adm-` (membres de `Domain Admins`) pour Thomas Bernard et Léa Girard.
- Mots de passe initiaux : aléatoires, 24 caractères, un fichier par compte dans `~/.vinoveritas/ad-passwords/` sur ADMIN01 (droits 600, hors du dépôt pour survivre au `rsync --delete`), expirés à la création seulement : un compte dont l'utilisateur a choisi son mot de passe le garde.
- `verify.yml` : chaque compte actif, dans son OU et son `GG_` ; `Domain Admins` ne contient qu'`Administrator` et les comptes `adm-`.
- Pas encore : GPO interdisant aux `adm-` l'ouverture de session sur les postes.
- Lancé depuis ADMIN01 : OU, groupes `GG_` et `DL_`, 15 comptes et 2 comptes `adm-` créés. Trois corrections :
  - contrôle : `win_powershell` ne sérialise que 2 niveaux par défaut, la liste des comptes arrivait en texte → `depth: 4` (même correction dans le contrôle de `file_shares`) ;
  - chaque passage ressortait `changed` : `groups.set` essayait de retirer `Domain Users`, groupe principal de chaque compte → ajouté à la liste ;
  - comparaison de `Domain Admins` : PowerShell et Jinja ne trient pas les majuscules pareil → tri des deux côtés dans Jinja.
- Second passage : `changed=0`, tous les contrôles passent.

### 21. Agents Wazuh (code prêt, à lancer par l'utilisateur)
- Constaté sur SIEM01 : Wazuh 4.14.9, ports 1514 et 1515 ouverts, inscription des agents sans mot de passe, seul l'agent local (`000`) présent. Pas de route vers les autres zones : la route par défaut passe par nat, les réponses aux agents d'ADMIN01 et d'OVS se perdraient. Le syslog de pfSense (514/udp) n'écoute pas encore : bloc écrit (étape SIEM01), rôle pas relancé.
- Rôle `wazuh` : route `10.50.0.0/16` par pfSense (`10.50.20.1`), fichier netplan `60-lab-zones.yaml` comme pour ADMIN01, vérifiée par `verify.yml`.
- Rôle `ovs` : route `10.50.0.0/16` par `10.50.10.1` sur `mgmt` (sinon l'agent d'OVS sortirait par nat).
- pfSense : `packages.wazuh.com` ajouté à l'alias `SORTIE_ADMIN` (F18), pour l'agent d'ADMIN01 et d'OVS une fois les liens nat retirés. Reporté dans le brouillon de la mission 2 et la note *Automatisation Ansible*.
- Rôle `wazuh_agent` : Debian (dépôt officiel, paquet `wazuh-agent=4.14.9-1` bloqué à cette version, la même que le serveur) et Windows (MSI de `packages.wazuh.com`, SHA-256 relevée au premier téléchargement car Wazuh n'en publie pas). Adresse de SIEM01 remise dans `ossec.conf` à chaque passage. `verify.yml` : `status='connected'` dans le fichier d'état de l'agent.
- Playbook `ansible/wazuh_agents.yml` : ADMIN01 et OVS depuis le Mac ou le serveur (`--limit admin01,ovs`), DC01 et FS01 depuis ADMIN01 (`--limit windows`). L'agent d'OVS est gardé pour l'instant (question ouverte dans le brouillon de la mission 2, F25).
- `siem01` ajouté à `inventory.yml` (`192.168.206.30`).
- Pas encore : mot de passe d'inscription des agents, pare-feu nftables de SIEM01 (mission 2), agents de CLIENT01 et BACKUP01 (machines pas encore créées).

### 22. Premier tableau de bord Wazuh (code prêt, à lancer par l'utilisateur)
- « Vino Veritas — Accès et identités », dans le menu *Dashboards* de Wazuh. Cinq panneaux : échecs de connexion dans le temps par machine (R3), comptes en échec avec adresse source (R3), comptes verrouillés (4740), connexions des comptes `adm-*` et `Administrator` avec adresse source et type (R5 : seulement depuis ADMIN01), changements sensibles dans l'AD (4720, 4722, 4724, 4728, 4732, 4756). Comptes machine (`$`) exclus. Dernières 24 h, rafraîchi chaque minute.
- Recoupe les trois scénarios de détection de la mission 7 : force brute, compte admin hors d'ADMIN01, ajout à Domain Admins.
- Export `roles/wazuh/templates/access-dashboard.ndjson.j2` (objets enregistrés d'OpenSearch Dashboards), généré par un script ; seul l'identifiant du modèle d'index `wazuh-alerts-*` est une variable, lue sur SIEM01.
- Rôle `wazuh`, `dashboards.yml` : mot de passe `admin` lu dans `wazuh-install-files.tar` sur SIEM01 (`no_log`, jamais dans le dépôt ; `-e wazuh_dashboard_password=...` s'il a été changé), import par l'API (`_import?overwrite=true`) quand le fichier change. `verify.yml` : le tableau de bord existe.
- Pas testé contre SIEM01 : syntaxe vérifiée, JSON valide. Pas encore : panneau des flux bloqués par pfSense (décodage du syslog à vérifier), tableau de bord « Accès aux données sensibles » (audit des fichiers de FS01).

### 23. Journaux de pfSense dans Wazuh, tableau de bord « Réseau » (code prêt, à lancer par l'utilisateur)
- Constaté : le syslog de pfSense arrive bien sur SIEM01 (514/udp), mais aucune alerte n'en sort. Deux causes :
  - pfSense n'envoie pas de nom d'hôte (`<134>Nov  1 19:39:58 filterlog[78906]: …`) : Wazuh prend `filterlog[78906]:` pour le nom d'hôte, et son décodeur pfSense (`program_name` filterlog) ne reconnaît plus rien. Vérifié avec `wazuh-logtest` : avec un nom d'hôte ajouté, la même ligne est décodée ;
  - la règle de Wazuh pour les blocages (87701) a l'option `no_log` : même décodés, les blocages ne deviendraient jamais des alertes.
- Rôle `wazuh` : décodeur `vinoveritas-pfsense` (PCRE2, lit le contenu de filterlog : règle, interface, action, sens, protocole, source, destination, ports ; IPv4) et règles 100200 à 100203 (flux bloqué niveau 3, flux autorisé niveau 3, plus de 20 blocages d'une même source en une minute niveau 10), dans `etc/decoders` et `etc/rules` de SIEM01. `verify.yml` passe une vraie ligne de pfSense dans `wazuh-logtest` et vérifie la règle 100201, la source et le port.
- Tableau de bord « Vino Veritas — Réseau » : matrice des flux bloqués (source × destination, carte de chaleur), balayages détectés (règle 100203), flux bloqués dans le temps par interface de pfSense, détail (source, destination, port, protocole). Les deux tableaux de bord sont maintenant dans une liste (`wazuh_dashboards`), importés et vérifiés en boucle.
- Pas testé contre SIEM01 : expressions vérifiées en Python sur trois lignes (UDP, ICMP, TCP), syntaxe Ansible et JSON valides. Bruit attendu : les diffusions NetBIOS de DC01 (`10.50.20.255:138`) sont bloquées et apparaîtront dans la matrice.

### 24. Script de génération d'événements (écrit, à lancer par l'utilisateur)
- `ansible/scripts/trigger-events.sh`, lancé sur ADMIN01 depuis `ansible/` (copié par rsync) : remplit les tableaux de bord Wazuh. Scénarios, tous par défaut ou au choix :
  - `brute` : connexions WinRM avec un mauvais mot de passe sur DC01 et FS01, comptes réels et inexistants (4625) ;
  - `ssh` : connexions SSH avec des comptes inconnus sur OVS et ADMIN01 ;
  - `admin` : connexion d'Administrator sur DC01 depuis ADMIN01 (4624, panneau des comptes à privilèges) ;
  - `ad` : compte `test.alerte` créé, ajouté à Domain Admins, retiré puis supprimé (4720, 4728, 4729, 4726) ;
  - `blocked` : SMB, LDAP et MS-SQL vers DC01 et FS01, refusés par pfSense (hors matrice depuis ADMIN) ;
  - `scan` : 30 ports fermés de FS01 en quelques secondes (règle 100203).
- Tout est défait à la fin ; rien ne sort du labo. Pas de verrouillage de compte (4740) : aucune stratégie de verrouillage n'est encore définie (GPO, mission 4).
- Vérifié : syntaxe bash. Pas lancé.

### 23. DNS d'ADMIN01 sur DC01
- Constat : ADMIN01 interrogeait le dnsmasq de libvirt sur le lien nat (`192.168.206.1`), qui répond avec les adresses nat des VM (`ovs` → `192.168.206.166`), au lieu de DC01 comme le prévoit le plan d'adressage de la mission 2 (F12).
- Rôle `dc01` : enregistrements A pour les machines hors domaine, à leur adresse dans les zones : `pfsense` `10.50.10.1`, `ovs` `10.50.10.2` (mgmt), `admin01` `10.50.10.10`, `siem01` `10.50.20.30`. Vérifiés par `verify.yml`.
- Rôle `admin` : DNS `10.50.20.10` et suffixe `vinoveritas.local` sur la carte ADMIN (`60-lab-zones.yaml`) ; DNS de la carte nat vidé par une surcharge networkd (`10-netplan-card1.network.d/no-dns.conf`), car netplan additionne les listes et ne peut pas retirer celui de cloud-init (essayé dans un dossier temporaire).
- Lancé : `dc01.yml` (depuis ADMIN01) puis `admin01.yml` (depuis le Mac). Vérifié sur ADMIN01 : `ovs` → `10.50.10.2`, `siem01` et `pfsense` résolus, `apt update` passe (DC01 → pfSense). Second passage d'`admin01.yml` : `changed=0`.
- Reste : ADMIN01 n'a pas de clé SSH, donc `ssh ovs` depuis ADMIN01 est refusé ; SIEM01 a encore le DNS du lien nat (même correction à faire dans le rôle `wazuh`).

### 24. CLIENT01 (code prêt, à lancer par l'utilisateur)
- `2-lab/client01.tf`, à part de `windows.tf` (changer le micrologiciel de la table commune aurait recréé DC01 et FS01) : Windows 11 Enterprise en évaluation (90 jours, 24H2, ISO de l'Evaluation Center, 5,4 Go, pas de somme publiée), 2 vCPU, 4 Gio, 64 Gio (minimums de Windows 11), carte e1000e sur seg-cli (MAC `02:50:00:00:30:10`). UEFI (`firmware = "efi"`, SMM) et TPM 2.0 émulé (swtpm), exigés par Windows 11 et utiles pour BitLocker (mission 6). `tofu plan` ciblé : 5 ressources ajoutées, rien d'autre.
- `windows/autounattend-client.xml.tftpl` : partitions GPT (EFI, MSR, Windows), adresse par DHCP, contrôle Secure Boot contourné (`LabConfig\BypassSecureBootCheck`, car il dépend du micrologiciel choisi par libvirt), pas de compte à créer dans l'OOBE (Administrator intégré activé par son mot de passe, pour Ansible seulement), puis le même `setup-winrm.ps1` que les serveurs.
- En UEFI, l'ISO Windows attend « Press any key to boot from CD » : `terraform_data.client01_boot_key` envoie une touche chaque seconde pendant 30 s après la création de la VM (`virsh send-key`).
- pfSense : bail DHCP fixe `10.50.30.10` pour CLIENT01, hors de la plage `.100`–`.199` (rôle `pfsense`, module `pfsense_dhcp_static`). Reporté dans le plan d'adressage de la mission 2.
- `pfsense_temporary.yml` : active ou désactive une règle temporaire (F21, F22) avec les mêmes réglages que le rôle `pfsense` (`-e rule=F21 -e enabled=true|false`). Lancé depuis le Mac ou le serveur, car pfSense n'a pas la clé d'ADMIN01.
- Rôle `client01` + `client01.yml` (depuis ADMIN01) : OU `Postes` sur DC01, jonction au domaine dans cette OU, groupe Administrateurs local réduit à `Administrator` et `VINOVERITAS\Domain Admins` (`state: pure`), agent Wazuh (F23). `client01.yml` s'arrête avec un message clair si F21 n'est pas activée. `verify.yml` : membre du domaine, OU, adresse et DNS par DHCP (DC01), administrateurs locaux.
- CLIENT01 ajouté à `inventory.yml` (groupe `windows`) : `wazuh_agents.yml --limit windows` le couvre aussi.

### 25. Tableau de bord des vulnérabilités (code prêt, à lancer par l'utilisateur)
- Constaté sur SIEM01 : index `wazuh-states-vulnerabilities-*` (modèle d'index créé par Wazuh, sans champ de date : c'est un état, la période choisie n'a pas d'effet), environ 9 800 vulnérabilités : DC01 et FS01 3 990 chacun (125 critiques), ADMIN01 et OVS environ 920 (46 critiques, 326 sans score). SIEM01 lui-même n'est pas analysé.
- « Vino Veritas — Vulnérabilités » : en haut, cartographie par service (carte de chaleur : service rendu par chaque machine × gravité, avec des filtres nommés « Annuaire, DNS (DC01) », « Fichiers (FS01) », « Poste de travail (CLIENT01) », « Administration (ADMIN01) », « Réseau (OVS) ») et total par gravité ; dessous, un sélecteur de machine (`agent.name`) qui filtre tout le tableau de bord ; puis les vulnérabilités critiques et élevées (CVE, score, paquet, machines) et les paquets les plus vulnérables.
- Rôle `wazuh` : chaque tableau de bord déclare le modèle d'index qu'il lit (`pattern` dans `wazuh_dashboards`) ; le rôle retrouve l'identifiant de chaque modèle par son titre (`wazuh_pattern_ids`) et vérifie qu'il existe.
- Pas testé contre SIEM01 : export généré par script, JSON validé, expression des identifiants testée en local.

### 26. 2-lab : un fichier par machine, modules pour ce qui est commun
- `vms.tf` (ADMIN01, OVS) et `windows.tf` (DC01, FS01) découpés : un fichier par machine (`admin01.tf`, `ovs.tf`, `siem01.tf`, `dc01.tf`, `fs01.tf`, `client01.tf`, `pfsense.tf`), chacun n'appelle qu'un module avec les réglages de la machine.
- Modules dans `2-lab/modules/` : `debian_vm` (image cloud, cloud-init, cartes réseau), `windows_vm` (ISO sans intervention, disque de données facultatif, `edition = "server"` ou `"client"` : UEFI, TPM 2.0 et touche au démarrage pour Windows 11), `server_iso` (téléchargement d'un ISO sur le serveur, somme et gzip facultatifs). Les gabarits Windows sont passés dans `modules/windows_vm/templates/`.
- `images.tf` regroupe les images : Debian, ISO Windows Server 2022, Windows 11 et pfSense. `locals.tf` : accès SSH au serveur, clés SSH, mot de passe Administrator, réseau ADMIN.
- `moved.tf` : 26 blocs `moved`. `tofu plan` : rien à créer ni à détruire. Seule différence : CLIENT01 `running = false -> true` (VM éteinte au moment du plan, sans lien avec le découpage).
- SIEM01 garde ses noms de cartes netplan (`seg-siem`, `nat`, option `name` du module) : sinon cloud-init, donc la VM, aurait été reconstruit.
- `tofu apply` lancé par l'utilisateur, déplacements enregistrés dans l'état : `moved.tf` supprimé, plan vide ensuite.
- Correction au passage : la touche au démarrage de CLIENT01 se déclenchait sur l'`id` de la VM, le numéro d'exécution, qui change à chaque démarrage ; elle se déclenche maintenant sur son `uuid` (un dernier remplacement au prochain `apply`, sans effet sur Windows déjà installé).

### 27. trigger-events.sh : alertes manquantes (corrigé, à relancer par l'utilisateur)
- Premier lancement (4 novembre) : `ssh`, `admin` et `ad` arrivent dans Wazuh ; rien pour `brute`, `blocked` et `scan`.
- `brute` : `curl --ntlm` envoie `Authorization: NTLM`, WinRM ne propose que `Negotiate` et `Kerberos` et répond 401 sans rien vérifier : aucun 4625 sur DC01 (audit des échecs pourtant actif). Le script passe par pywinrm (`transport=ntlm`, comme Ansible) : 4625 vérifié dans Wazuh (règle 60122). Le 4625 n'a pas de champ `ipAddress` (connexion NTLM par HTTP), seulement `workstationName` (`ADMIN01`).
- `blocked`, `scan` : le décodeur `vinoveritas-pfsense` n'a jamais reconnu une vraie ligne : sans nom de programme trouvé, l'en-tête `filterlog[pid]: ` reste dans le message lu par les décodeurs, et l'expression était ancrée en `^`. Même la ligne de `verify.yml` échouait. Expressions corrigées (`(?:^|filterlog\[\d+\]: )`), testées avec `wazuh-logtest` sur SIEM01 (décodeur temporaire, retiré ensuite).
- `verify.yml` ne pouvait pas voir ce défaut : `wazuh-logtest` écrit son résultat sur stderr, le contrôle lisait stdout (vide). `2>&1` ajouté.

### 28. FS01 sans disque de données : partages dans C:\Partages (code prêt, à lancer par l'utilisateur)
- Pour simplifier : le disque `D:` obligeait à déplacer les lecteurs de CD de l'installation (`Y:`, `Z:`) pour libérer la lettre. Le sujet n'impose pas de disque séparé.
- `2-lab` : option `data_disk` retirée du module `windows_vm` et de `fs01.tf`. `tofu plan` : FS01 modifié sur place (pas recréé), `fs01-data.qcow2` détruit ; s'y ajoute le remplacement de la touche au démarrage de CLIENT01 (entrée 26).
- Rôle `fs01` : tâches des lecteurs de CD et du disque retirées, `verify.yml` ne contrôle plus de disque. `shares_root: C:\Partages` ; le rôle `file_shares` coupe l'héritage depuis `C:` (même raison qu'avant : « Utilisateurs » en lecture à la racine).
- La saturation du disque par un partage est couverte par les quotas FSRM (à faire, mission 5).

### 29. Adresses centralisées dans ansible/group_vars/all/network.yml
- Un seul fichier donne le plan d'adressage : `lab_network`, `zones` (VLAN, réseau, passerelle pfSense, plage DHCP de POSTES), `ips` (adresse de chaque machine dans sa zone), `server_tunnel_ip` et `nat_ips` (liens nat temporaires).
- Y renvoient : `inventory.yml` (`ansible_host`, `ProxyJump`), `host_vars/pfsense.yml` (zones, DHCP, syslog, alias), `host_vars/ovs.yml` (`mgmt`), les `defaults` des rôles `admin`, `dc01`, `fs01`, `wazuh`, `wazuh_agent`, `windows_base`, et les tâches qui citaient `10.50.0.0/16`, DC01 ou pfSense. Les noms des variables des rôles ne changent pas.
- Restent en dur : la ligne de journal de test de `wazuh/tasks/verify.yml`, les commandes d'aide en commentaire de `dc01.yml` et `fs01.yml`, et `scripts/trigger-events.sh` (script bash, renvoi en commentaire). `2-lab/` (OpenTofu) garde ses propres adresses.
- Vérifié sans rien appliquer : toutes les variables touchées (hôtes, `ProxyJump`, zones, DHCP, alias, `ovs_mgmt`, enregistrements DNS, valeurs par défaut des rôles) donnent exactement les mêmes valeurs qu'avant (rendu comparé avant et après le changement) ; `--syntax-check` passe sur tous les playbooks.

## À faire
- FS01 : après `dc01.yml`, `tofu apply` pour créer FS01, attendre la fin de l'installation, puis rsync et `ansible-playbook fs01.yml` depuis ADMIN01.
- DC01 : quand Windows a fini de s'installer, copier `ansible/` sur ADMIN01 (rsync) et y lancer `ansible-playbook dc01.yml` (commandes en tête de `dc01.yml`).
- Exporter `config.xml` de pfSense dans le dépôt (sans les secrets).
- Passer la route par défaut d'ADMIN01 (puis des autres VM) sur pfSense, et retirer les liens nat temporaires.
- Définir le mot de passe de `debian` (`ssh debian@10.99.0.1 sudo passwd debian`) pour se connecter à Cockpit.
- Lancer `ansible-playbook admin01.yml` (rôles devtools, admin et server_access).
- Ajouter `192.168.206.0/24` aux `AllowedIPs` du tunnel du Mac (déjà fait pour la connexion par `-J`, pas encore pour un accès direct).
- Remplacer `admin_user = "root"` par un compte nommé, puis reconstruire ADMIN01 et OVS.
- Pare-feu de l'hôte : SSH est encore ouvert sur l'IP publique (clé seule).
- Mettre à jour la note *Labo chez OVH avec Proxmox et Terraform* : elle décrit encore Proxmox et Packer, et le dépôt d'infra.
- Ansible sur ADMIN01 : cloud-init doit installer Ansible et cloner ce dépôt.
- SIEM01 : relancer `ansible-playbook siem01.yml` (route vers les zones, syslog de pfSense). Le rôle `wazuh` reçoit aussi le syslog de pfSense (F26) : bloc `<remote>` ajouté à `ossec.conf` (514/udp, seule `10.50.20.1` acceptée), vérifié par `verify.yml` ; écrit mais pas encore lancé.
- Partages dans `C:\Partages` : `tofu apply` dans `2-lab/`, puis `ansible-playbook file_shares.yml` depuis ADMIN01.
- Agents Wazuh, dans l'ordre : `siem01.yml`, `ovs.yml`, `pfsense.yml` (alias F18), puis `wazuh_agents.yml --limit admin01,ovs` (Mac ou serveur) et `wazuh_agents.yml --limit windows` (ADMIN01).
- Tableau de bord : `git pull` sur le serveur, puis `ansible-playbook siem01.yml`.
- Journaux pfSense et tableau de bord « Réseau » : `git pull` sur le serveur, puis `ansible-playbook siem01.yml`.
- CLIENT01, dans l'ordre : `pfsense.yml` (bail fixe), `tofu apply` dans `2-lab/` (crée CLIENT01, télécharge l'ISO), attendre la fin de l'installation, puis F21 activée, `client01.yml` depuis ADMIN01, F21 désactivée.
