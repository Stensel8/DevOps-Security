from flask import Flask, request, redirect, make_response, url_for
import os
import shutil
import sqlite3
import urllib
import quoter_templates as templates

# Run using `poetry install && poetry run flask run --reload`
app = Flask(__name__)

# Open the database. Have queries return dicts instead of tuples.
# The use of `check_same_thread` can cause unexpected results in rare cases. We'll
# get rid of this when we learn about SQLAlchemy.
# De SQL-injectie die hier zat is opgelost in week 2, tijdens commit 4965429.

# De database en het logbestand staan in /data als die map er is. In Kubernetes is dat een aparte
# schrijfbare map, want de rest van het bestandssysteem is read-only. De eerste keer krijgt die map
# de database uit het image. Zonder /data staan ze naast de code.
DATA_DIR = "/data" if os.path.isdir("/data") else "."
DB_PATH = os.path.join(DATA_DIR, "db.sqlite3")
if not os.path.exists(DB_PATH):
    shutil.copy("db.sqlite3", DB_PATH)

db = sqlite3.connect(DB_PATH, check_same_thread=False)
db.row_factory = sqlite3.Row

# Log all requests for analytics purposes
log_file = open(os.path.join(DATA_DIR, 'access.log'), 'a', buffering=1)
@app.before_request
def log_request():
    # Opgelost in week 2, tijdens commit 9355c96: hier stonden ook de wachtwoorden in het logbestand.
    log_file.write(f"{request.method} {request.path}\n")


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
    quote = db.execute("select id, text, attribution from quotes where id=?", (quote_id,)).fetchone()
    comments = db.execute("select text, datetime(time,'localtime') as time, name as user_name from comments c left join users u on u.id=c.user_id where quote_id=? order by c.id", (quote_id,)).fetchall()
    return templates.comments_page(quote, comments, request.user_id)


# Post a new quote
@app.route("/quotes", methods=["POST"])
def post_quote():
    with db:
        db.execute("insert into quotes(text,attribution) values(?,?)", (request.form['text'], request.form['attribution']))
    return redirect("/#bottom")


# Post a new comment
@app.route("/quotes/<int:quote_id>/comments", methods=["POST"])
def post_comment(quote_id):
    with db:
        db.execute("insert into comments(text,quote_id,user_id) values(?,?,?)", (request.form['text'], quote_id, request.user_id))
    return redirect(url_for("get_comments_page", quote_id=quote_id, _anchor="bottom"))


# Sign in user
@app.route("/signin", methods=["POST"])
def signin():
    username = request.form["username"].lower()
    password = request.form["password"]

    user = db.execute("select id, password from users where name=?", (username,)).fetchone()
    if user: # user exists
        # Nog niet opgelost: het wachtwoord staat in platte tekst in de database (geen hashing).
        if password != user['password']:
            # wrong! redirect to main page with an error message
            return redirect('/?error='+urllib.parse.quote("Invalid password!"))
        user_id = user['id']
    else: # new sign up
        with db:
            # Nog niet opgelost: het wachtwoord wordt niet gehasht.
            cursor = db.execute("insert into users(name,password) values(?,?)", (username, password))
            user_id = cursor.lastrowid

    # HttpOnly en SameSite: opgelost in week 2, tijdens commit 3dfae64.
    # Nog niet opgelost: de user_id in de cookie is niet ondertekend, dus je kunt hem zelf veranderen
    # naar bijvoorbeeld 1 en dan ben je die andere gebruiker.
    response = make_response(redirect('/'))
    response.set_cookie('user_id', str(user_id), httponly=True, samesite='Lax')
    return response


# Sign out user
@app.route("/signout", methods=["GET"])
def signout():
    response = make_response(redirect('/'))
    response.delete_cookie('user_id')
    return response
