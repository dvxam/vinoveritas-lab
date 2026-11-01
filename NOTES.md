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

## À faire
- Relever l'adresse DHCP d'OVS (`tofu -chdir=2-lab output ssh`) et la reporter dans `ansible/inventory.yml` si elle a changé.
- Ajouter `192.168.206.0/24` aux `AllowedIPs` du tunnel du Mac (déjà fait pour la connexion par `-J`, pas encore pour un accès direct).
- Remplacer `admin_user = "root"` par un compte nommé, puis reconstruire ADMIN01 et OVS.
- Brancher ADMIN01 sur seg-admin pour que le port `mgmt` réponde depuis ADMIN01.
- Pare-feu de l'hôte : SSH est encore ouvert sur l'IP publique (clé seule).
- Mettre à jour la note *Labo chez OVH avec Proxmox et Terraform* : elle décrit encore Proxmox et Packer, et le dépôt d'infra.
- Ansible sur ADMIN01 : cloud-init doit installer Ansible et cloner ce dépôt.
