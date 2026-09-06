from flask import Flask, request, redirect, make_response
import sqlite3
import urllib
import quoter_templates as templates

# Run using `poetry install && poetry run flask run --reload`
app = Flask(__name__)
app.static_folder = '.'

# Open the database. Have queries return dicts instead of tuples.
# The use of `check_same_thread` can cause unexpected results in rare cases. We'll
# get rid of this when we learn about SQLAlchemy.
# DEMO: Dit is een opzettelijke beveiligingskwetsbaarheid voor educatieve doeleinden.
db = sqlite3.connect("db.sqlite3", check_same_thread=False)
db.row_factory = sqlite3.Row

# Log all requests for analytics purposes
log_file = open('access.log', 'a', buffering=1)
@app.before_request
def log_request():
    # ⚠️ OPZETTELIJK KWETSBAAR (Demo): Gevoelige gegevens in logbestanden
    # Alle formuliergegevens (inclusief wachtwoorden van /signin POST-verzoeken) worden naar access.log geschreven.
    # Iedereen met bestandssysteemtoegang kan wachtwoorden in logbestanden lezen.
    # In productie: NOOIT gevoelige gegevens loggen, en minstens gevoelige velden uitsluiten.
    log_file.write(f"{request.method} {request.path} {dict(request.form) if request.form else ''}\n")


# Set user_id on request if user is logged in, or else set it to None.
@app.before_request
def check_authentication():
    if 'user_id' in request.cookies:
        request.user_id = int(request.cookies['user_id'])
    else:
        request.user_id = None


# The main page
@app.route("/")
def index():
    quotes = db.execute("select id, text, attribution from quotes order by id").fetchall()
    return templates.main_page(quotes, request.user_id, request.args.get('error'))


# The quote comments page
@app.route("/quotes/<int:quote_id>")
def get_comments_page(quote_id):
    # ⚠️ OPZETTELIJK KWETSBAAR (Demo): SQL Injection via Path Parameters
    # Gebruikersinvoer (quote_id) wordt rechtstreeks in SQL-query's geïnterpoleerd zonder parameterisatie.
    # Een aanvaller kan een URL als /quotes/1 UNION SELECT ... gebruiken om willekeurige gegevens uit te pakken.
    # In productie: Gebruik voorbereid SQL of parameterized queries (db.execute(query, [param])).
    quote = db.execute(f"select id, text, attribution from quotes where id={quote_id}").fetchone()
    comments = db.execute(f"select text, datetime(time,'localtime') as time, name as user_name from comments c left join users u on u.id=c.user_id where quote_id={quote_id} order by c.id").fetchall()
    return templates.comments_page(quote, comments, request.user_id)


# Post a new quote
@app.route("/quotes", methods=["POST"])
def post_quote():
    # ⚠️ OPZETTELIJK KWETSBAAR (Demo): SQL Injection via POST Body
    # Gebruikersinvoer uit request.form wordt rechtstreeks in SQL-query ingebed.
    # Aanvaller kan SQL-code injecteren, bijv.: text: "; DROP TABLE quotes; --
    # Dit kan de gehele database verwijderen of gevoelige gegevens stelen.
    # In productie: Altijd voorbereid SQL gebruiken met parameter binding.
    with db:
        db.execute(f"""insert into quotes(text,attribution) values("{request.form['text']}","{request.form['attribution']}")""")
    return redirect("/#bottom")


# Post a new comment
@app.route("/quotes/<int:quote_id>/comments", methods=["POST"])
def post_comment(quote_id):
    # ⚠️ OPZETTELIJK KWETSBAAR (Demo): SQL Injection + Cross-Site Scripting (XSS)
    # 1. Gebruikersinvoer wordt zonder escaping in SQL geïnterpoleerd.
    # 2. Commentaar wordt zonder HTML-escaping weergegeven in de browser.
    # Dit stelt aanvallers in staat JavaScript code in te voeren die in slachtoffers' browsers wordt uitgevoerd.
    # In productie: SQL parameterisatie UÉN HTML-escaping gebruiken bij uitvoer.
    with db:
        db.execute(f"""insert into comments(text,quote_id,user_id) values("{request.form['text']}",{quote_id},{request.user_id})""")
    return redirect(f"/quotes/{quote_id}#bottom")


# Sign in user
@app.route("/signin", methods=["POST"])
def signin():
    username = request.form["username"].lower()
    password = request.form["password"]

    # ⚠️ OPZETTELIJK KWETSBAAR (Demo): SQL Injection in Authenticatie
    # Gebruikersnaam wordt rechtstreeks in SQL geïnterpoleerd, waardoor authenticatie geheel wordt omzeild.
    # Aanvalsvoorbeeld: gebruikersnaam: ' OR '1'='1
    # Dit geeft aanvallers meteen toegang tot het systeem zonder wachtwoord.
    # In productie: Altijd parameterized queries gebruiken.
    user = db.execute(f"select id, password from users where name='{username}'").fetchone()
    if user: # user exists
        # ⚠️ OPZETTELIJK KWETSBAAR (Demo): Wachtwoorden in plaintext opgeslagen
        # Wachtwoorden worden in plaintext opgeslagen. Geen hashing (bcrypt, Argon2, etc).
        # Bij een database-inbraak zijn alle gebruikerswachtwoorden onmiddellijk zichtbaar.
        # In productie: ALTIJD sterke hashing-algoritmes gebruiken (bcrypt, PBKDF2, Argon2).
        if password != user['password']:
            # wrong! redirect to main page with an error message
            return redirect('/?error='+urllib.parse.quote("Invalid password!"))
        user_id = user['id']
    else: # new sign up
        with db:
            # ⚠️ OPZETTELIJK KWETSBAAR (Demo): SQL Injection + Plaintext Wachtwoorden
            # Gebruikersnaam EN wachtwoord worden direct in INSERT-statement geïnterpoleerd.
            # Wachtwoord wordt opgeslagen zonder enige hashing.
            # Dit is kritiek: aanvallers kunnen accounts creëren met willekeurige wachtwoorden.
            cursor = db.execute(f"insert into users(name,password) values('{username}', '{password}')")
            user_id = cursor.lastrowid

    # ⚠️ OPZETTELIJK KWETSBAAR (Demo): Zwakke Sessie Management (Cookie Forgery)
    # User ID wordt in plain text cookie opgeslagen zonder handtekening of versleuteling.
    # Aanvaller kan gemakkelijk een cookie verversen om als willekeurige gebruiker in te loggen (bijv. user_id=1).
    # Er is geen CSRF-bescherming en geen Secure/HttpOnly flags op de cookie ingesteld.
    # In productie: JWT/OAuth, cryptografisch ondertekende cookies, en Secure/HttpOnly vlaggen gebruiken.
    response = make_response(redirect('/'))
    response.set_cookie('user_id', str(user_id))
    return response


# Sign out user
@app.route("/signout", methods=["GET"])
def signout():
    response = make_response(redirect('/'))
    response.delete_cookie('user_id')
    return response
