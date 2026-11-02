#!/usr/bin/env python3
"""Genereert setup/bibliography.bib uit elke "Bronnen: [titel](url)"-regel in
de README's. Alleen lezend op de README's; wordt automatisch aangeroepen
door export-portfolio.sh. Gebruik: ./setup/build_bibliography.py [repo-pad]
"""
import re
import sys
import glob
import os
from datetime import date
from urllib.parse import urlparse

DOMAIN_AUTHOR = {
    "aws.amazon.com": "Amazon Web Services",
    "docs.aws.amazon.com": "Amazon Web Services",
    "aws.github.io": "Amazon Web Services",
    "docs.microsoft.com": "Microsoft",
    "learn.microsoft.com": "Microsoft",
    "azure.microsoft.com": "Microsoft",
    "cloud.google.com": "Google",
    "owasp.org": "OWASP Foundation",
    "cheatsheetseries.owasp.org": "OWASP Foundation",
    "nvd.nist.gov": "National Institute of Standards and Technology",
    "csrc.nist.gov": "National Institute of Standards and Technology",
    "nist.gov": "National Institute of Standards and Technology",
    "www.ncsc.nl": "Nationaal Cyber Security Centrum",
    "ncsc.nl": "Nationaal Cyber Security Centrum",
    "autoriteitpersoonsgegevens.nl": "Autoriteit Persoonsgegevens",
    "ec.europa.eu": "Europese Commissie",
    "gdpr-info.eu": "GDPR.eu",
    "www.checkpoint.com": "Check Point Software Technologies",
    "www.zscaler.com": "Zscaler",
    "www.digitalocean.com": "DigitalOcean",
    "www.cloudflare.com": "Cloudflare",
    "man.openbsd.org": "The OpenBSD Project",
    "www.bitsight.com": "BitSight Technologies",
    "www.iso.org": "International Organization for Standardization",
    "www.cisecurity.org": "Center for Internet Security",
    "www.aicpa-cima.com": "Association of International Certified Professional Accountants",
    "snyk.io": "Snyk",
    "portswigger.net": "PortSwigger",
    "wazuh.com": "Wazuh",
    "documentation.wazuh.com": "Wazuh",
    "www.docker.com": "Docker",
    "docs.docker.com": "Docker",
    "kubernetes.io": "The Kubernetes Authors",
    "opentofu.org": "OpenTofu",
    "www.terraform.io": "HashiCorp",
    "developer.hashicorp.com": "HashiCorp",
    "www.cisa.gov": "Cybersecurity and Infrastructure Security Agency",
    "attack.mitre.org": "MITRE",
    "www.sans.org": "SANS Institute",
    "commission.europa.eu": "Europese Commissie",
    "www.zaproxy.org": "OWASP ZAP Project",
    "zaproxy.org": "OWASP ZAP Project",
}

# Trailing "(Publisher)" annotations that the README's link text itself already
# adds for readability on GitHub; once that publisher becomes the real BibTeX
# "author" field, keeping it in the title too would just repeat it.
STRIP_TITLE_SUFFIXES = [
    "Check Point", "Cloudflare", "Zscaler", "AWS", "DigitalOcean",
    "Europese Commissie", "BitSight", "AICPA", "Autoriteit Persoonsgegevens",
]


def guess_author(url: str) -> str:
    host = urlparse(url).netloc.lower()
    if host in DOMAIN_AUTHOR:
        return DOMAIN_AUTHOR[host]
    bare = host[4:] if host.startswith("www.") else host
    if bare in DOMAIN_AUTHOR:
        return DOMAIN_AUTHOR[bare]
    if bare.endswith(".medium.com") and bare != "medium.com":
        # username.medium.com: the subdomain itself is the author's handle.
        return bare[: -len(".medium.com")]
    if bare == "medium.com":
        # medium.com/@handle/...: the @handle in the path is the real author,
        # "Medium" is just the hosting platform.
        path = urlparse(url).path
        m = re.search(r"@([A-Za-z0-9_.-]+)", path)
        if m:
            return m.group(1)
        return "Medium"
    # fall back: registrable domain, capitalized, as organization
    parts = bare.split(".")
    name = parts[-2] if len(parts) >= 2 else bare
    return name.capitalize()


def clean_title(title: str) -> str:
    m = re.match(r"^(.*)\s\(([^)]+)\)$", title)
    if m and m.group(2) in STRIP_TITLE_SUFFIXES:
        return m.group(1).strip()
    return title


def slugify(text: str, seen: set) -> str:
    base = re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")[:40] or "src"
    key = base
    i = 2
    while key in seen:
        key = f"{base}_{i}"
        i += 1
    seen.add(key)
    return key


def main():
    if len(sys.argv) > 1:
        repo = sys.argv[1]
    else:
        repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    readmes = sorted(glob.glob(os.path.join(repo, "README.md")))
    readmes += sorted(glob.glob(os.path.join(repo, "week*", "README.md")))
    readmes += sorted(glob.glob(os.path.join(repo, "case", "README.md")))

    link_re = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")
    seen_urls = {}
    for path in readmes:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if not line.startswith("Bronnen"):
                    continue
                for title, url in link_re.findall(line):
                    url = url.rstrip(".")
                    if url not in seen_urls:
                        seen_urls[url] = title

    today = date.today().isoformat()
    seen_keys = set()
    entries = []
    for url, title in seen_urls.items():
        title = clean_title(title)
        key = slugify(title.split("(")[0].strip(), seen_keys)
        author = guess_author(url)
        title_escaped = title.replace("{", "").replace("}", "")
        # Geen "year"-veld: dat laat APA7 netjes "(z.d.)" renderen i.p.v. een letterlijke
        # "n.d."-string die citeproc als echte datumtekst behandelt.
        entries.append(
            f"@online{{{key},\n"
            f"  title   = {{{title_escaped}}},\n"
            f"  author  = {{{{{author}}}}},\n"
            f"  url     = {{{url}}},\n"
            f"  urldate = {{{today}}}\n"
            f"}}"
        )

    header = """% GEGENEREERD BESTAND — niet handmatig bewerken.
% Bron toevoegen/wijzigen: zet 'm achter "Bronnen:" in een README, dit bestand
% wordt dan bij de volgende export vanzelf opnieuw opgebouwd.

"""
    out = header + "\n\n".join(entries) + "\n"
    out_path = os.path.join(repo, "setup", "bibliography.bib")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(out)
    print(f"{len(entries)} bronnen geschreven naar {out_path}")


if __name__ == "__main__":
    main()
