# Setup

Hier staat alleen het verversen van de AWS-credentials. De rest van de omgeving (EC2-VM's, K3s, de pipeline) staat beschreven in [week-1/README.md](../week-1/README.md).

## Lab-credentials verversen

Een AWS Academy Learner Lab-sessie verloopt na een paar uur. [`setup/lab-login.sh`](lab-login.sh) vraagt interactief om nieuwe credentials, zet ze in `~/.aws/credentials` en test meteen met `aws sts get-caller-identity`.

```bash
./setup/lab-login.sh
```

In de lab-omgeving: **AWS Details → AWS CLI** (of "Cloud Access"), daar staan `aws_access_key_id`, `aws_secret_access_key` en `aws_session_token`, plus de AccountId en regio die als profielnaam dienen.

Dit scriptje heb ik met Claude Sonnet 5 geschreven voor [Cloud-Security](https://github.com/Stensel8/Cloud-Security) (ander vak, zelfde AWS Academy Learner Lab) en hergebruik ik hier gewoon één op één. Scheelt me elke keer opnieuw dezelfde prompts uittypen voor twee vakken die toch dezelfde lab-omgeving delen.
