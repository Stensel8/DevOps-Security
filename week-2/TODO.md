# Week 2 - status

## Gemaakt
- [x] 2.1 Snyk gekoppeld aan GitHub, repository gescand (Snyk Code, Snyk IaC, Snyk Open Source)
- [x] 2.1 Extra: GitHub Advanced Security met CodeQL ingericht, secret scanning met push protection aan
- [x] 2.2 Fix 1: SQL-injectie, parameters i.p.v. f-strings (commit `4965429`)
- [x] 2.2 Fix 2: XSS, `markupsafe.escape` in de templates (commit `251f107`)
- [x] 2.2 Fix 3: dependencies geüpgraded + SHA-pinning (Renovate/Dependabot)
- [x] 2.2 Fix 4: cookie met `HttpOnly`/`SameSite` (commit `3dfae64`)
- [x] 2.2 Fix 5: redirect met `url_for` (commit `2a2e85f`)
- [x] 2.2 Fix 6: Snyk IaC-punten in `deployment.yaml` opgelost (non-root, capabilities drop, read-only fs, resource limits, liveness probe)
- [x] 2.2 Extra fixes: wachtwoorden niet meer in het logbestand, `static_folder` dicht, wachtwoorden gehasht, cookie vervangen door ondertekende sessie
- [x] 2.3 Advies veilig ontwikkelen in Plan en Code (threat modeling, OWASP, SAST/DAST)
- [x] CodeRabbit-stukje verplaatst naar week 3 (issue [#39](https://github.com/Stensel8/DevOps-Security/issues/39), daar afgerond)

## Nog te doen
Geen, week 2 is compleet. Bewust open gelaten, geen Snyk/CodeQL-melding meer voor: `Secure`-vlag op de cookie (kan pas met HTTPS, zie week 5), CSRF-bescherming, limiet op inlogpogingen.

---
Hier houd ik bij wat ik nog moet doen.
