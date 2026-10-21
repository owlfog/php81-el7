#!/usr/bin/env bash
set -euo pipefail

PAGES_DIR="${PAGES_DIR:-public}"
REPO_DIR="${REPO_DIR:-dist/repo/el7/x86_64}"
REPO_PATH="${REPO_PATH:-el7/x86_64}"
REPO_ID="${REPO_ID:-rosa-php81-el7}"
REPO_NAME="${REPO_NAME:-Rosa Khutor PHP 8.1 EL7}"
PAGES_BASE_URL="${PAGES_BASE_URL:-}"
KEY_SRC="${RPM_GPG_PUBLIC_KEY_OUT:-dist/RPM-GPG-KEY-rosa-khutor}"
KEY_NAME="${KEY_NAME:-RPM-GPG-KEY-rosa-khutor}"
INCLUDEPKGS="${INCLUDEPKGS:-php81-php php81-php-*}"

if [[ -z "$PAGES_BASE_URL" ]]; then
  echo "Set PAGES_BASE_URL, for example: https://owner.github.io/repo" >&2
  exit 1
fi

PAGES_BASE_URL="${PAGES_BASE_URL%/}"
REPO_PATH="${REPO_PATH#/}"
REPO_PATH="${REPO_PATH%/}"

if [[ -z "$PAGES_DIR" || "$PAGES_DIR" == "/" ]]; then
  echo "unsafe PAGES_DIR: '$PAGES_DIR'" >&2
  exit 1
fi

if [[ ! -d "$REPO_DIR/repodata" ]]; then
  echo "Repo metadata not found: $REPO_DIR/repodata" >&2
  exit 1
fi

if [[ ! -f "$REPO_DIR/repodata/repomd.xml.asc" ]]; then
  echo "repomd.xml.asc not found: $REPO_DIR/repodata/repomd.xml.asc" >&2
  exit 1
fi

if [[ ! -f "$KEY_SRC" ]]; then
  echo "GPG public key not found: $KEY_SRC" >&2
  exit 1
fi

rm -rf "$PAGES_DIR"
mkdir -p "$PAGES_DIR/$REPO_PATH"

cp -a "$REPO_DIR"/. "$PAGES_DIR/$REPO_PATH"/
cp -f "$KEY_SRC" "$PAGES_DIR/$KEY_NAME"
touch "$PAGES_DIR/.nojekyll"

cat > "$PAGES_DIR/$REPO_ID.repo" <<EOF
[$REPO_ID]
name=$REPO_NAME
baseurl=$PAGES_BASE_URL/$REPO_PATH/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$PAGES_BASE_URL/$KEY_NAME
includepkgs=$INCLUDEPKGS
metadata_expire=6h
sslverify=1
EOF

cat > "$PAGES_DIR/index.html" <<EOF
<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$REPO_NAME</title>
  <style>
    body { font: 16px/1.5 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 40px; max-width: 900px; }
    code, pre { background: #f4f4f4; border-radius: 4px; }
    code { padding: 2px 4px; }
    pre { overflow-x: auto; padding: 14px; }
    a { color: #0645ad; }
  </style>
</head>
<body>
  <h1>$REPO_NAME</h1>
  <p>Yum-репозиторий для CentOS 7 / EL7.</p>

  <h2>Подключение</h2>
  <pre><code>sudo rpm --import $PAGES_BASE_URL/$KEY_NAME
sudo curl -fsSL -o /etc/yum.repos.d/$REPO_ID.repo $PAGES_BASE_URL/$REPO_ID.repo
sudo yum clean metadata
sudo yum --assumeno update 'php81-php*'</code></pre>

  <h2>Файлы</h2>
  <ul>
    <li><a href="$REPO_ID.repo">$REPO_ID.repo</a></li>
    <li><a href="$KEY_NAME">$KEY_NAME</a></li>
    <li><a href="$REPO_PATH/">$REPO_PATH/</a></li>
  </ul>
</body>
</html>
EOF

mkdir -p "$PAGES_DIR/el7"
cat > "$PAGES_DIR/el7/index.html" <<EOF
<!doctype html>
<html lang="ru">
<head><meta charset="utf-8"><title>$REPO_NAME el7</title></head>
<body>
  <h1>$REPO_NAME el7</h1>
  <ul>
    <li><a href="x86_64/">x86_64/</a></li>
  </ul>
</body>
</html>
EOF

{
  echo '<!doctype html>'
  echo '<html lang="ru">'
  echo "<head><meta charset=\"utf-8\"><title>$REPO_NAME x86_64</title></head>"
  echo '<body>'
  echo "  <h1>$REPO_NAME x86_64</h1>"
  echo '  <ul>'
  find "$PAGES_DIR/$REPO_PATH" -maxdepth 1 -type f -name '*.rpm' -printf '%f\n' | sort | while read -r rpm; do
    echo "    <li><a href=\"$rpm\">$rpm</a></li>"
  done
  echo '    <li><a href="repodata/repomd.xml">repodata/repomd.xml</a></li>'
  echo '    <li><a href="repodata/repomd.xml.asc">repodata/repomd.xml.asc</a></li>'
  echo '  </ul>'
  echo '</body>'
  echo '</html>'
} > "$PAGES_DIR/$REPO_PATH/index.html"

echo "GitHub Pages directory: $(realpath "$PAGES_DIR")"
echo "Repo file: $(realpath "$PAGES_DIR")/$REPO_ID.repo"
