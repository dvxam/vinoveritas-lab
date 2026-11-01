# vinoveritas-lab

Code du labo Vino Veritas : serveur OVH sous Debian 13, KVM/libvirt, réseaux et machines virtuelles du TP.

## Structure

```
1-server/   serveur OVH déjà loué : réinstallation Debian, WireGuard, paquets, libvirt, Cockpit (OpenTofu, provider ovh/ovh)
2-lab/      une VM Debian 13 dans libvirt (OpenTofu, provider dmacvicar/libvirt, par SSH)
later/       code complet du labo (segments, pfSense, Windows), pas encore utilisé
```

Adresses et connexions : voir [NETWORK.md](NETWORK.md).

## Ordre de lancement

1. `1-server/` : `dotenvx run -- tofu apply` installe WireGuard, les paquets, libvirt et Cockpit (optionnel, voir `1-server/cockpit.tf`).
2. Tunnel WireGuard actif sur le Mac, puis une fois `ssh debian@10.99.0.1` (clé d'hôte).
3. `2-lab/` : `tofu apply` crée le réseau nat et la VM Debian ; `tofu output ssh` donne la commande de connexion.

Consoles des VM (VNC, écoute locale au serveur) : `ssh -L 5900:127.0.0.1:5900 debian@10.99.0.1`, puis `vnc://localhost:5900` (5901, 5902… pour les VM suivantes ; `virsh vncdisplay <vm>` donne le numéro).

## Secrets

Rien de sensible n'est versionné (voir `.gitignore`). Il faut à la main :

- `1-server/.env` : identifiants OVH ;
- `1-server/terraform.tfvars` : nom de service OVH, clé publique WireGuard du Mac ;
- `2-lab/terraform.tfvars` : compte admin de la VM.

L'état (`*.tfstate`) reste sur le Mac et n'est jamais commité.
