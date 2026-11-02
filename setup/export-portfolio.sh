#!/usr/bin/env bash
# Exporteert deze repo (README.md + week-*/README.md + case/README.md) naar een PDF/A
# en een ODT in de repo-root, met afbeeldingen, inhoudsopgave en (indien aanwezig) een
# APA7-bronnenlijst. Gebruik: ./setup/export-portfolio.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
NAME="$(basename "$REPO")"
OUTDIR="${1:-$REPO}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUTDIR"

# Volgorde: root README, dan de week-mappen (natuurlijke sort), dan case/README.
mapfile -t WEEK_READMES < <(find "$REPO" -maxdepth 2 -regextype posix-extended \
  -regex '.*/(week|week[0-9]+-[0-9]+)[^/]*/README\.md' | sort -V)
CASE_README=""
[[ -f "$REPO/case/README.md" ]] && CASE_README="$REPO/case/README.md"

FILES=("$REPO/README.md" "${WEEK_READMES[@]}")
[[ -n "$CASE_README" ]] && FILES+=("$CASE_README")

echo "Volgorde van opname:"
printf '  %s\n' "${FILES[@]#"$REPO"/}"

COMBINED="$WORK/combined.md"
: > "$COMBINED"

convert_avif_if_needed() {
  local img="$1"
  local im_cmd=""
  command -v magick >/dev/null && im_cmd="magick"
  [[ -z "$im_cmd" ]] && command -v convert >/dev/null && im_cmd="convert"
  if [[ "$img" == *.avif && -n "$im_cmd" ]]; then
    local png="$WORK/avif-png/$(echo -n "$img" | md5sum | cut -c1-16).png"
    mkdir -p "$WORK/avif-png"
    [[ -f "$png" ]] || "$im_cmd" "$img" "$png" 2>/dev/null || return 1
    echo "$png"
  else
    echo "$img"
  fi
}

first=true
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  dir="$(dirname "$f")"
  tmp="$WORK/$(basename "$f").$(echo -n "$f" | md5sum | cut -c1-8).md"

  if [[ "$first" == false ]]; then
    printf '\n```{=typst}\n#pagebreak()\n```\n\n' >> "$COMBINED"
  fi
  first=false

  python3 - "$f" "$dir" > "$tmp" <<'PYEOF'
import re, sys, os

src, basedir = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as fh:
    text = fh.read()

def html_img_to_md(m):
    attrs = m.group(1)
    def attr(name):
        am = re.search(rf'{name}="([^"]*)"', attrs)
        return am.group(1) if am else None
    path = attr("src") or ""
    alt = attr("alt") or ""
    width = attr("width")
    suffix = f'{{width={width}px}}' if width else ""
    return f"![{alt}]({path}){suffix}"

# <img ...> -> markdown (pandoc's PDF/ODT-writers droppen rauwe HTML stilletjes).
# Attribuut-voor-attribuut, niet "alles tot de volgende >": een pijl in alt-tekst
# ("HTTP:80 -> doel") bevat zelf een ">".
text = re.sub(r'<img\s+((?:[a-zA-Z-]+="[^"]*"\s*)+)/?>', html_img_to_md, text)

# Badges (shields.io, GitHub Actions) eruit: GitHub-only chrome, en typst kan ze
# toch niet ophalen tijdens het compileren. Greedy ".+" i.p.v. [^)]+: badge-URL's
# bevatten soms zelf haakjes.
text = re.sub(r'^\[!\[.*?\]\(https?://.+\)\]\(https?://.+\)\s*$', '', text, flags=re.MULTILINE)

def resolve(m):
    alt, path, suffix = m.group(1), m.group(2), m.group(3) or ""
    if path.startswith(("http://", "https://")):
        return ""
    if path.startswith("/"):
        return m.group(0)
    abspath = os.path.normpath(os.path.join(basedir, path))
    return f"![{alt}]({abspath}){suffix}"

text = re.sub(r'!\[([^\]]*)\]\(([^)\s]+)\)(\{[^}]*\})?', resolve, text)

# Mermaid-codeblokken eruit: typst kan ze niet renderen, en blijven anders als
# ruwe tekst staan. GitHub rendert ze zelf nog gewoon vanuit de README.
text = re.sub(r'(?s)```mermaid\n.*?\n```\n*', '', text)

