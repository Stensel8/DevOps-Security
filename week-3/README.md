# Week 3: Veilige images en testen in de pipeline

In deze week staan de beveiliging van het container-image en het testen in de pipeline centraal. Een container-image bestaat uit veel meer dan de eigen code: een besturingssysteem, libraries en packages van anderen. Een SBOM (software bill of materials) is een lijst van al die onderdelen, in een vast formaat zoals CycloneDX [(CycloneDX, z.d.)](https://cyclonedx.org/) of SPDX [(The Linux Foundation, z.d.)](https://spdx.dev/). Een scanner zoals Docker Scout [(Docker, z.d.-a)](https://docs.docker.com/scout/) of Trivy [(Aqua Security, z.d.)](https://trivy.dev) vergelijkt die onderdelen met databases van bekende kwetsbaarheden.

Hoe minder er in een image zit, hoe minder er kwetsbaar kan zijn. Met een multi-stage build wordt de applicatie in een tussenstap gebouwd, en gaat alleen het resultaat mee naar het image dat echt draait [(Docker, z.d.-b)](https://docs.docker.com/build/building/multi-stage/). De tools die nodig zijn om te bouwen, komen zo niet in productie terecht.

Deze week bestaat uit zeven opdrachten. Paragraaf 3.1 gaat over het maken van een SBOM, en paragraaf 3.2 over het kwetsbaarheidsvrij maken van het image met Docker Scout. Paragraaf 3.3 beschrijft Docker Scout in de pipeline. Paragraaf 3.4 tot en met 3.6 gaan over testen: welke soorten tests er zijn, en Postman-tests in de pipeline. Paragraaf 3.7 bevat een advies over veilige images en een teststrategie. Aan het eind staan twee extra's: de overstap van Poetry naar uv, en CodeRabbit.

## 3.1 SBOM

Voor deze opdracht heb ik Trivy gebruikt. Trivy is een open-source scanner van Aqua Security, die images en configuratiebestanden controleert op kwetsbaarheden en ook een SBOM kan maken. In een SBOM staat per onderdeel wat het is, welke versie, welk type (bijvoorbeeld `apk` of `pypi`), de licentie en een vaste naam (`purl`). Wordt er een nieuwe kwetsbaarheid bekend, dan is met de SBOM direct te zien welke images het betreffende onderdeel bevatten.

Ik heb een SBOM in het formaat CycloneDX gemaakt van het oude image, op basis van Debian en met Poetry erin, en van het huidige image:

```
oud (Debian, Poetry in het image):  272 onderdelen  (deb: 126, pypi: 146)
nu  (Alpine, alleen de runtime):     38 onderdelen  (apk: 30, pypi: 8)
```

Door een andere basisimage en de multi-stage build (zie 3.2) zitten er nog 38 onderdelen in plaats van 272. Van Python zijn alleen de acht packages over die de app echt nodig heeft, zoals Flask en gunicorn. De volledige SBOM staat in [sbom/devops-security.cdx.json](sbom/devops-security.cdx.json).

In de pipeline staat nu ook `sbom: true` bij de build-stap. Docker maakt dan bij elke build een SBOM en zet die als attestation bij het image op Docker Hub [(Docker, z.d.-c)](https://docs.docker.com/build/metadata/attestations/sbom/).

## 3.2 Docker Scout

Docker Scout is de scanner van Docker zelf, die op Docker Hub per image laat zien welke kwetsbaarheden erin zitten. Het image in de beginstaat was kwetsbaar: Docker Scout vond 96 kwetsbaarheden, waarvan 3 critical en 21 high. Het meeste zat in de basisimage `python:3-slim-bookworm`.

![Docker Scout voor de fix: 96 kwetsbaarheden](images/docker-scout-voor.png)

### De kwetsbaarheden oplossen

Ik heb de [Dockerfile](../Dockerfile) op drie punten aangepast:

- **Een kleinere basisimage:** `python:3.14-alpine` in plaats van Debian.
- **Niet als root:** het image draait als gebruiker 10001.
- **Een multi-stage build:** een builder waarin de dependencies worden geïnstalleerd, en een runtime met alleen de app en de virtuele omgeving van Python. Alleen de runtime gaat naar Docker Hub, waardoor de package manager en pip niet in het image zitten dat draait.

![De build in twee stappen: de builder installeert de dependencies, alleen de virtuele omgeving gaat mee naar de runtime, en alleen de runtime gaat naar Docker Hub](images/docker-build-stages.svg)

Elke `FROM` begint een nieuw, schoon image, en `COPY --from=builder` haalt alleen de virtuele omgeving uit de builder. De kern van de Dockerfile ziet er zo uit:

```dockerfile
FROM python:3.14-alpine@sha256:9e9f... AS builder
RUN uv sync --locked --no-install-project

FROM python:3.14-alpine@sha256:9e9f... AS runtime
COPY --from=builder --chown=10001:10001 /app/.venv /app/.venv
USER 10001:10001
```

Ik heb voor Alpine gekozen omdat daar veel minder in zit. Trivy vond op de Debian-basisimage 252 kwetsbaarheden en op Alpine 3. Die drie zitten in pip, dat ik in de runtime weghaal. Trivy telt overigens anders dan Docker Scout, omdat de scanners verschillende databases gebruiken. In de runtime vindt Trivy geen kwetsbaarheden meer.

Docker Scout vindt na de fix 0 kwetsbaarheden, in 47 packages. Voor de fix waren het er 127.

![Docker Scout na de fix: 0 kwetsbaarheden](images/docker-scout-na.png)

Het image is ook veel kleiner geworden. Gecomprimeerd ging het van 118,93 MB naar 17 MB, zoals Docker Hub het toont, en uitgepakt van ongeveer 437 MB naar 84,5 MB.

Bij een latere build vond Docker Scout toch weer een kwetsbaarheid: CVE-2026-107891 in `musl` van Alpine, nog zonder ernst omdat hij te nieuw was voor een CVSS-score. Daarom blijven deze scans in de pipeline draaien en worden ze niet één keer uitgevoerd. Een image dat vandaag schoon is, kan morgen een nieuwe kwetsbaarheid hebben, zonder dat er iets aan de Dockerfile is veranderd.

![Docker Scout vindt een nieuwe CVE in musl, nog zonder ernst](images/docker-scout-musl-cve.png)

### Extra: een veiligere app

Buiten de opdracht heb ik nog een paar dingen aan de app verbeterd:

- **Gunicorn in plaats van de ontwikkelserver:** de app draaide eerst met `flask run`. Dat is de ontwikkelserver van Flask, die niet bedoeld is voor productie [(Pallets, z.d.)](https://flask.palletsprojects.com/en/stable/deploying/).
- **Jinja-templates:** de pagina's staan nu in templates die invoer vanzelf escapen.
- **Security headers:** elk antwoord krijgt headers mee, zoals `Content-Security-Policy`, `X-Frame-Options` en `Referrer-Policy` [(OWASP Foundation, z.d.)](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html). De Content-Security-Policy staat alleen scripts, CSS en afbeeldingen van de app zelf toe.

Met [securityheaders.com](https://securityheaders.com) heb ik de headers gecontroleerd. Met alleen de eerste drie headers kreeg de app een D, met de rest erbij een A.

![securityheaders.com geeft de app een A](images/securityheaders-na.png)

De achtergrondfoto's kwamen van `cdn.glitch.com`, maar dat domein bestaat niet meer. Ik heb ze teruggezocht op Unsplash en host ze nu zelf, zodat de Content-Security-Policy geen ander domein hoeft toe te staan.

## 3.3 Docker Scout in de pipeline

In [build.yaml](../.github/workflows/build.yaml) staat een job `scan`, die het net gebouwde image met Docker Scout controleert op critical- en high-kwetsbaarheden. Vindt Docker Scout er een, dan faalt de job. De job `deploy` wacht op Test en Scan, waardoor een kwetsbaar image niet op het cluster komt.

Om te laten zien dat die controle werkt, heb ik tijdelijk een paar dependencies teruggezet naar kwetsbare versies, waaronder gunicorn 21.2.0. Die versie heeft twee high-kwetsbaarheden voor HTTP request smuggling, CVE-2024-1135 en CVE-2024-6827. De scan faalde, en Deploy liep niet.

![De scan-job faalt op twee high-kwetsbaarheden in gunicorn 21.2.0](images/scout-pipeline-rood.png)

Renovate maakte voor elke kwetsbaarheid een aparte pull request met het label `security`. Na het mergen was de scan weer groen en liep Deploy door.

![De scan-job slaagt weer: 0 kwetsbaarheden](images/scout-pipeline-groen.png)

## 3.4 Testsoorten in de testfase

In de pipeline draaien drie soorten controles, elk op een ander niveau:

- **Unit tests:** in de job `validate`. Die testen één functie los van de rest. Ze draaien bij elke commit, zijn snel, en er hoeft niets voor gebouwd of uitgerold te worden.
- **Een smoke test:** in de job `test`. Die start het net gebouwde image en wacht tot het antwoordt op HTTP. Dat test niet de logica, alleen of het image opstart. Een kapotte dependency of een verkeerd startcommando komt zo aan het licht, een fout in de logica niet.
- **Een image-scan:** in de job `scan`. Dat is eigenlijk geen functionele test, maar een controle in de testfase: het image wordt vergeleken met een database van kwetsbaarheden.

Wat nog ontbreekt, is een integratietest die een volledig scenario doorloopt, zoals inloggen, een quote plaatsen en die terugzien. In 3.5 en 3.6 begin ik daarmee met Postman. Daarnaast ontbreekt een DAST-scan tegen de draaiende app, bijvoorbeeld met ZAP [(ZAP, z.d.)](https://www.zaproxy.org/). Die zou ik na Deploy laten lopen, tegen de net uitgerolde omgeving, zodat ook fouten in de configuratie van Kubernetes naar boven komen.

## 3.5 en 3.6 Postman-tests in de pipeline

Postman is een programma om API's en webapplicaties te testen. Tests worden gebundeld in een collectie, die ook buiten Postman kan draaien. Mijn collectie staat in [tests/postman/quoter-xp.postman_collection.json](../tests/postman/quoter-xp.postman_collection.json) en bevat twee verzoeken:

- **De verplichte test uit 3.5:** de homepage geeft HTTP 200, en de tekst "Quoter XP" staat erop.
- **De eigen test uit 3.6:** de security headers staan erop, en de app draait op gunicorn en niet op de ontwikkelserver van Flask.

In de job `test` start ik de container van het net gebouwde image, en laat ik de collectie lopen met Newman, de command-line runner van Postman [(Postman, z.d.)](https://learning.postman.com/docs/collections/using-newman-cli/command-line-integration-with-newman/). Alle zes de controles slagen, zowel lokaal als in de pipeline:

![De Postman-tests in de pipeline: alle 6 controles geslaagd](images/postman-pipeline-groen.png)

## 3.7 Advies: veilige images en teststrategie

Voor SolidApps adviseer ik dezelfde opbouw als in deze pipeline, als vast proces bij elke build:

1. **Bouw klein en zonder root.** Gebruik een kleine, recente basisimage zoals Alpine, en een multi-stage build, zodat buildtools niet in het image komen dat draait.
2. **Maak bij elke build een SBOM**, zodat bij een nieuwe kwetsbaarheid direct duidelijk is welke images die bevatten.
3. **Scan het image vóór het uitrollen**, met een harde grens op critical en high. Een kwetsbaar image wordt niet uitgerold, ook niet tijdelijk.
4. **Test op meerdere niveaus:** unit tests en een smoke test bij elke build, Postman-tests tegen de draaiende container, en een DAST-scan tegen de net uitgerolde omgeving.
5. **Scan code en dependencies bij elke pull request**, met Snyk, CodeQL of Trivy, zodat een kwetsbaarheid opvalt voordat hij in `main` staat.

Omdat SolidApps met meerdere programmeertalen werkt, is het belangrijk dat deze stappen niet afhangen van de taal. Dan hoeven ze niet per project opnieuw te worden ingericht.

## Extra: van Poetry naar uv

In de les liepen we met de hele klas tegen problemen aan doordat Python 3.12 en 3.13 niet goed samenwerkten. School heeft toen alles teruggezet naar 3.10. Dat lost het onderliggende probleem niet op: bij een andere versie of een verkeerde combinatie van dependencies gebeurt het opnieuw.

Daarom heb ik Poetry vervangen door uv van Astral. uv legt alle dependencies vast in één lockfile, `uv.lock` [(Astral, z.d.)](https://docs.astral.sh/uv/). Met `uv sync --locked` faalt de build zodra die lockfile niet meer past bij `pyproject.toml`, zodat er nooit ongemerkt andere versies worden geïnstalleerd. uv zelf staat in de Dockerfile en de pipeline ook vast op een vaste versie, en Dependabot houdt `uv.lock` bij. Na de overstap heb ik de unit tests lokaal gedraaid; ze slaagden alle drie.

In de [screencast bij deze week](video/rollout-en-debug.webm) is te zien wat er gebeurt als de Python-versie verandert: ik zet die terug van 3.14 naar 3.8, en de app gaat meteen stuk.

## Extra: CodeRabbit

Naast Snyk, CodeQL en Trivy heb ik CodeRabbit aan de repository gekoppeld. CodeRabbit is een tool die met AI pull requests en code beoordeelt, als extra laag naast de securityscanners [(CodeRabbit, 2026)](https://www.coderabbit.ai/). Ik heb de gratis proefperiode van veertien dagen gebruikt en het abonnement daarna niet verlengd. De instellingen staan nog in [`.coderabbit.yaml`](../.coderabbit.yaml).

Het interessantste deed CodeRabbit uit zichzelf. Het zag dat het pad van een verzoek ongefilterd in het logbestand terechtkwam. Met een regeleinde in het pad kan zo een nep-logregel worden toegevoegd; dit heet log-injectie. CodeRabbit opende zelf een pull request met een fix en tests, zonder dat ik erom had gevraagd.

![CodeRabbit opent zelf een pull request met een fix en tests](images/coderabbit-autonome-fix-pr41.png)

Ik heb de pull request beoordeeld en gemerged. Het pad wordt nu gecodeerd voordat het in het log komt:

```diff
-    log_file.write(f"{request.method} {request.path}\n")
+    log_path = urllib.parse.quote(request.path, safe="/")
+    log_file.write(f"{request.method} {log_path}\n")
```

De tests hiervoor controleren dat speciale tekens geen nieuwe logregel kunnen maken, en draaien sindsdien mee in de job `validate`.

## Bronnen

Aqua Security. (z.d.). *Trivy*. https://trivy.dev

Astral. (z.d.). *uv*. https://docs.astral.sh/uv/

CodeRabbit. (2026). *CodeRabbit* \[AI-tool voor codereview\]. https://www.coderabbit.ai/

CycloneDX. (z.d.). *CycloneDX Bill of Materials Standard*. https://cyclonedx.org/

Docker. (z.d.-a). *Docker Scout*. Docker Docs. https://docs.docker.com/scout/

Docker. (z.d.-b). *Multi-stage builds*. Docker Docs. https://docs.docker.com/build/building/multi-stage/

Docker. (z.d.-c). *SBOM attestations*. Docker Docs. https://docs.docker.com/build/metadata/attestations/sbom/

OWASP Foundation. (z.d.). *HTTP headers cheat sheet*. OWASP Cheat Sheet Series. https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html

Pallets. (z.d.). *Deploying to production*. Flask Documentation. https://flask.palletsprojects.com/en/stable/deploying/

Postman. (z.d.). *Newman CLI overview*. Postman Docs. https://learning.postman.com/docs/collections/using-newman-cli/command-line-integration-with-newman/

The Linux Foundation. (z.d.). *SPDX*. https://spdx.dev/

ZAP. (z.d.). *ZAP*. https://www.zaproxy.org/
