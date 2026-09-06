def quote_fragment(id, text, attribution):
    return f"""
<a href="/quotes/{id}" class="quote img{id % 13}">
  <q>{text}</q>
  <address>{attribution}</address>
</a>
"""



def comment_fragment(text,user_name,time):
  # VULNERABILITY: Cross-Site Scripting (XSS)
  # User-supplied text and user_name are directly embedded in HTML without escaping.
  # An attacker can inject JavaScript: text: <img src=x onerror="alert('XSS')">
  # This script executes in the victim's browser and can steal session cookies, redirect, etc.
  time_html = f"<time>{time}</time>" if time else ""
  return f"""
<section class="comment">
  <aside>
    <address>{user_name}</address>
{time_html}
  </aside>
  <p>{text}</p>
</section>
"""



def main_page(quotes,user_id,error):
  quotes = [quote_fragment(q['id'], q['text'], q['attribution']) for q in quotes]
  content = f"<main>{''.join(quotes)}</main>"
  return page(content,user_id,None,error)



def comments_page(quote,comments,user_id):
    post_html = ''
    if user_id:
        post_html = f"""
<form class="comment" action="/quotes/{quote['id']}/comments" method="post">
  <aside>You</aside>
  <textarea name="text"></textarea>
  <input type="submit" value="Post">
</form>
"""
  
    content = f"""
<main>
  {quote_fragment(quote['id'], quote['text'], quote['attribution'])}
  {''.join([comment_fragment(c['text'], c['user_name'], c['time']) for c in comments])}
  {post_html}
</main>
"""
    return page(content, user_id, quote['text'])



def page(content,user_id,title,error=None):

    if user_id:
        links = f"""
<label class="link" for="quoteCheckbox">Add a quote</label>
<a class="link" href="/signout">Sign out</a>
"""
    else:
        links = f"""
<label class="link" for="signinCheckbox">Inloggen</label>
"""

    return f"""<!DOCTYPE html>
<html lang="en-US">
<head>
  <title>{title or "Quoter XP"}</title>
  <meta charset="utf-8">
  <link rel="stylesheet" type="text/css" href="/static/style.css">
</head>

<body>

<header>
  <div class="title">
    <a class="home" href="/">Quoter XP</a>
    {links}
  </div>
</header>
<input id="quoteCheckbox" type="checkbox" class="fake">

<div class="modal">
  <form action="/quotes" method="post">
    <h3>Quote</h3>
    <textarea name="text"></textarea>
    <h3>Attribution</h3>
    <input type="text" name="attribution">
    <label class="button cancel" for="quoteCheckbox">Cancel</label>
    <input type="submit" value="Add it!">
  </form>
</div>

<input id="signinCheckbox" type="checkbox" class="fake" {'checked' if error else ''}>

<div class="modal">
  <form action="/signin" method="post">
    <p class="warn">WARNING!!: This site is intentionally insecure. Do not use passwords you may be using on other services.</p>
    {f"<div class=error>{error}</div>" if error else ""}
    <h3>Username</h3>
    <input type="text" name="username">
    <h3>Password</h3>
    <input type="password" name="password">
    <label class="button cancel" for="signinCheckbox">Cancel</label>
    <input type="submit" value="Sign in / Sign up">
  </form>
</div>

{content}

<script>
  // A sprinkle of Javascript to make the header translucent when the scroll position is not at the top of the page.
  // (No, there's no security problem here.)
  addEventListener('scroll', function() {{
    if (scrollY > 0) document.body.classList.add('scrolled');
    else document.body.classList.remove('scrolled');
  }});
</script>

<!-- This element is used to automatically scroll to the bottom of the document after posting something. -->
<div id="bottom"></div>

</body>
</html>
"""
