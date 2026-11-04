#!/usr/bin/env bash
# Triggers security events of the lab, to fill the Wazuh dashboards ("Accès et identités", "Réseau").
# Run on ADMIN01, from the ansible/ directory copied there (rsync, see dc01.yml):
#   bash scripts/trigger-events.sh            # every scenario
#   bash scripts/trigger-events.sh brute scan # some of them
# Scenarios:
#   brute    failed logons on DC01 and FS01 (WinRM, wrong password)  -> 4625, "Comptes en échec"
#   ssh      failed SSH logons on OVS and ADMIN01 (unknown accounts)  -> sshd alerts
#   admin    logon of Administrator on DC01 from ADMIN01             -> 4624, "Comptes à privilèges"
#   ad       temporary account, added to Domain Admins, then deleted -> 4720, 4728, 4729, 4726
#   blocked  connections refused by pfSense (SMB, LDAP from ADMIN)   -> "Matrice des flux bloqués"
#   scan     30 closed ports on FS01 in a few seconds                -> rule 100203 "Balayages"
# Everything is undone at the end (the temporary account is deleted). Nothing is sent outside the lab.
set -euo pipefail

DC01=10.50.20.10
FS01=10.50.20.20
OVS=10.50.10.2
SECRETS=secrets/windows.yml
SCENARIOS=("$@")
[ ${#SCENARIOS[@]} -eq 0 ] && SCENARIOS=(brute ssh admin ad blocked scan)

say() { printf '\n== %s\n' "$*"; }

# WinRM logon with NTLM, through pywinrm (as Ansible does): a wrong password is a failed network
# logon (4625) on the target. Not curl --ntlm: it sends "Authorization: NTLM", WinRM only offers
# Negotiate and Kerberos and answers 401 before checking anything, so Windows logs nothing.
winrm_logon() { # host user password -> ok | refusé | erreur
  python3 - "$@" <<'PY' 2>/dev/null || echo erreur
import sys, warnings
import winrm
from winrm.exceptions import InvalidCredentialsError
warnings.filterwarnings("ignore")
host, user, password = sys.argv[1:4]
session = winrm.Session(f"https://{host}:5986/wsman", auth=(user, password), transport="ntlm",
                        server_cert_validation="ignore", operation_timeout_sec=10, read_timeout_sec=15)
try:
    session.run_cmd("hostname")
    print("ok")
except InvalidCredentialsError:
    print("refusé")
PY
}

# TCP connection attempt, quiet: the result does not matter, pfSense logs the block
knock() { # host port
  timeout 2 bash -c "</dev/tcp/$1/$2" 2>/dev/null || true
}

admin_password() {
  [ -f "$SECRETS" ] || { echo "$SECRETS absent : lancer depuis ansible/, après le rsync du Mac" >&2; exit 1; }
  sed -n 's/^windows_admin_password: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$SECRETS"
}

brute() {
  say "Échecs de connexion sur DC01 et FS01 (WinRM, mauvais mot de passe)"
  # A real account (password spraying) and accounts that do not exist
  for user in claire.martin nicolas.roux helene.garnier administrateur test admin; do
    for host in $DC01 $FS01; do
      printf '%s@%s : %s\n' "$user" "$host" "$(winrm_logon "$host" "VINOVERITAS\\$user" 'Mauvais-mot-de-passe-1')"
    done
  done
}

ssh_failures() {
  say "Échecs SSH sur OVS et ADMIN01 (comptes inconnus)"
  for host in $OVS 127.0.0.1; do
    for user in admin oracle backup; do
      ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password \
          "$user@$host" true 2>/dev/null || true
      echo "$user@$host : refusé"
    done
  done
}

admin_logon() {
  say "Connexion d'Administrator sur DC01 depuis ADMIN01 (attendu : seulement d'ici)"
  printf 'Administrator@%s : %s\n' "$DC01" "$(winrm_logon $DC01 'VINOVERITAS\Administrator' "$(admin_password)")"
}

ad_changes() {
  say "Compte temporaire, ajouté à Domain Admins, puis supprimé"
  local ps
  ps=$(cat <<'PS'
$name = 'test.alerte'
$pw = ConvertTo-SecureString ([guid]::NewGuid().ToString() + 'Aa1!') -AsPlainText -Force
New-ADUser -Name $name -SamAccountName $name -AccountPassword $pw -Enabled $true -Path 'OU=Utilisateurs,DC=vinoveritas,DC=local' -Description 'Compte de test (trigger-events.sh)'
Add-ADGroupMember 'Domain Admins' -Members $name
Start-Sleep -Seconds 5
Remove-ADGroupMember 'Domain Admins' -Members $name -Confirm:$false
Remove-ADUser $name -Confirm:$false
'créé, ajouté à Domain Admins, retiré, supprimé'
PS
)
  # Module arguments as JSON: the script has quotes and several lines
  ansible dc01 -e @"$SECRETS" -m ansible.windows.win_powershell \
    -a "$(python3 -c 'import json,sys; print(json.dumps({"script": sys.stdin.read()}))' <<<"$ps")" \
    | grep -E 'SUCCESS|CHANGED|FAILED|"msg"|créé' || true
}

blocked() {
  say "Flux refusés par pfSense depuis ADMIN01 (hors matrice : SMB, LDAP, MS-SQL)"
  for port in 445 389 1433; do
    knock $DC01 $port; knock $FS01 $port
    echo "$DC01:$port et $FS01:$port : tentés"
  done
}

scan() {
  say "Balayage de 30 ports fermés sur FS01 (plus de 20 refus en une minute)"
  for port in $(seq 8000 8029); do knock $FS01 "$port"; done
  echo "ports 8000 à 8029 tentés"
}

for scenario in "${SCENARIOS[@]}"; do
  case "$scenario" in
    brute) brute ;;
    ssh) ssh_failures ;;
    admin) admin_logon ;;
    ad) ad_changes ;;
    blocked) blocked ;;
    scan) scan ;;
    *) echo "Scénario inconnu : $scenario (brute ssh admin ad blocked scan)" >&2; exit 1 ;;
  esac
done

say "Terminé : les alertes arrivent dans Wazuh en une minute environ (dernières 24 h des tableaux de bord)"
