# Week 2

Voor week 2 is het de bedoeling dat ik Snyk installeer, de repository van vorige week scan en minstens twee kwetsbaarheden fix door de code aan te passen. Daarnaast schrijf ik een advies voor de developers van SolidApps.

## 2.1 Snyk installeren en de repository scannen

Eerst heb ik Snyk gekoppeld aan mijn GitHub-account. Ik log in met GitHub, geef toestemming en rond de registratie af. De dataregio laat ik op de standaard staan, SNYK-US-01. De EU-regio werkte niet voor de GitHub-koppeling, want GitHub zit op US.

![Inloggen bij Snyk](images/snyk-login.png)
![Toestemming voor GitHub](images/snyk-github-toestemming.png)
![Registratie afronden](images/snyk-registratie.png)

Daarna kies ik GitHub als integratie, importeer ik de repository `DevOps-Security` en zet ik Snyk Code aan. Dat staat standaard uit, en je moet het project daarna opnieuw importeren om het te scannen.

![GitHub als integratie kiezen](images/snyk-github-integratie.png)
![Repository importeren](images/snyk-repository-importeren.png)
![Snyk Code aanvinken](images/snyk-code-aanzetten.png)

Na een tijdje zie je Snyk alles flaggen. Snyk Code vindt 7 problemen in `content/app.py`: 4 keer SQL-injectie ([CWE-89](https://cwe.mitre.org/data/definitions/89.html)) en 1 keer cross-site scripting ([CWE-79](https://cwe.mitre.org/data/definitions/79.html)), allemaal High, en 2 keer Low voor de cookie zonder `HttpOnly` en zonder `Secure`. Snyk IaC vindt 8 punten in `kubernetes/deployment.yaml` (3 Medium, 5 Low), zoals een container zonder root-user control en zonder memory limit. In Open Source vindt Snyk niks.

![Overzicht van de projecten in Snyk](images/snyk-projecten-overzicht.png)
![Voorbeelden van SQL-injecties](images/snyk-sql-injecties.png)

Vervolgens heb ik ook de Snyk-extensie in VS Code geïnstalleerd, zodat ik live kan scannen. De extensie ziet dezelfde kwetsbaarheden terug, met regelnummer en uitleg per issue.

![Snyk-extensie in VS Code](images/vscode-snyk-extensie.png)
![De extensie toont de kwetsbaarheden](images/vscode-snyk-resultaten.png)

## Extra: GitHub Advanced Security met CodeQL

Als extra heb ik GitHub Advanced Security met CodeQL ingericht. Dat staat in de repository onder Settings, Advanced Security. Zie de screenshots voor de instellingen.

![CodeQL default configuration](images/codeql-configuratie.png)
![Advanced Security instellingen](images/advanced-security-instellingen.png)

Daarna staat er een 10 bij het tabblad Security and quality. Onder Code scanning staan de kwetsbaarheden die GitHub met zijn eigen tooling al gevonden heeft.

![Security overzicht](images/security-overzicht.png)
![Code scanning alerts](images/code-scanning-alerts.png)

Als ik op een kwetsbaarheid klik, zie ik precies wat er mis is en waar het staat. GitHub geeft ook een link naar de CWE in de MITRE-database, hier [CWE-89](https://cwe.mitre.org/data/definitions/89.html) (SQL-injectie).

![Alert met details](images/code-scanning-alert-detail.png)
![CWE-89 bij MITRE](images/cwe-89.png)

## 2.2 Kwetsbaarheden fixen

Voor de fixes stonden er 10 open meldingen in Code scanning (CodeQL): 6 keer SQL-injectie, 1 keer XSS, 1 keer een URL-redirect en 2 keer iets met de cookie.

![Security vulnerabilities voor de fixes](images/codeql-voor-de-fixes.png)

Ik heb ze in vijf stappen aangepakt, en daarna ook de punten van Snyk IaC (fix 6) en een paar dingen die scanners niet melden (fix 7 t/m 10). Bij fix 1, 2, 4 en 5 heb ik een eigen commit gemaakt, zodat je de diff los kunt bekijken. De diffs hieronder heb ik ingekort tot alleen de code die veranderd is, met bestand en regelnummer erbij. De weggehaalde commentaarregels laat ik weg. De hele diff staat in de commit.

### Fix 1: SQL-injectie

In de code werd wat een gebruiker invult gewoon in de SQL-query geplakt, met een f-string. Daardoor kan een aanvaller zelf SQL meegeven. Met `nope' UNION SELECT 1,'hax` als gebruikersnaam was ik ingelogd als gebruiker 1, zonder wachtwoord. En via het quote-formulier kon ik alle wachtwoorden uit de database in een quote laten verschijnen.

Ik heb dit opgelost met parameters in de query (`?`). De SQL blijft vast en de invoer wordt apart meegegeven, dus de database ziet het nooit als SQL. Snyk vond 4 plekken en CodeQL 6, en ik heb alle 6 aangepast. Ook de twee in `get_comments_page`: `quote_id` is daar al een getal, maar een f-string in een query hoort er sowieso niet.

![SQL-injectie in Snyk (fix 1)](images/fix1-sql-injectie-snyk.png)

Zie de diff van commit [`4965429`](https://github.com/Stensel8/DevOps-Security/commit/4965429):

```diff
@@ content/app.py:46-47 @@
-    quote = db.execute(f"select id, text, attribution from quotes where id={quote_id}").fetchone()
-    comments = db.execute(f"select text, datetime(time,'localtime') as time, name as user_name from comments c left join users u on u.id=c.user_id where quote_id={quote_id} order by c.id").fetchall()
+    quote = db.execute("select id, text, attribution from quotes where id=?", (quote_id,)).fetchone()
+    comments = db.execute("select text, datetime(time,'localtime') as time, name as user_name from comments c left join users u on u.id=c.user_id where quote_id=? order by c.id", (quote_id,)).fetchall()
@@ content/app.py:55 @@
-        db.execute(f"""insert into quotes(text,attribution) values("{request.form['text']}","{request.form['attribution']}")""")
+        db.execute("insert into quotes(text,attribution) values(?,?)", (request.form['text'], request.form['attribution']))
@@ content/app.py:64 @@
-        db.execute(f"""insert into comments(text,quote_id,user_id) values("{request.form['text']}",{quote_id},{request.user_id})""")
+        db.execute("insert into comments(text,quote_id,user_id) values(?,?,?)", (request.form['text'], quote_id, request.user_id))
@@ content/app.py:74 @@
-    user = db.execute(f"select id, password from users where name='{username}'").fetchone()
+    user = db.execute("select id, password from users where name=?", (username,)).fetchone()
@@ content/app.py:85 @@
-            cursor = db.execute(f"insert into users(name,password) values('{username}', '{password}')")
+            cursor = db.execute("insert into users(name,password) values(?,?)", (username, password))
```

Daarna heb ik het getest in het gebouwde image. Dezelfde gebruikersnaam maakt nu gewoon een nieuw account aan met een rare naam, en een quote met `"; DROP TABLE quotes; --` staat gewoon als tekst op de pagina. De tabel is nog heel.

### Fix 2: XSS (cross-site scripting)

De app zette wat een gebruiker invult zonder escaping in de HTML. Daardoor kan iemand JavaScript in een quote, commentaar of gebruikersnaam zetten, en dat wordt dan bij iedere bezoeker uitgevoerd. Bijvoorbeeld `<img src=x onerror=alert(1)>`.

Snyk vindt alleen de variant met de `error`-parameter en stelt voor om alleen die parameter in `app.py` te escapen (zie screenshot). Ik heb het liever op één plek in de template gedaan, met `markupsafe.escape`. Dat zat al in de dependencies. Zo zijn ook de opgeslagen quotes, commentaren, gebruikersnamen en de paginatitel veilig.

![XSS in Snyk met het voorstel van Snyk (fix 2)](images/fix2-xss-snyk.png)

Zie de diff van commit [`251f107`](https://github.com/Stensel8/DevOps-Security/commit/251f107):

```diff
@@ content/quoter_templates.py:1 @@
+from markupsafe import escape
@@ content/quoter_templates.py:7-8 @@
-  <q>{text}</q>
-  <address>{attribution}</address>
+  <q>{escape(text)}</q>
+  <address>{escape(attribution)}</address>
@@ content/quoter_templates.py:19 @@
-    <address>{user_name}</address>
+    <address>{escape(user_name)}</address>
@@ content/quoter_templates.py:22 @@
-  <p>{text}</p>
+  <p>{escape(text)}</p>
@@ content/quoter_templates.py:72 @@
-  <title>{title or "Quoter XP"}</title>
+  <title>{escape(title or "Quoter XP")}</title>
@@ content/quoter_templates.py:103 @@
-    {f"<div class=error>{error}</div>" if error else ""}
+    {f"<div class=error>{escape(error)}</div>" if error else ""}
```

Getest: `<img src=x onerror=alert(1)>` staat nu als gewone tekst op de pagina. Ook via `?error=`, een quote, de naam eronder en een gebruikersnaam.

### Fix 3: dependencies en SHA-pinning

Als derde fix heb ik alle dependencies geüpgraded en gebumpt, met behulp van Renovate en Dependabot. Daarom vindt Snyk Open Source niks.

Voor dependencies pin ik zoveel mogelijk vast op een versie of een commit SHA. Dat is een vorm van supply chain beveiliging. Een tag zoals `v4` kan later naar andere code wijzen, bijvoorbeeld als een action of image wordt aangepast of gehackt. Een SHA kan dat niet. Zo draait er alleen code die ik heb gezien. Renovate en Dependabot maken een pull request voor elke nieuwe versie, dus ik bepaal zelf wanneer ik update. De base image staat op een digest, alle GitHub Actions staan op een volledige commit SHA (met de versie als commentaar), `poetry.lock` heeft hashes van de packages en de K3s-versie staat vast in het script.

```dockerfile
FROM python:3.14-slim-bookworm@sha256:82bc3c539b8813ada9d68c63b40158fa002f7f33de9bf3312a3dfdc0620dff56
```

```yaml
uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
```

![SHA-pinning in build.yaml (fix 3)](images/fix3-sha-pinning-build-yaml.png)

Poetry heb ik ook vastgepind (`poetry==2.5.1`, in de Dockerfile en in de workflow) en Renovate houdt die versie bij. Nog niet vastgepind is het image `stensel8/devops-security:latest` in de Deployment.

### Fix 4: cookie met HttpOnly en SameSite

De `user_id`-cookie had geen `HttpOnly`. Dan kan JavaScript op de pagina hem lezen, bijvoorbeeld via een XSS. Met `httponly=True` kan alleen de browser hem nog gebruiken, en met `samesite='Lax'` wordt hij niet meegestuurd bij verzoeken vanaf andere websites. CodeQL en Snyk melden dit allebei. Later heb ik de losse cookie vervangen door een sessie (fix 10), maar dit was de eerste oplossing.

Zie de diff van commit [`3dfae64`](https://github.com/Stensel8/DevOps-Security/commit/3dfae64):

```diff
@@ content/app.py:91 @@
-    response.set_cookie('user_id', str(user_id))
+    response.set_cookie('user_id', str(user_id), httponly=True, samesite='Lax')
```

### Fix 5: redirect met url_for

CodeQL meldt een URL-redirect, omdat `quote_id` uit de URL komt en in de redirect wordt gebruikt. Door `<int:quote_id>` kon je er eigenlijk weinig mee, maar ik bouw de URL nu met `url_for`. Die maakt de URL uit de route van de app zelf, in plaats van dat ik zelf een tekst aan elkaar plak.

Zie de diff van commit [`2a2e85f`](https://github.com/Stensel8/DevOps-Security/commit/2a2e85f):

```diff
@@ content/app.py:1 @@
-from flask import Flask, request, redirect, make_response
+from flask import Flask, request, redirect, make_response, url_for
@@ content/app.py:64 @@
-    return redirect(f"/quotes/{quote_id}#bottom")
+    return redirect(url_for("get_comments_page", quote_id=quote_id, _anchor="bottom"))
```

Voordat ik pushte heb ik CodeQL ook lokaal gedraaid. Op de oude code kwamen dezelfde 10 meldingen eruit als op GitHub, en na de fixes bleef er 1 over.

Na de push heeft CodeQL op GitHub opnieuw gescand en zijn 9 van de 10 meldingen gesloten. Er staat er nog 1 open, de `Secure`-vlag op de cookie. Omdat die regel een ander regelnummer kreeg, zag CodeQL het als een nieuwe melding (#18). Die heb ik gesloten als "won't fix", net als de eerste. Hieronder staat waarom.

![Code scanning na de fixes](images/codeql-na-de-fixes.png)

### Fix 6: Snyk IaC in de Deployment

Snyk IaC vond 8 punten in `kubernetes/deployment.yaml`. Voor de container ontbraken `allowPrivilegeEscalation: false`, `runAsNonRoot`, alle capabilities droppen, een `runAsUser` boven de 10000 (anders kan de UID botsen met een gebruiker op de host), een read-only root-bestandssysteem, een CPU-limiet, een geheugenlimiet en een liveness probe. Die heb ik allemaal toegevoegd. Het image draait al als gebruiker 10001, dus `runAsNonRoot` kan nu. Een seccomp-profiel (`RuntimeDefault`) heb ik er ook bij gezet. Dat stond niet in de lijst van Snyk.

Een read-only root-bestandssysteem past niet zomaar bij deze app, want die schrijft de SQLite-database en het logbestand naast de code. Daarom staan die twee nu in een aparte map (`DATA_DIR`). In Kubernetes is dat een `emptyDir` op `/data`, en de app kopieert de database uit het image naar die map als hij er nog niet staat. De rest van het bestandssysteem is read-only.

Zie de diffs van commit [`b3d10f5`](https://github.com/Stensel8/DevOps-Security/commit/b3d10f5) en [`fd73ded`](https://github.com/Stensel8/DevOps-Security/commit/fd73ded):

```diff
@@ content/app.py:2-3 @@
+import os
+import shutil
@@ content/app.py:18-23 @@
-db = sqlite3.connect("db.sqlite3", check_same_thread=False)
+DATA_DIR = os.environ.get("DATA_DIR", ".")
+DB_PATH = os.path.join(DATA_DIR, "db.sqlite3")
+if not os.path.exists(DB_PATH):
+    shutil.copy("db.sqlite3", DB_PATH)
+db = sqlite3.connect(DB_PATH, check_same_thread=False)
@@ content/app.py:27 @@
-log_file = open('access.log', 'a', buffering=1)
+log_file = open(os.path.join(DATA_DIR, 'access.log'), 'a', buffering=1)
```

```diff
@@ kubernetes/deployment.yaml:19-21 @@
+      securityContext:
+        seccompProfile:
+          type: RuntimeDefault
@@ kubernetes/deployment.yaml:28-57 @@
+        env:
+          - name: DATA_DIR
+            value: /data
+        securityContext:
+          runAsNonRoot: true
+          runAsUser: 10001
+          runAsGroup: 10001
+          allowPrivilegeEscalation: false
+          readOnlyRootFilesystem: true
+          capabilities:
+            drop: ["ALL"]
+        resources:
+          requests:
+            cpu: 50m
+            memory: 64Mi
+          limits:
+            cpu: 500m
+            memory: 256Mi
+        livenessProbe:
+          httpGet:
+            path: /
+            port: 5000
+          initialDelaySeconds: 5
+          periodSeconds: 10
+        volumeMounts:
+          - name: data
+            mountPath: /data
+      volumes:
+        - name: data
+          emptyDir: {}
```

Ik heb dit getest in een K3s van dezelfde versie als mijn cluster (draaiend in Docker). De pod komt op `Running`, blijft `Ready` zonder herstarts en de liveness probe slaagt. In de pod zie ik dat alle capabilities weg zijn, dat schrijven naar `/app` niet kan (`Read-only file system`) en dat inloggen en quotes plaatsen nog werkt. Trivy vond op het manifest 19 punten voor de aanpassing en nog 3 erna: het `:latest`-tag, de default namespace en de vertrouwde registry.

Toen ik de Snyk-extensie opnieuw draaide, vond die nog 5 punten. Vier daarvan kwamen door mijn eigen wijziging. Snyk ziet een omgevingsvariabele (`DATA_DIR`) als onbetrouwbare invoer. Die komt terecht in het pad van de database en het logbestand, en dat gaf 2 keer XSS (Medium) en 2 keer Path Traversal (Low). Het vijfde punt is de `Secure`-vlag op de cookie, die ik niet zet.

![Snyk na fix 6](images/snyk-na-fix-6.png)

Ik heb de omgevingsvariabele weggehaald. De app gebruikt nu `/data` als die map bestaat en anders de map naast de code, en de `env` in de Deployment is weg. Zie de diff van commit [`19d558f`](https://github.com/Stensel8/DevOps-Security/commit/19d558f):

```diff
@@ content/app.py:19 @@
-DATA_DIR = os.environ.get("DATA_DIR", ".")
+DATA_DIR = "/data" if os.path.isdir("/data") else "."
@@ kubernetes/deployment.yaml:27 (weggehaald) @@
-        env:
-          - name: DATA_DIR
-            value: /data
```

Dit heb ik opnieuw getest in Docker met dezelfde beperkingen (read-only, geen capabilities) en ook met een gewone `docker run` zonder `/data`. In beide gevallen werkt de app.

### Fix 7: wachtwoorden niet meer in het logbestand

De app schreef bij elk verzoek alles wat er in een formulier stond in het logbestand, dus ook de wachtwoorden bij het inloggen. Wie het logbestand kon lezen, zag dus de wachtwoorden. Nu logt de app alleen nog de methode en het pad. Zie de diff van commit [`9355c96`](https://github.com/Stensel8/DevOps-Security/commit/9355c96):

```diff
@@ content/app.py:34 @@
-    log_file.write(f"{request.method} {request.path} {dict(request.form) if request.form else ''}\n")
+    log_file.write(f"{request.method} {request.path}\n")
```

Getest: na twee keer inloggen met een wachtwoord staat er alleen `POST /signin` in het logbestand.

### Fix 8: alleen static/ publiek maken

Met `app.static_folder = '.'` was de hele app-map publiek via `/static/`. Daardoor kon iedereen de database (met alle gebruikers) en `app.py` downloaden, bijvoorbeeld via `/static/db.sqlite3`. Geen scanner meldde dit, maar ik zag het bij het testen. Nu staat `style.css` in de map `static/`, en dat is het enige wat geserveerd wordt. Zie de diff van commit [`e217cf4`](https://github.com/Stensel8/DevOps-Security/commit/e217cf4) (`style.css` is verplaatst naar `content/static/`):

```diff
@@ content/app.py:9 (weggehaald) @@
-app.static_folder = '.'
```

Getest: `/static/style.css` geeft 200 en `/static/db.sqlite3`, `/static/app.py` en `/static/poetry.lock` geven 404, ook als ik `../` in het pad probeer.

### Fix 9: wachtwoorden hashen

Wachtwoorden stonden in platte tekst in de database. Wie bij de database kwam, zag ze allemaal. Nu sla ik ze op als hash (scrypt, met `werkzeug.security`, dat zit al in Flask). Bij het inloggen kijkt `check_password_hash` of het wachtwoord klopt. De twee gebruikers die al in de database stonden (`test` en `frank`, uit het sjabloon van de docent) heb ik ook omgezet naar een hash, dus `db.sqlite3` staat ook in de commit. Zie de diff van commit [`6a929c6`](https://github.com/Stensel8/DevOps-Security/commit/6a929c6):

```diff
@@ content/app.py:2 @@
+from werkzeug.security import check_password_hash, generate_password_hash
@@ content/app.py:84 @@
-        if password != user['password']:
+        if not check_password_hash(user['password'], password):
@@ content/app.py:90 @@
-            cursor = db.execute("insert into users(name,password) values(?,?)", (username, password))
+            cursor = db.execute("insert into users(name,password) values(?,?)", (username, generate_password_hash(password)))
@@ content/quoter_templates.py:102 @@
-    <p class="warn">WARNING!!: This is a demo site and passwords are stored in plain text. Do not use passwords you may be using on other services.</p>
+    <p class="warn">WARNING!!: This is a demo site. Do not use passwords you may be using on other services.</p>
```

Getest: inloggen als `test` met `1234` werkt nog, een fout wachtwoord niet, een nieuwe gebruiker krijgt meteen een hash en er staat geen platte tekst meer in de database.

### Fix 10: ondertekende sessie in plaats van een losse cookie

De app zette een cookie met alleen `user_id=1`. Die kon je zelf aanpassen, dus je kon zonder wachtwoord inloggen als een andere gebruiker. Nu gebruik ik de sessie van Flask. Die cookie is ondertekend met een willekeurige sleutel, dus een aangepaste of verzonnen cookie wordt niet geaccepteerd. De sleutel verandert bij elke start van de app, dus na een herstart moet je opnieuw inloggen. Dat is hier prima, want er draait maar één pod. De sessie-cookie heeft `HttpOnly` standaard en `SameSite=Lax` heb ik ingesteld, dus dit neemt fix 4 over. Zie de diff van commit [`f2aef79`](https://github.com/Stensel8/DevOps-Security/commit/f2aef79):

```diff
@@ content/app.py:1 @@
-from flask import Flask, request, redirect, make_response, url_for
+from flask import Flask, request, redirect, session, url_for
@@ content/app.py:4 @@
+import secrets
@@ content/app.py:12-13 @@
+app.secret_key = secrets.token_hex(32)
+app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
@@ content/app.py:42 @@
-    if 'user_id' in request.cookies:
-        request.user_id = int(request.cookies['user_id'])
-    else:
-        request.user_id = None
+    request.user_id = session.get("user_id")
@@ content/app.py:93-94 @@
-    response = make_response(redirect('/'))
-    response.set_cookie('user_id', str(user_id), httponly=True, samesite='Lax')
-    return response
+    session["user_id"] = user_id
+    return redirect('/')
@@ content/app.py:100-101 @@
-    response = make_response(redirect('/'))
-    response.delete_cookie('user_id')
-    return response
+    session.clear()
+    return redirect('/')
```

Getest: inloggen en uitloggen werken. Een zelf gemaakte `user_id=1`-cookie, een aangepaste sessie-cookie en een sessie-cookie die met een andere sleutel is ondertekend worden alle drie niet geaccepteerd.

### Wat nog open staat

De `Secure`-vlag op de cookie heb ik niet gezet. Die werkt alleen met HTTPS, en de app draait op gewone HTTP. Een browser slaat een `Secure`-cookie niet op via HTTP, dus dan kan ik niet meer inloggen. In GitHub heb ik de melding gesloten als "won't fix", met die reden erbij. Sinds fix 10 gebruik ik een sessie-cookie en staat er geen `set_cookie` meer in de code, dus CodeQL meldt het niet meer. De cookie heeft de `Secure`-vlag nog steeds niet. Zodra er HTTPS is, bijvoorbeeld met de Ingress met certificaat uit week 5, kan ik `SESSION_COOKIE_SECURE` aanzetten.

Alle andere kwetsbaarheden die scanners of ik hebben gevonden zijn opgelost. In de code staat bij elk daarvan "Opgelost in week 2, tijdens commit ...". De app is daarmee niet helemaal veilig. Er is bijvoorbeeld geen CSRF-bescherming en geen limiet op het aantal inlogpogingen.

## 2.3 Advies: veilig ontwikkelen in Plan en Code

SolidApps werkt met JavaScript en C# in Visual Studio. Dit zou ik de developers adviseren voor de fasen Plan en Code.

Ik zou beginnen met threat modeling. Bij elke nieuwe functie kijken ze met STRIDE wat er mis kan gaan, op een tekening van hoe de data door de applicatie loopt (een data flow diagram). Met DREAD of de OWASP-methode bepalen ze welke bedreigingen ze het eerst aanpakken. Bij onze app zie je zo meteen dat "inloggen" en "quote plaatsen" invoer van buiten krijgen (tampering, SQL-injectie) en dat er gebruikersgegevens worden opgeslagen (information disclosure).

Als standaard voor de code kunnen ze de OWASP Top 10 gebruiken, met OWASP ASVS als checklist en de OWASP cheat sheets per soort kwetsbaarheid. Voor SQL-injectie zijn dat parameters in queries en voor XSS output encoding, dus precies mijn twee fixes. Ze leggen vast dat je nooit strings in een query plakt, uitvoer altijd escapet en geen secrets in de code zet.

Voor tooling is een Snyk-extensie in de IDE handig (die bestaat ook voor Visual Studio), want die laat fouten zien terwijl je typt. Secret scanning met push protection staat in mijn repository aan. Code gaat via een pull request met een review van een collega, en Snyk en CodeQL draaien als check op elke pull request, zodat een kwetsbaarheid niet ongemerkt in `main` komt. Dependabot en Renovate houden de dependencies bij.

Dan SAST en DAST. SAST (static application security testing) kijkt naar de broncode zonder dat de app draait. Zo vindt het bijvoorbeeld een f-string in `db.execute`. Je kunt het vroeg gebruiken, in de IDE en bij elke pull request, maar het geeft ook meldingen die niet kloppen (false positives). Snyk Code en CodeQL zijn SAST. DAST (dynamic application security testing) test de draaiende applicatie van buitenaf, zoals een aanvaller dat doet, bijvoorbeeld met OWASP ZAP. Daarmee vind je dingen in de configuratie en tijdens het draaien die je in de code niet ziet. Het nadeel is dat het pas laat kan en niet zegt op welke regel de fout zit. SolidApps zou SAST gebruiken tijdens Plan en Code (in de IDE en bij pull requests) en DAST in de testfase van de pipeline, tegen de omgeving die net is uitgerold.

Bronnen: [DevSecOps-controls (Microsoft)](https://learn.microsoft.com/nl-nl/azure/cloud-adoption-framework/secure/devsecops-controls), [SAST (Snyk)](https://snyk.io/learn/application-security/static-application-security-testing/), [Threat modeling (OWASP)](https://owasp.org/www-community/Threat_Modeling), [Bedreigingen per STRIDE-categorie (Microsoft)](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats), [OWASP Top 10](https://owasp.org/www-project-top-ten/), [OWASP ASVS](https://owasp.org/www-project-asvs/), [SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html), [XSS Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html), [Source Code Analysis Tools (OWASP)](https://owasp.org/www-community/Source_Code_Analysis_Tools), [OWASP ZAP](https://www.zaproxy.org/), [Voorbeeld SQL-injectie](https://github.com/doublehops/sql-injection-attack-example).

Voor SHA-pinning: [Security hardening for GitHub Actions](https://docs.github.com/en/actions/how-tos/security-for-github-actions/security-guides/security-hardening-for-github-actions), [Docker best practices: pin base image versions](https://docs.docker.com/build/building/best-practices/) en [Renovate: Docker digest pinning](https://docs.renovatebot.com/docker/).
