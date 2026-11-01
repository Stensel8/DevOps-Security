# Week 5 - status

## Gemaakt
- [x] 5.1 kube-bench baseline gedraaid, 3 Level 2-maatregelen uit 3 families toegepast (5.7 al aanwezig sinds week 2, 5.2 Pod Security "restricted", 3.2 audit logging), opnieuw gedraaid: 5 bevindingen WARN->PASS, plus een containerd-check (socket-rechten, al goed)
- [x] 5.2 Ingress met TLS (Traefik, al ingebouwd in K3s) op NodePort 31189 (niet 443), getest op CN1 zelf met een self-signed cert
- [x] 5.3 Geschreven: welke CNI K3s standaard gebruikt (Flannel + de ingebouwde kube-router policy-controller), of die te vervangen is, en of een andere CNI (Calico/Cilium) veiliger zou zijn
- [x] 5.3 praktisch deel: NetworkPolicy toegepast en bewezen (poort 5000 open, poort 9999 timeout) — zie `kubernetes/networkpolicy.yaml` en week-5/README.md
- [x] 5.4 Geschreven: Terraform/Ansible-toegang herontwerpen zonder adminwachtwoord (SSH-sleutels/SSM, IAM-rol via OIDC, ansible-vault)
- [x] 5.2 extern getest: security group had NodePort 30000 nog op `0.0.0.0/0`/`::/0` staan (klopte niet met week-1/README.md), verkrapt naar eigen IP; nieuwe regels voor 6443 (API) en 31189 (Ingress) toegevoegd, ook op eigen IP. Extern getest (niet via SSH, rechtstreeks vanaf eigen laptop): Ingress en de Kubernetes-API allebei HTTP 200
- [x] 5.4 TryHackMe "Cluster Hardening"-room afgerond (100%, alle 8 taken, screenshot in README.md), 3 belangrijkste hardeningspunten voor SolidApps beschreven (TLS tussen control-plane-componenten, RBAC least privilege, admission controllers)

## Nog te doen
Geen, week 5 is compleet.

---
Hier houd ik bij wat ik nog moet doen.
