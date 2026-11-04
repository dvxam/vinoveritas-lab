# Réseau du labo

Adresses de toutes les machines et façon de s'y connecter. Mis à jour à chaque machine ajoutée.

*Dernière mise à jour : 1er novembre 2026. ADMIN01 et OVS tournent ; OVS est configuré par `ansible/` (pont `br0`, ports VLAN, `mgmt`). Cockpit installé sur le serveur, joignable par le tunnel. pfSense installé et configuré par `ansible/pfsense.yml` (4 zones, DHCP POSTES, DNS, règles de la matrice).*

## Schéma

```
                     Internet
                        │
                        │  51.161.128.8 (enp1s0f0)
                        │  ouvert : SSH 22/tcp (clé seule), WireGuard 51820/udp
┌───────────────────────┴─────────────────────────────────────────────────┐
│ Serveur OVH « pve » — Debian 13, KVM/libvirt                            │
│                                                                         │
│   wg0      10.99.0.1  ◄─────── tunnel WireGuard ───────┐                │
│            Cockpit https://10.99.0.1:9090 (tunnel)     │                │
│   lab-nat  192.168.206.1  (passerelle, DHCP, DNS)      │                │
│      │                                                 │                │
│      ├── ADMIN01  192.168.206.10  (lien temporaire)    │                │
│      ├── OVS      192.168.206.166 (DHCP, temporaire)   │                │
│      └── pfSense  192.168.206.167 (WAN, DHCP)          │                │
│                                                        │                │
│   Segments isolés (pas d'adresse sur le serveur) :     │                │
│     seg-admin ── ADMIN01 10.50.10.10 ── OVS            │                │
│     seg-trunk ── pfSense em1 (VLAN 10 : 10.50.10.1) ── OVS                │
│     seg-dc, seg-fs, seg-cli,                           │                │
│     seg-backup, seg-siem ──────────────── OVS          │                │
└────────────────────────────────────────────────────────┼────────────────┘
                                                         │
                                             Mac  10.99.0.2
```

- Le Mac joint le serveur par le tunnel (`10.99.0.1`). Il joint les VM par le même tunnel, à condition d'avoir `192.168.206.0/24` dans ses `AllowedIPs`.
- Les VM sortent sur Internet par le NAT du serveur (service `lab-nat`).
- ADMIN01 sort encore par son lien `nat` : pfSense ne route pas encore vers Internet pour le VLAN 10 (configuration Ansible à venir).

## Machines

Côté Ansible, ces adresses ne sont écrites qu'une fois, dans `ansible/group_vars/all/network.yml` : à modifier en même temps que ce tableau (et `2-lab/` pour les VM).

| Machine | Rôle | Adresse(s) | Compte SSH | Créée par |
|---|---|---|---|---|
| Mac | Poste d'administration | `10.99.0.2` (tunnel) | — | — |
| pve | Serveur OVH, hyperviseur ; Cockpit sur `10.99.0.1:9090` | `51.161.128.8` (public), `10.99.0.1` (tunnel), `192.168.206.1` (lab-nat) | `debian` (sudo) ; root refusé | `1-server/` |
| ADMIN01 | Poste d'administration du labo (VLAN 10) | `10.50.10.10` (seg-admin), `192.168.206.10` (nat, temporaire) | `root` (`admin_user`) | `2-lab/` |
| SIEM01 | Wazuh tout-en-un (VLAN 20) — VM créée, Wazuh pas encore installé | `10.50.20.30` (seg-siem), `192.168.206.30` (nat, temporaire) | `root` (`admin_user`) | `2-lab/siem01.tf` |
| CLIENT01 | Poste Windows 11 (VLAN 30) — code prêt, pas encore créé | DHCP de pfSense, plage `.100` à `.199` (seg-cli) ; Ansible le joint par son nom `client01.vinoveritas.local` | `Administrator` (WinRM depuis ADMIN01, règle temporaire F21) | `2-lab/client01.tf` |
| OVS | Commutateur Open vSwitch | `192.168.206.166` (nat, DHCP, temporaire) ; `10.50.10.2` (mgmt, VLAN 10) ; ports sans adresse sur les 7 segments | `root` (`admin_user`) | `2-lab/` |

| DC01 | Contrôleur de domaine `vinoveritas.local`, DNS (Windows Server 2022) | `10.50.20.10` (seg-dc, VLAN 20) | `Administrator` (mot de passe dans `ansible/secrets/windows.yml`) ; WinRM 5986 et RDP depuis ADMIN | `2-lab/dc01.tf` |
| FS01 | Serveur de fichiers, membre du domaine (Windows Server 2022) | `10.50.20.20` (seg-fs, VLAN 20) | `Administrator` local, puis comptes du domaine ; WinRM 5986 et RDP depuis ADMIN | `2-lab/fs01.tf` |
| pfSense | Pare-feu et routeur | `192.168.206.167` (WAN `em0`, DHCP sur nat) ; `10.50.10.1` (LAN `em1.10`, VLAN 10) | `admin` (clé SSH ; mot de passe dans `ansible/secrets/pfsense.yml`) | `2-lab/pfsense.tf` + console |

- L'adresse d'OVS vient du DHCP : la valeur à jour est donnée par `tofu -chdir=2-lab output ssh`.

### Adresses MAC fixes

