from flask import Flask, request, redirect, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash
import os
import secrets
import shutil
import sqlite3
import urllib
import quoter_templates as templates

# Run using `poetry install && poetry run flask run --reload`
# Alleen static/ wordt publiek geserveerd. Vroeger was dat de hele map, waardoor je de database en
# app.py kon downloaden. Opgelost in week 2, tijdens commit e217cf4.
app = Flask(__name__)

# De sessie-cookie wordt ondertekend met een willekeurige sleutel, dus een aangepaste of verzonnen cookie
# wordt niet geaccepteerd. De sleutel verandert bij elke start, dus na een herstart moet iedereen opnieuw
# inloggen. Vroeger was het een losse user_id-cookie die je zelf kon aanpassen. Opgelost in week 2,
# tijdens commit f2aef79. De Secure-vlag ontbreekt nog, want die werkt alleen met HTTPS.
app.secret_key = secrets.token_hex(32)
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

# De database en het logbestand staan in /data als die map er is. In Kubernetes is dat een schrijfbaar
# volume, want de rest van het bestandssysteem is read-only. De eerste keer wordt de database uit het
# image daarheen gekopieerd. Zonder /data staan ze naast de code. Zie commit b3d10f5 en 19d558f.
DATA_DIR = "/data" if os.path.isdir("/data") else "."
DB_PATH = os.path.join(DATA_DIR, "db.sqlite3")
if not os.path.exists(DB_PATH):
    shutil.copy("db.sqlite3", DB_PATH)

# Alle queries hieronder gebruiken ?-parameters, dus invoer wordt nooit als SQL gelezen. Vroeger werd de
# invoer in de SQL geplakt (SQL-injectie). Opgelost in week 2, tijdens commit 4965429.
db = sqlite3.connect(DB_PATH, check_same_thread=False)
db.row_factory = sqlite3.Row

# Elk verzoek komt in het logbestand, alleen met methode en pad.
log_file = open(os.path.join(DATA_DIR, 'access.log'), 'a', buffering=1)
@app.before_request
def log_request():
    # Vroeger stonden hier ook de formuliervelden in, dus de wachtwoorden. Opgelost in week 2, tijdens commit 9355c96.
    log_file.write(f"{request.method} {request.path}\n")


# Zet request.user_id als je bent ingelogd (uit de ondertekende sessie), anders None.
@app.before_request
def check_authentication():
    request.user_id = session.get("user_id")


# Hoofdpagina met alle quotes. De tekst wordt in de template ge-escaped (XSS), zie commit 251f107.
@app.route("/")
def index():
    quotes = db.execute("select id, text, attribution from quotes order by id").fetchall()
    return templates.main_page(quotes, request.user_id, request.args.get('error'))


# Pagina met een quote en de commentaren erbij.
@app.route("/quotes/<int:quote_id>")
def get_comments_page(quote_id):
    quote = db.execute("select id, text, attribution from quotes where id=?", (quote_id,)).fetchone()
    comments = db.execute("select text, datetime(time,'localtime') as time, name as user_name from comments c left join users u on u.id=c.user_id where quote_id=? order by c.id", (quote_id,)).fetchall()
    return templates.comments_page(quote, comments, request.user_id)


# Een nieuwe quote plaatsen.
@app.route("/quotes", methods=["POST"])
def post_quote():
    with db:
        db.execute("insert into quotes(text,attribution) values(?,?)", (request.form['text'], request.form['attribution']))
    return redirect("/#bottom")


# Een nieuw commentaar plaatsen. De redirect wordt met url_for gebouwd, zie commit 2a2e85f.
@app.route("/quotes/<int:quote_id>/comments", methods=["POST"])
def post_comment(quote_id):
    with db:
        db.execute("insert into comments(text,quote_id,user_id) values(?,?,?)", (request.form['text'], quote_id, request.user_id))
    return redirect(url_for("get_comments_page", quote_id=quote_id, _anchor="bottom"))


# Inloggen of registreren. Bestaat de gebruikersnaam al, dan wordt het wachtwoord gecontroleerd. Anders
# wordt er een nieuw account gemaakt. Wachtwoorden worden gehasht opgeslagen (scrypt). Vroeger stonden ze
# in platte tekst in de database. Opgelost in week 2, tijdens commit 6a929c6.
@app.route("/signin", methods=["POST"])
def signin():
    username = request.form["username"].lower()
    password = request.form["password"]

    user = db.execute("select id, password from users where name=?", (username,)).fetchone()
    if user: # user exists
        if not check_password_hash(user['password'], password):
            # wrong! redirect to main page with an error message
            return redirect('/?error='+urllib.parse.quote("Invalid password!"))
        user_id = user['id']
    else: # new sign up
        with db:
            cursor = db.execute("insert into users(name,password) values(?,?)", (username, generate_password_hash(password)))
            user_id = cursor.lastrowid

    session["user_id"] = user_id
    return redirect('/')


# Uitloggen: de sessie wordt leeggemaakt.
@app.route("/signout", methods=["GET"])
def signout():
    session.clear()
    return redirect('/')
