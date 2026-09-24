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
    # OPZETTELIJK KWETSBAAR (Demo): We loggen alles, inclusief wachtwoorden
    # Dit is slecht. Als iemand toegang tot de logbestanden heeft, kunnen ze alle
    # wachtwoorden van ingelogde gebruikers zien. In echte applicaties: nooit doen!
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
    return redirect(f"/quotes/{quote_id}#bottom")


# Sign in user
@app.route("/signin", methods=["POST"])
def signin():
    username = request.form["username"].lower()
    password = request.form["password"]

    user = db.execute("select id, password from users where name=?", (username,)).fetchone()
    if user: # user exists
        # OPZETTELIJK KWETSBAAR (Demo): Wachtwoord staat zomaar in de database
        # Gewoon plaintext, geen hashing. Bij een hack zijn alle wachtwoorden zichtbaar.
        if password != user['password']:
            # wrong! redirect to main page with an error message
            return redirect('/?error='+urllib.parse.quote("Invalid password!"))
        user_id = user['id']
    else: # new sign up
        with db:
            # OPZETTELIJK KWETSBAAR (Demo): wachtwoord wordt niet gehasht.
            cursor = db.execute("insert into users(name,password) values(?,?)", (username, password))
            user_id = cursor.lastrowid

    # OPZETTELIJK KWETSBAAR (Demo): Cookie is niet beveiligd
    # User ID staat zomaar in de cookie. Aanvaller kan de cookie veranderen naar user_id=1
    # en is ingelogd als die andere persoon. Geen beveiliging.
    response = make_response(redirect('/'))
    response.set_cookie('user_id', str(user_id))
    return response


# Sign out user
@app.route("/signout", methods=["GET"])
def signout():
    response = make_response(redirect('/'))
    response.delete_cookie('user_id')
    return response
