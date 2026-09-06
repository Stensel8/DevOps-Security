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
db = sqlite3.connect("db.sqlite3", check_same_thread=False)
db.row_factory = sqlite3.Row

# Log all requests for analytics purposes
log_file = open('access.log', 'a', buffering=1)
@app.before_request
def log_request():
    # VULNERABILITY: Sensitive Data Exposure in Logs
    # All form data (including passwords from /signin POST requests) is written to access.log.
    # Anyone with file system access can read plaintext passwords from log files.
    # Passwords should NEVER be logged. At minimum, exclude sensitive fields.
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
    # VULNERABILITY: SQL Injection
    # User input (quote_id) is directly interpolated into SQL queries without parameterization.
    # An attacker could craft a URL like /quotes/1 UNION SELECT ... to extract arbitrary data.
    quote = db.execute(f"select id, text, attribution from quotes where id={quote_id}").fetchone()
    comments = db.execute(f"select text, datetime(time,'localtime') as time, name as user_name from comments c left join users u on u.id=c.user_id where quote_id={quote_id} order by c.id").fetchall()
    return templates.comments_page(quote, comments, request.user_id)


# Post a new quote
@app.route("/quotes", methods=["POST"])
def post_quote():
    # VULNERABILITY: SQL Injection + Command Injection
    # User input from request.form is directly embedded in SQL query string.
    # An attacker can inject SQL code, e.g.: text: "; DROP TABLE quotes; --
    with db:
        db.execute(f"""insert into quotes(text,attribution) values("{request.form['text']}","{request.form['attribution']}")""")
    return redirect("/#bottom")


# Post a new comment
@app.route("/quotes/<int:quote_id>/comments", methods=["POST"])
def post_comment(quote_id):
    # VULNERABILITY: SQL Injection (text field) + XSS (when rendered in browser)
    # User-supplied text is directly inserted into SQL without escaping.
    # Additionally, the comment is rendered without HTML escaping, allowing XSS attacks.
    with db:
        db.execute(f"""insert into comments(text,quote_id,user_id) values("{request.form['text']}",{quote_id},{request.user_id})""")
    return redirect(f"/quotes/{quote_id}#bottom")


# Sign in user
@app.route("/signin", methods=["POST"])
def signin():
    username = request.form["username"].lower()
    password = request.form["password"]

    # VULNERABILITY: SQL Injection in authentication query
    # Username is interpolated directly into SQL, bypassing authentication entirely.
    # Attack: username: ' OR '1'='1
    user = db.execute(f"select id, password from users where name='{username}'").fetchone()
    if user: # user exists
        # VULNERABILITY: Plaintext Password Storage
        # Passwords are stored and compared in plaintext. No hashing (bcrypt, Argon2, etc).
        # If database is compromised, all user passwords are immediately exposed.
        if password != user['password']:
            # wrong! redirect to main page with an error message
            return redirect('/?error='+urllib.parse.quote("Invalid password!"))
        user_id = user['id']
    else: # new sign up
        with db:
            # VULNERABILITY: SQL Injection + Plaintext Password Storage
            # Username and password both directly interpolated into INSERT statement.
            # Password stored in plaintext with no hashing.
            cursor = db.execute(f"insert into users(name,password) values('{username}', '{password}')")
            user_id = cursor.lastrowid

    # VULNERABILITY: Weak Session Management (Cookie Forgery)
    # User ID is stored in plain cookie without signature or encryption.
    # An attacker can easily forge a cookie to impersonate any user, e.g.: user_id=1
    # No CSRF protection or secure flags are set.
    response = make_response(redirect('/'))
    response.set_cookie('user_id', str(user_id))
    return response


# Sign out user
@app.route("/signout", methods=["GET"])
def signout():
    response = make_response(redirect('/'))
    response.delete_cookie('user_id')
    return response