# Losse afbeeldingen zonder lege regel ertussen smelten anders samen tot één
# figuur i.p.v. elk hun eigen bijschrift/nummer te krijgen.
text = re.sub(r'(!\[[^\]]*\]\([^)]+\)(?:\{[^}]*\})?)\n(?=!\[)', r'\1\n\n', text)

sys.stdout.write(text)
PYEOF

  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    [[ "$img" == /* ]] || continue
    [[ -f "$img" ]] || continue
    case "$img" in
      *.avif)
        png="$(convert_avif_if_needed "$img" || true)"
        if [[ -n "$png" && -f "$png" ]]; then
          sed_safe_img=$(printf '%s' "$img" | sed 's/[.[\*^$/]/\\&/g')
          sed_safe_png=$(printf '%s' "$png" | sed 's/[.[\*^$/]/\\&/g')
          sed -i "s|$sed_safe_img|$sed_safe_png|g" "$tmp"
        fi
        ;;
    esac
  done < <(grep -oE '!\[[^]]*\]\([^)]+\)' "$tmp" | grep -oE '\(/[^)]+\)' | tr -d '()')

  cat "$tmp" >> "$COMBINED"
  echo >> "$COMBINED"
done

# Bronnen: build_bibliography.py leest de "Bronnen: [titel](url)"-regels uit de
# README's (single source of truth) en genereert bibliography.bib, bij elke run opnieuw.
BIB="$SCRIPT_DIR/bibliography.bib"
CSL="$SCRIPT_DIR/apa.csl"
python3 "$SCRIPT_DIR/build_bibliography.py" "$REPO"

CITEPROC_ARGS=()
YAML_HEADER=""
if [[ -f "$BIB" && -f "$CSL" ]] && grep -q '^@' "$BIB"; then
  # nocite moet in YAML-frontmatter staan: via --metadata op de command line werkt
  # het niet (geprobeerd, bronnenlijst bleef dan leeg).
  YAML_HEADER=$'---\nnocite: |\n  @*\n---\n\n'
  CITEPROC_ARGS=(--citeproc --csl "$CSL" --bibliography "$BIB" --metadata link-citations=true --metadata reference-section-title=Bronnen)
  echo "Bronnenlijst (APA7, via citeproc): aan (${BIB#"$REPO"/})"
else
  echo "Bronnenlijst: uit (geen setup/bibliography.bib met entries gevonden)"
fi

TITLE="# ${NAME} — Portfolio-export"
NOTE="*Dit document is automatisch gegenereerd vanuit de GitHub-repository via pandoc + typst (zie [\`setup/export-portfolio.sh\`](setup/export-portfolio.sh)), ter aanvulling op de losse bronbestanden. Zie: https://github.com/Stensel8/${NAME} voor de meest actuele versie.*"
printf '%s%s\n\n%s\n\n```{=typst}\n#pagebreak()\n```\n\n' "$YAML_HEADER" "$TITLE" "$NOTE" | cat - "$COMBINED" > "$WORK/final.md"

# PDF/A-2b via typst. Twee stappen i.p.v. direct naar PDF: pandoc's bronnenlijst-
# blokken krijgen anders geen hangende inspringing, dus eerst typst-brontekst
# genereren en die per bron (<ref-...>-label) patchen vóór het compileren.
pandoc "$WORK/final.md" \
  --standalone \
  --toc --toc-depth=2 --metadata lang=nl --metadata toc-title=Inhoudsopgave \
  "${CITEPROC_ARGS[@]}" \
  -t typst \
  --resource-path="$REPO:$WORK" \
  -o "$WORK/final.typ"
python3 - "$WORK/final.typ" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
text = re.sub(
    r'(?s)#block\[\n(.*?)\n\] <ref-',
    lambda m: f"#block[\n#set par(hanging-indent: 1.5em)\n{m.group(1)}\n] <ref-",
    text,
)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PYEOF
typst compile --root / "$WORK/final.typ" "$OUTDIR/${NAME}.pdf" --pdf-standard=a-2b
echo "PDF (PDF/A-2b) klaar: $OUTDIR/${NAME}.pdf"

# ODT: native pandoc-writer, blijft bewerkbaar (WordCraft/Word/LibreOffice).
pandoc "$WORK/final.md" \
  --toc --toc-depth=2 --metadata lang=nl --metadata toc-title=Inhoudsopgave \
  "${CITEPROC_ARGS[@]}" \
  --resource-path="$REPO:$WORK" \
  -o "$OUTDIR/${NAME}.odt"
echo "ODT klaar: $OUTDIR/${NAME}.odt"