| Machine | Réseau | MAC | Nom dans la VM (avant `.link`) |
|---|---|---|---|
| ADMIN01 | seg-admin | `02:50:00:00:10:10` | — |
| ADMIN01 | nat | `02:50:00:00:10:11` | — |
| SIEM01 | seg-siem | `02:50:00:00:20:30` | — |
| SIEM01 | nat | `02:50:00:00:20:31` | — |
| DC01 | seg-dc | `02:50:00:00:20:10` | — |
| FS01 | seg-fs | `02:50:00:00:20:20` | — |
| pfSense | nat (WAN) | `02:50:00:00:00:01` | em0 |
| pfSense | seg-trunk (LAN) | `02:50:00:00:00:02` | em1 |
| CLIENT01 | seg-cli | `02:50:00:00:30:10` | — |
| OVS | nat | `02:50:00:00:01:00` | enp1s0 |
| OVS | seg-trunk | `02:50:00:00:01:01` | enp8s0 |
| OVS | seg-admin | `02:50:00:00:01:10` | enp2s0 |
| OVS | seg-dc | `02:50:00:00:01:20` | enp5s0 |
| OVS | seg-fs | `02:50:00:00:01:21` | enp6s0 |
| OVS | seg-siem | `02:50:00:00:01:22` | enp7s0 |
| OVS | seg-cli | `02:50:00:00:01:30` | enp4s0 |
| OVS | seg-backup | `02:50:00:00:01:40` | enp3s0 |

Les MAC d'OVS sont dans `ansible/host_vars/ovs.yml`.

## Réseaux

| Réseau | Plage | Passerelle | DHCP | Rôle |
|---|---|---|---|---|
| Tunnel WireGuard | `10.99.0.0/24` | `10.99.0.1` (serveur) | non | Administration depuis le Mac |
| lab-nat (libvirt `nat`) | `192.168.206.0/24` | `192.168.206.1` (serveur) | `.100` à `.199` | Lien temporaire des VM, sortie Internet par NAT |
| seg-admin | `10.50.10.0/24` (VLAN 10) | `10.50.10.1` (pfSense) | non | ADMIN01 ↔ OVS ↔ pfSense |
| seg-trunk | VLAN étiquetés 10, 20, 30, 40 | — | non | pfSense (`em1.10` à `em1.40`) ↔ OVS |
| seg-dc, seg-fs, seg-siem | `10.50.20.0/24` (VLAN 20) | `10.50.20.1` (pfSense) | non | Une machine ↔ OVS |
| seg-cli | `10.50.30.0/24` (VLAN 30) | `10.50.30.1` (pfSense) | pfSense, `.100` à `.199` | CLIENT01 ↔ OVS |
| seg-backup | `10.50.40.0/24` (VLAN 40) | `10.50.40.1` (pfSense) | non | BACKUP01 ↔ OVS |

## Se connecter

**Serveur**, par le tunnel (ou par l'IP publique tant que SSH y est ouvert) :
```bash
ssh debian@10.99.0.1
```

**ADMIN01**, depuis le serveur, connecté en `debian` (une fois `admin01.yml` lancé : clé et alias posés par Ansible) :
```bash
ssh admin01
```

**Noms des VM sur le serveur** (`ssh ovs`, `ssh siem01`, `ssh pfsense`, `ping siem01`…) : fichiers `server/ssh_config` et `server/hosts`, à installer une fois sur le serveur (commandes en tête de chaque fichier). `admin01` est déjà connu de `~/.ssh/config` (rôle `server_access`) ; pfSense passe par ADMIN01.

**ADMIN01**, en rebondissant par le serveur :
```bash
ssh -J debian@10.99.0.1 root@192.168.206.10
```

**ADMIN01**, directement depuis le Mac (après avoir ajouté `192.168.206.0/24` aux `AllowedIPs` du tunnel) :
```bash
ssh root@192.168.206.10
```

**OVS** :
```bash
ssh -J debian@10.99.0.1 root@192.168.206.166
```

**pfSense**, depuis ADMIN01 (SSH et interface web sur `10.50.10.1`, VLAN 10) :
```bash
ssh admin@10.50.10.1
```
Interface web depuis le Mac : `ssh -L 8443:10.50.10.1:443 -J debian@10.99.0.1 root@192.168.206.10`, puis `https://localhost:8443`. Console : Cockpit, page Machines, VM `pfsense`.

**Cockpit** (interface web du serveur et des VM, console graphique dans le navigateur), par le tunnel uniquement :
```
https://10.99.0.1:9090
```
Compte `debian`, avec son mot de passe (défini une fois par `ssh debian@10.99.0.1 sudo passwd debian` ; SSH reste en clé seule). Certificat auto-signé : accepter l'avertissement du navigateur. Pour regarder et démarrer ou arrêter les VM, pas pour les créer ou les modifier (c'est le rôle de `2-lab/`). Installé par `1-server/cockpit.tf`, qui explique comment l'enlever.

**Console d'une VM** (si SSH ne répond pas), depuis le serveur, `Ctrl+]` pour quitter :
```bash
virsh -c qemu:///system console admin01
```

## Tunnel WireGuard du Mac

```ini
[Interface]
PrivateKey = (générée par l'application, reste sur le Mac)
Address = 10.99.0.2/32

[Peer]
PublicKey = 6c6/NXIC+gEhhf7OuvmA+msQhpr7GjTUuq9D6qxQ+0A=
Endpoint = 51.161.128.8:51820
AllowedIPs = 10.99.0.0/24, 192.168.206.0/24
PersistentKeepalive = 25
```

La clé publique du serveur se relit avec `tofu -chdir=1-server output -raw wireguard_server_key_command`.
