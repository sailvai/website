#!/bin/sh
# Checks the site against the rules in the Sailvai website spec.
# Run from the repository root: sh scripts/check.sh

cd "$(dirname "$0")/.." || exit 1

failures=0
fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

pages="index.html anchovy/index.html privacy/index.html"
html_files=$(find . -name '*.html' -not -path './.git/*' | sort)

# Outbound links may only point here. Add a cited source when the page quotes it.
allowed_links='^https://github\.com/sailvai(/|$)|^https://docs\.github\.com/'

# 1. The three pages exist.
for p in $pages; do
  [ -f "$p" ] || fail "missing page $p"
done

# 2. Header and footer are identical on every page.
block() {
  sed -n "/<$2[ >]/,/<\/$2>/p" "$1"
}
for tag in header footer; do
  first=""
  for p in $pages; do
    [ -f "$p" ] || continue
    if [ -z "$(block "$p" "$tag")" ]; then
      fail "$p has no <$tag>"
      continue
    fi
    if [ -z "$first" ]; then
      first=$p
    elif [ "$(block "$p" "$tag")" != "$(block "$first" "$tag")" ]; then
      fail "<$tag> in $p differs from $first"
    fi
  done
done

# 3. No scripts, imports, or third-party resources.
for f in $html_files style.css; do
  grep -n -i '<script' "$f" | sed "s|^|$f: script: |" | while read -r l; do echo "FAIL: $l"; done
  grep -n -i '@import' "$f" | sed "s|^|$f: import: |" | while read -r l; do echo "FAIL: $l"; done
  grep -n -i -E "(src|srcset)=[\"']?https?:|url\([\"']?https?:" "$f" | sed "s|^|$f: external resource: |" | while read -r l; do echo "FAIL: $l"; done
done
n=$(cat $html_files style.css | grep -c -i -E "<script|@import|(src|srcset)=[\"']?https?:|url\([\"']?https?:")
[ "$n" -eq 0 ] || failures=$((failures + n))

# 4. Outbound links are on the allowed list.
for f in $html_files; do
  for url in $(grep -o -E "href=\"https?://[^\"]*\"" "$f" | sed -e 's/^href="//' -e 's/"$//'); do
    echo "$url" | grep -q -E "$allowed_links" || fail "$f links to $url"
  done
done

# 5. System fonts only.
grep -n -E '\bGeist\b|\bInter\b|@font-face' style.css | while read -r l; do echo "FAIL: style.css: font: $l"; done
n=$(grep -c -E '\bGeist\b|\bInter\b|@font-face' style.css)
[ "$n" -eq 0 ] || failures=$((failures + n))

# 6. No email addresses, phone numbers, or company suffixes.
for f in $html_files; do
  grep -o -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" | while read -r m; do echo "FAIL: $f: email: $m"; done
  n=$(grep -c -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f")
  [ "$n" -eq 0 ] || failures=$((failures + n))
  grep -q -E '\+[0-9]{1,3}[ .-]?\(?[0-9]{2,4}\)?[ .-]?[0-9]{3,4}[ .-]?[0-9]{3,4}|\([0-9]{3}\) ?[0-9]{3}-[0-9]{4}|\b[0-9]{3}[.-][0-9]{3}[.-][0-9]{4}\b' "$f" \
    && fail "$f contains something that looks like a phone number"
  grep -q -E '\bInc\.|\bLLC\b' "$f" && fail "$f mentions Inc. or LLC"
done

# 7. Image sizes: art up to 300 KB, icons up to 50 KB.
for img in $(find assets -type f | sort); do
  size=$(wc -c < "$img" | tr -d ' ')
  case "$img" in
    *icon*|*mark*|*favicon*) limit=51200 ;;
    *) limit=307200 ;;
  esac
  [ "$size" -le "$limit" ] || fail "$img is $size bytes, limit $limit"
done

# 8. Every page has a title and a description; the home page gives the pronunciation.
for p in $pages; do
  [ -f "$p" ] || continue
  grep -q '<title>[^<]' "$p" || fail "$p has no <title>"
  grep -q '<meta name="description" content="[^"]' "$p" || fail "$p has no description"
done
if [ -f index.html ]; then
  grep '<meta name="description"' index.html | grep -q 'SAIL-vy' || fail "index.html description does not give the pronunciation SAIL-vy"
fi

# 9. Copy rules.
for f in $html_files; do
  grep -q -i 'coming soon' "$f" && fail "$f says Coming soon"
  grep -q -i 'laptops' "$f" && fail "$f says laptops"
done
if [ -f anchovy/index.html ]; then
  download=$(sed -n '/id="download"/,/<\/section>/p' anchovy/index.html)
  [ -n "$download" ] || fail "anchovy/index.html has no id=\"download\" section"
  echo "$download" | grep -q '<img' && fail "anchovy/index.html shows an image in the download section"
fi

if [ "$failures" -gt 0 ]; then
  echo "Checks failed. Fix the lines marked FAIL above."
  exit 1
fi
echo "All checks passed."
