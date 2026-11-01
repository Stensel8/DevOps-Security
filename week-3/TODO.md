# Week 3 - status

## Gemaakt
- [x] 3.1 SBOM van het image gemaakt met Trivy (CycloneDX), voor en na de fix vergeleken
- [x] 3.2 Docker Scout-scan: kwetsbaarheden in de beginstaat aangetoond en opgelost (Alpine, multi-stage build, non-root)
- [x] Extra: securityheaders.com van D naar A (CSP, Permissions-Policy, COOP, CORP)
- [x] 3.3 Docker Scout in de `scan`-job van `build.yaml` gedocumenteerd, incl. bewijs van een rode en een groene run (gunicorn-CVE's)
- [x] 3.4 Geschreven: welke testsoorten in de pipeline zitten en wat er nog ontbreekt
- [x] Extra: CodeRabbit gekoppeld (issue [#39](https://github.com/Stensel8/DevOps-Security/issues/39), 14 dagen trial), `.coderabbit.yaml` toegevoegd, bewijs: CodeRabbit vond zelf de log-injectie in `app.py` en opende zelfstandig PR #41 met fix + 68 regels tests (screenshot + diff in week-3/README.md)
- [x] 3.5 Postman-collectie (`tests/postman/`) + Newman-stap in de `Test`-job van `build.yaml`: HTTP 200 + "Quoter XP" in de body
- [x] 3.6 Extra security-test in dezelfde collectie: headers + dat de app op gunicorn draait, niet op `flask run`
- [x] 3.7 Advies: proces voor veilige images en teststrategie, met tooling-advies

## Nog te doen
Geen, week 3 is compleet. De Postman-tests zijn zowel lokaal als in de echte pipeline-run bevestigd groen (screenshot in README.md).

---
Hier houd ik bij wat ik nog moet doen.
