# Lancé une fois par autounattend.xml : active WinRM en HTTPS pour Packer et Ansible (flux F11).
# Repris de bootstrap/windows.ps1 du dépôt vinoveritas-infra.
$ErrorActionPreference = 'Stop'

Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\Auth\Negotiate -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false

$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

New-NetFirewallRule -DisplayName 'WinRM HTTPS' -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow | Out-Null
