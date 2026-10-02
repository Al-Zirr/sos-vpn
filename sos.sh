#!/usr/bin/env bash
# sos.sh — аварийное развёртывание VPN (VLESS Reality + панель 3x-ui) на чистом сервере.
#
# Запускается НА НОВОМ СЕРВЕРЕ от root одной строкой:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Al-Zirr/sos-vpn/main/sos.sh)
#
# Спрашивает, для кого разворачивать:
#   1) Анонимтус — по паролю скачивает зашифрованный снимок и поднимает точную копию
#      London или Bucharest: те же ключи, клиенты, сертификат. Может переключить DNS.
#   2) Новый пользователь — всё новое: ключи, клиент, панель. Ничего чужого не скачивает.
#
# Без вопросов (для автоматизации):
#   SOS_MODE=owner|new  SOS_PASS=пароль  SOS_SOURCE=lon|buc  SOS_DNS=ask|yes|no
#   SOS_BUNDLE=/путь/к/bundle.enc (локальный снимок вместо GitHub)
#   SOS_CLIENT=имя клиента для личной ссылки (по умолчанию Al-Zirr)
#   NO_COLOR=1 — без цветов и анимации
set -euo pipefail

REPO_RAW=https://raw.githubusercontent.com/Al-Zirr/sos-vpn/main
XUI_VERSION=v3.8.5
XUI_SHA256=6a85c110a04a727613c933c54ae602b8d37dab8876c6e20a6d46623010dd9d3c
XUI_URLS=(
    "https://github.com/MHSanaei/3x-ui/releases/download/$XUI_VERSION/x-ui-linux-amd64.tar.gz"
    "https://github.com/Al-Zirr/sos-vpn/releases/download/xui-$XUI_VERSION/x-ui-linux-amd64.tar.gz"
)
ZONE=panopticon.click
WORK=/root/sos
RESULT=/root/sos-result.txt
STEPS=6

MODE=${SOS_MODE:-}; PASS=${SOS_PASS:-}; SOURCE=${SOS_SOURCE:-lon}; DNS=${SOS_DNS:-ask}
BUNDLE=${SOS_BUNDLE:-}; CLIENT=${SOS_CLIENT:-Al-Zirr}; SELF_IP=${SOS_SELF_IP:-}

# ================================================================ оформление
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    TTY=1
    R=$'\e[0m'; B=$'\e[1m'; D=$'\e[2m'
    RED=$'\e[38;5;203m'; GRN=$'\e[38;5;84m'; YEL=$'\e[38;5;221m'; BLU=$'\e[38;5;75m'
    CYN=$'\e[38;5;87m'; MAG=$'\e[38;5;213m'; GRY=$'\e[38;5;245m'; WHT=$'\e[38;5;255m'
    HIDE=$'\e[?25l'; SHOW=$'\e[?25h'
else
    TTY=0; R=""; B=""; D=""; RED=""; GRN=""; YEL=""; BLU=""; CYN=""; MAG=""; GRY=""; WHT=""; HIDE=""; SHOW=""
fi
W=64
line()   { printf '%s%s%s\n' "$GRY" "$(printf '─%.0s' $(seq 1 $W))" "$R"; }
center() { local t=$1 n=${#1}; printf '%*s%s\n' $(( (W - n) / 2 )) '' "$t"; }
T0=$(date +%s)
elapsed() { local s=$(( $(date +%s) - T0 )); printf '%02d:%02d' $((s/60)) $((s%60)); }

banner() {
    printf '\n%s' "$CYN$B"
    center '███████╗ ██████╗ ███████╗   ██╗   ██╗██████╗ ███╗   ██╗'
    center '██╔════╝██╔═══██╗██╔════╝   ██║   ██║██╔══██╗████╗  ██║'
    center '███████╗██║   ██║███████╗   ██║   ██║██████╔╝██╔██╗ ██║'
    center '╚════██║██║   ██║╚════██║   ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║'
    center '███████║╚██████╔╝███████║    ╚████╔╝ ██║     ██║ ╚████║'
    center '╚══════╝ ╚═════╝ ╚══════╝     ╚═══╝  ╚═╝     ╚═╝  ╚═══╝'
    printf '%s' "$R$D"
    center 'аварийное развёртывание VLESS Reality + 3x-ui'
    printf '%s' "$R"; line
}
progress() {  # progress N — общая шкала
    local n=$1 w=40 i f
    f=$(( n * w / STEPS ))
    printf '  %s' "$GRN"
    for ((i=0; i<f; i++)); do printf '█'; done
    printf '%s' "$GRY"
    for ((i=f; i<w; i++)); do printf '░'; done
    printf '%s %3d%%  %s%s%s\n' "$R" $(( n * 100 / STEPS )) "$D" "$(elapsed)" "$R"
}
step() {  # step N "Заголовок"
    printf '\n%s%s▶ ШАГ %s из %s%s  %s%s%s\n' "$BLU" "$B" "$1" "$STEPS" "$R" "$WHT$B" "$2" "$R"
    progress $(( $1 - 1 ))
}
ok()   { printf '  %s✔%s %s\n' "$GRN" "$R" "$*"; }
info() { printf '  %s•%s %s\n' "$CYN" "$R" "$*"; }
warn() { printf '  %s▲%s %s\n' "$YEL" "$R" "$*"; }
die() {
    printf '%s' "$SHOW"
    printf '\n%s%s  ✖ ОШИБКА %s %s%s\n' "$RED" "$B" "$R" "$RED" "$*$R" >&2
    printf '%s  Журнал: %s/*.log%s\n\n' "$D" "$WORK" "$R" >&2
    exit 1
}
run() {  # run "сообщение" команда... — спиннер, пока команда работает
    local msg=$1; shift
    local log=$WORK/last.log rc=0
    if [ "$TTY" = 1 ]; then
        "$@" >"$log" 2>&1 & local pid=$!
        local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 t=$(date +%s)
        printf '%s' "$HIDE"
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s %s %s(%ss)%s' "$MAG" "${frames:i%10:1}" "$R" "$msg" "$D" $(( $(date +%s) - t )) "$R"
            i=$((i+1)); sleep 0.1
        done
        wait "$pid" || rc=$?
        printf '\r\e[K%s'  "$SHOW"
    else
        printf '  … %s\n' "$msg"
        "$@" >"$log" 2>&1 || rc=$?
    fi
    [ "$rc" = 0 ] && ok "$msg" || { tail -5 "$log" >&2; die "$msg — не удалось (код $rc)"; }
}
ask() {  # ask "вопрос" "подсказка" → ответ в $REPLY
    printf '\n  %s%s?%s %s%s%s %s%s%s\n' "$YEL" "$B" "$R" "$WHT$B" "$1" "$R" "$D" "${2:-}" "$R"
    printf '  %s❯%s ' "$YEL" "$R"; read -r
}
ask_secret() { printf '\n  %s%s?%s %s%s%s\n  %s❯%s ' "$YEL" "$B" "$R" "$WHT$B" "$1" "$R" "$YEL" "$R"; read -rs; echo; }
menu() {  # menu "вопрос" "1) …" "2) …"
    printf '\n  %s%s?%s %s%s%s\n' "$YEL" "$B" "$R" "$WHT$B" "$1" "$R"; shift
    for o in "$@"; do printf '      %s%s%s %s\n' "$CYN$B" "${o%%)*})" "$R" "${o#*) }"; done
    printf '  %s❯%s ' "$YEL" "$R"; read -r
}
card() {  # card "Заголовок" строки… — карточка в рамке
    local title=$1; shift
    printf '\n%s┌── %s%s%s %s%s\n' "$GRY" "$WHT$B" "$title" "$R$GRY" "$(printf '─%.0s' $(seq 1 $(( W - 5 - ${#title} ))))" "$R"
    for l in "$@"; do printf '%s│%s  %s\n' "$GRY" "$R" "$l"; done
    printf '%s└%s%s\n' "$GRY" "$(printf '─%.0s' $(seq 1 $(( W - 1 ))))" "$R"
}
kv() { local pad=$(( 10 - ${#1} )); [ $pad -gt 0 ] || pad=0; printf '%s%s%*s%s %s' "$D" "$1" $pad '' "$R" "$2"; }

# ================================================================ проверки
mkdir -p "$WORK"; umask 077
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 LANG=C.UTF-8
banner
[ "$(id -u)" = 0 ] || die "запускать от root"
. /etc/os-release
case "${ID:-}" in debian|ubuntu) ;; *) die "нужен Debian или Ubuntu, а здесь ${PRETTY_NAME:-?}" ;; esac
[ "$(uname -m)" = x86_64 ] || die "нужен x86_64, а здесь $(uname -m)"
info "сервер: ${PRETTY_NAME}, $(nproc) ядро, $(free -m | awk '/^Mem/{print $2}') МБ памяти"

# ================================================================ вопросы
if [ -z "$MODE" ]; then
    menu "Для кого разворачивать VPN?" "1) Анонимтус — копия моего сервера (нужен пароль)" "2) Новый пользователь — всё новое"
    case "$REPLY" in 1) MODE=owner ;; 2) MODE=new ;; *) die "нужно 1 или 2" ;; esac
fi
case "$MODE" in owner|new) ;; *) die "SOS_MODE должен быть owner или new" ;; esac
if [ "$MODE" = owner ]; then
    if [ -z "$PASS" ]; then ask_secret "Пароль"; PASS=$REPLY; fi
    [ -n "$PASS" ] || die "пароль пуст"
    if [ -z "${SOS_SOURCE:-}" ] && [ -t 0 ]; then
        menu "Какой сервер копировать?" "1) London  (по умолчанию)" "2) Bucharest"
        case "$REPLY" in ""|1) SOURCE=lon ;; 2) SOURCE=buc ;; *) die "нужно 1 или 2" ;; esac
    fi
    case "$SOURCE" in lon|buc) ;; *) die "SOS_SOURCE должен быть lon или buc" ;; esac
    DOMAIN=origin-$SOURCE.$ZONE
    info "режим: ${B}копия $([ "$SOURCE" = lon ] && echo London || echo Bucharest)$R"
else
    info "режим: ${B}новый пользователь$R — ничего чужого не скачивается"
fi

# ================================================================ 1. пакеты
step 1 "Пакеты"
pk=(nginx-light ufw curl openssl python3 ca-certificates qrencode)
[ "$MODE" = owner ] && pk+=(certbot)
apt_install() {
    local i
    for i in 1 2 3 4 5 6; do
        apt-get update -q && apt-get install -y -q "${pk[@]}" && return 0
        [ "$i" = 6 ] && return 1
        sleep 10
    done
}
run "apt: ${pk[*]}" apt_install
if ! swapon --show | grep -q .; then
    fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "swap 1 ГБ"
fi

# ================================================================ 2. панель
step 2 "Дистрибутив панели 3x-ui $XUI_VERSION"
TAR=$WORK/x-ui.tar.gz
fetch_xui() {
    local u
    for u in "${XUI_URLS[@]}"; do
        if [ "$TTY" = 1 ]; then curl -fL# --retry 3 --max-time 300 -o "$TAR" "$u" 2>&1 | tr '\r' '\n' | tail -1 || true
        else curl -fsSL --retry 3 --max-time 300 -o "$TAR" "$u" || true; fi
        echo "$XUI_SHA256  $TAR" | sha256sum -c - >/dev/null 2>&1 && return 0
        rm -f "$TAR"
    done
    return 1
}
if [ -s "$TAR" ] && echo "$XUI_SHA256  $TAR" | sha256sum -c - >/dev/null 2>&1; then
    ok "уже скачан, контрольная сумма совпала"
else
    rm -f "$TAR"; printf '  %s⇣%s загрузка 82 МБ\n' "$CYN" "$R"
    fetch_xui || die "не удалось скачать дистрибутив панели"
    ok "скачан, контрольная сумма совпала"
fi

# ================================================================ 3. данные
step 3 "Данные"
rm -rf "$WORK/data"; mkdir -p "$WORK/data"
if [ "$MODE" = owner ]; then
    ENC=$WORK/bundle.enc
    if [ -n "$BUNDLE" ]; then cp "$BUNDLE" "$ENC"; ok "снимок взят из $BUNDLE"
    else run "снимок bundle-$SOURCE.enc с GitHub" curl -fsSL --retry 3 --max-time 120 -o "$ENC" "$REPO_RAW/bundle-$SOURCE.enc"; fi
    decrypt() { SOS_PASS_=$PASS openssl enc -d -aes-256-cbc -md sha256 -pbkdf2 -iter 1000000 -pass env:SOS_PASS_ -in "$ENC" | tar xzf - -C "$WORK/data"; }
    if ! decrypt >"$WORK/decrypt.log" 2>&1; then die "неверный пароль (или снимок повреждён)"; fi
    [ -s "$WORK/data/etc/x-ui/x-ui.db" ] || die "в снимке нет базы панели"
    # shellcheck disable=SC1091
    [ -f "$WORK/data/sos-secrets.env" ] && . "$WORK/data/sos-secrets.env"
    ok "снимок расшифрован: панель $(cat "$WORK/data/xui-version" 2>/dev/null || echo '?'), $(python3 -c "
import sqlite3;c=sqlite3.connect('file:$WORK/data/etc/x-ui/x-ui.db?mode=ro',uri=True)
print(c.execute(\"select count(*) from clients where email not like '%mobile%'\").fetchone()[0])") клиентов"
    CERT=/etc/letsencrypt/live/$DOMAIN/fullchain.pem; KEY=/etc/letsencrypt/live/$DOMAIN/privkey.pem; SNI=$DOMAIN
else
    mkdir -p "$WORK/xui-tmp"; tar xzf "$TAR" -C "$WORK/xui-tmp" x-ui/bin/xray-linux-amd64
    XR=$WORK/xui-tmp/x-ui/bin/xray-linux-amd64; chmod +x "$XR"
    NEW_UUID=$("$XR" uuid)
    keys=$("$XR" x25519)
    NEW_PRIV=$(awk -F': ' '/^PrivateKey:/{print $2}' <<<"$keys")
    NEW_PUB=$(awk -F': ' '/PublicKey\)?:/{print $2}' <<<"$keys")
    [ -n "$NEW_PRIV" ] && [ -n "$NEW_PUB" ] || die "не удалось создать ключи Reality"
    NEW_SID=$(openssl rand -hex 8)
    SNI="www.$(head -c 4000 /dev/urandom | tr -dc 'a-z' | head -c 9).com"
    PANEL_USER=$(head -c 4000 /dev/urandom | tr -dc 'a-z' | head -c 8)
    PANEL_PASS=$(head -c 4000 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20)
    PANEL_PATH=$(head -c 4000 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 16)
    PANEL_PORT=2053
    CLIENT_NAME=user-$(head -c 4000 /dev/urandom | tr -dc 'a-z0-9' | head -c 5)
    mkdir -p /etc/ssl/sos
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
        -keyout /etc/ssl/sos/key.pem -out /etc/ssl/sos/cert.pem -subj "/CN=$SNI" \
        -addext "subjectAltName=DNS:$SNI" >/dev/null 2>&1 || die "не удалось создать сертификат"
    chmod 600 /etc/ssl/sos/key.pem
    CERT=/etc/ssl/sos/cert.pem; KEY=/etc/ssl/sos/key.pem
    mkdir -p "$WORK/data/srv/site"
    echo '<!doctype html><title>Welcome</title><h1>It works</h1>' > "$WORK/data/srv/site/index.html"
    ok "ключи Reality и UUID созданы"; ok "сертификат для $SNI"
fi

# ================================================================ 4. nginx
step 4 "nginx — цель Reality на 127.0.0.1:8444"
if [ "$MODE" = owner ]; then
    rm -rf /etc/letsencrypt && cp -a "$WORK/data/etc/letsencrypt" /etc/letsencrypt
    chown -R root:root /etc/letsencrypt && chmod 700 /etc/letsencrypt/live /etc/letsencrypt/archive
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    printf '#!/bin/sh\nsystemctl reload nginx 2>/dev/null; systemctl restart x-ui 2>/dev/null\n' \
        > /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
    openssl x509 -checkend 86400 -noout -in "$CERT" >/dev/null \
        || die "сертификат $DOMAIN из снимка истёк ($(openssl x509 -enddate -noout -in "$CERT"))"
    systemctl enable -q --now certbot.timer 2>/dev/null || true
    ok "сертификат $DOMAIN до $(openssl x509 -enddate -noout -in "$CERT" | cut -d= -f2)"
fi
systemctl stop nginx 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default
mkdir -p /srv/site && cp -a "$WORK/data/srv/site/." /srv/site/ && chown -R root:root /srv/site && chmod -R a+rX /srv/site
cat > /etc/nginx/sites-available/reality-target <<EOF
server {
    listen 127.0.0.1:8444 ssl http2;
    server_name $SNI;
    ssl_certificate     $CERT;
    ssl_certificate_key $KEY;
    ssl_protocols TLSv1.3;
    ssl_ecdh_curve X25519:prime256v1;
    root /srv/site;
    index index.html;
}
EOF
ln -sf /etc/nginx/sites-available/reality-target /etc/nginx/sites-enabled/reality-target
nginx -t >"$WORK/nginx.log" 2>&1 || { cat "$WORK/nginx.log" >&2; die "конфиг nginx не прошёл проверку"; }
systemctl enable -q nginx && systemctl restart nginx
code=$(curl -sk -o /dev/null --max-time 5 --tlsv1.3 --resolve "$SNI:8444:127.0.0.1" -w '%{http_code}' "https://$SNI:8444/")
[ "$code" = 200 ] || die "nginx на 8444 ответил $code вместо 200"
ok "nginx отвечает 200 по TLS 1.3"

# ================================================================ 5. панель и Xray
step 5 "Панель и Xray"
systemctl stop x-ui 2>/dev/null || true
rm -rf /usr/local/x-ui && tar xzf "$TAR" -C /usr/local/ --no-same-owner
chmod +x /usr/local/x-ui/x-ui /usr/local/x-ui/x-ui.sh /usr/local/x-ui/bin/xray-linux-amd64
cp /usr/local/x-ui/x-ui.sh /usr/bin/x-ui && chmod +x /usr/bin/x-ui
cp /usr/local/x-ui/x-ui.service.debian /etc/systemd/system/x-ui.service
mkdir -p /etc/systemd/system/x-ui.service.d
printf '[Service]\nMemoryHigh=500M\n' > /etc/systemd/system/x-ui.service.d/memory.conf
mkdir -p /etc/x-ui && chmod 700 /etc/x-ui
rm -f /etc/x-ui/x-ui.db /etc/x-ui/x-ui.db-wal /etc/x-ui/x-ui.db-shm
systemctl daemon-reload
ok "панель распакована"

if [ "$MODE" = owner ]; then
    install -m 600 "$WORK/data/etc/x-ui/x-ui.db" /etc/x-ui/x-ui.db
    # Адрес и логин панели — из базы; пароль в базе хранится хешем, задаём новый.
    eval "$(python3 - <<'PY'
import sqlite3, re
c = sqlite3.connect("file:/etc/x-ui/x-ui.db?mode=ro", uri=True)
st = dict(c.execute("select key, value from settings where key in ('webPort','webBasePath','subPort')"))
user = c.execute("select username from users order by id limit 1").fetchone()[0]
path = (st.get("webBasePath") or "/").strip("/")
for v in (user, path):
    assert re.fullmatch(r"[A-Za-z0-9._-]*", v), "неожиданные символы в данных панели"
print(f"PANEL_USER={user}\nPANEL_PATH={path}\nPANEL_PORT={int(st.get('webPort') or 2053)}\nSUB_PORT={int(st.get('subPort') or 2096)}")
PY
)"
    PANEL_PASS=$(head -c 4000 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20)
    /usr/local/x-ui/x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" >/dev/null 2>&1 || die "не удалось задать пароль панели"
    EXTRA_PORTS="$SUB_PORT"
    ok "база панели восстановлена, новый пароль задан"
else
    /usr/local/x-ui/x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" -port "$PANEL_PORT" \
        -webBasePath "/$PANEL_PATH/" -webCert "$CERT" -webCertKey "$KEY" >/dev/null 2>&1 || die "не удалось задать настройки панели"
    EXTRA_PORTS=""
    ok "панель настроена"
fi
systemctl enable -q x-ui && systemctl restart x-ui
for i in $(seq 1 20); do ss -tlnH | grep -q ":$PANEL_PORT " && break; sleep 1; done
ss -tlnH | grep -q ":$PANEL_PORT " || { journalctl -u x-ui --no-pager -n 15 >&2; die "панель не слушает порт $PANEL_PORT"; }

if [ "$MODE" = new ]; then
    # Inbound и клиент — через API панели (токен выдаёт сама панель).
    TOKEN=$(/usr/local/x-ui/x-ui setting -getApiToken 2>/dev/null | grep -oE '[A-Za-z0-9_-]{32,}' | tail -1)
    [ -n "$TOKEN" ] || die "панель не выдала API-токен"
    api() { curl -sk --max-time 20 -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }
    BASE="https://127.0.0.1:$PANEL_PORT/$PANEL_PATH"
    SETTINGS='{"clients":[],"decryption":"none","fallbacks":[]}'
    STREAM=$(SNI=$SNI PRIV=$NEW_PRIV PUB=$NEW_PUB SID=$NEW_SID python3 -c "
import json,os
print(json.dumps({'network':'tcp','security':'reality','externalProxy':[],
 'realitySettings':{'show':False,'xver':0,'dest':'127.0.0.1:8444','target':'127.0.0.1:8444','serverNames':[os.environ['SNI']],
   'privateKey':os.environ['PRIV'],'minClient':'','maxClient':'','maxTimediff':0,'shortIds':[os.environ['SID']],
   'settings':{'publicKey':os.environ['PUB'],'fingerprint':'firefox','serverName':'','spiderX':'/'}},
 'tcpSettings':{'acceptProxyProtocol':False,'header':{'type':'none'}}}))")
    SNIFF='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'
    body=$(SETTINGS=$SETTINGS STREAM=$STREAM SNIFF=$SNIFF python3 -c "
import json,os
print(json.dumps({'up':0,'down':0,'total':0,'remark':'Wi-Fi Reality','enable':True,'expiryTime':0,'listen':'','port':443,
 'protocol':'vless','settings':os.environ['SETTINGS'],'streamSettings':os.environ['STREAM'],'sniffing':os.environ['SNIFF']}))")
    resp=$(api -X POST "$BASE/panel/api/inbounds/add" --data-binary "$body")
    grep -q '"success":true' <<<"$resp" || die "панель не создала inbound: $(cut -c1-200 <<<"$resp")"
    INBOUND_ID=$(python3 -c "import json,sys;print(json.loads(sys.argv[1])['obj']['id'])" "$resp")
    body=$(UUID=$NEW_UUID NAME=$CLIENT_NAME IID=$INBOUND_ID python3 -c "
import json,os
print(json.dumps({'client':{'id':os.environ['UUID'],'email':os.environ['NAME'],'enable':True,'flow':'xtls-rprx-vision',
 'limitIp':0,'totalGB':0,'expiryTime':0,'tgId':0,'subId':'','reset':0,'comment':''},'inboundIds':[int(os.environ['IID'])]}))")
    resp=$(api -X POST "$BASE/panel/api/clients/add" --data-binary "$body")
    grep -q '"success":true' <<<"$resp" || die "панель не создала клиента: $(cut -c1-200 <<<"$resp")"
    systemctl restart x-ui
    ok "inbound VLESS Reality :443 и клиент $CLIENT_NAME созданы"
fi
for i in $(seq 1 20); do ss -tlnH | grep -q ':443 ' && break; sleep 1; done
ss -tlnH | grep -q ':443 ' || { journalctl -u x-ui --no-pager -n 15 >&2; die "Xray не слушает порт 443"; }
ok "панель $(/usr/local/x-ui/x-ui -v 2>/dev/null) и Xray запущены"

ufw allow 22/tcp >/dev/null
for p in 80 443 "$PANEL_PORT" $EXTRA_PORTS; do ufw allow "$p/tcp" >/dev/null; done
ufw --force enable >/dev/null
ok "фаервол: 22, 80, 443, $PANEL_PORT${EXTRA_PORTS:+, $EXTRA_PORTS}"

# ================================================================ 6. проверка
step 6 "Проверка"
PUB_IP=${SELF_IP:-$(curl -4fsS --max-time 15 https://api.ipify.org 2>/dev/null || true)}
[[ "$PUB_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "не удалось узнать свой IP"
eval "$(PUB_IP=$PUB_IP CLIENT=$CLIENT MODE=$MODE python3 - <<'PY'
import json, os, urllib.parse, sqlite3
c = json.load(open("/usr/local/x-ui/bin/config.json"))
ib = next(i for i in c["inbounds"] if i.get("port") == 443 and (i.get("streamSettings") or {}).get("security") == "reality")
r = ib["streamSettings"]["realitySettings"]
db = sqlite3.connect("file:/etc/x-ui/x-ui.db?mode=ro", uri=True)
pub = json.loads(db.execute("select stream_settings from inbounds where port=443").fetchone()[0])["realitySettings"]["settings"]["publicKey"]
clients = ib["settings"]["clients"]
want = os.environ["CLIENT"].lower()
cl = next((x for x in clients if x.get("email", "").lower().startswith(want) and "mobile" not in x.get("email", "").lower()), None) \
     if os.environ["MODE"] == "owner" else clients[0]
assert cl, "клиент не найден: " + ", ".join(x.get("email", "") for x in clients)
q = {"type": "tcp", "security": "reality", "pbk": pub, "fp": "firefox", "sni": r["serverNames"][0],
     "sid": r["shortIds"][0], "spx": "/", "flow": cl.get("flow") or "xtls-rprx-vision"}
link = f"vless://{cl['id']}@{os.environ['PUB_IP']}:443?{urllib.parse.urlencode(q)}#{urllib.parse.quote('SOS-' + cl.get('email', 'client'))}"
print(f"LINK='{link}'\nLINK_NAME='{cl.get('email','')}'")
test = {"log": {"loglevel": "warning"},
        "inbounds": [{"listen": "127.0.0.1", "port": 19700, "protocol": "http"}],
        "outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": os.environ["PUB_IP"], "port": 443,
                       "users": [{"id": cl["id"], "encryption": "none", "flow": q["flow"]}]}]},
                       "streamSettings": {"network": "tcp", "security": "reality",
                                          "realitySettings": {"serverName": q["sni"], "publicKey": pub, "shortId": q["sid"],
                                                              "spiderX": "/", "fingerprint": "firefox"}}}]}
json.dump(test, open("/root/sos/selftest.json", "w"))
PY
)"
selftest() {
    /usr/local/x-ui/bin/xray-linux-amd64 run -config "$WORK/selftest.json" >/dev/null 2>&1 & local xp=$!; sleep 2
    OUT_IP=$(curl -s --max-time 20 --proxy http://127.0.0.1:19700 https://api.ipify.org || true)
    kill $xp 2>/dev/null || true; rm -f "$WORK/selftest.json"
    [[ "$OUT_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}
OUT_IP=""
if [ "$TTY" = 1 ]; then
    ( selftest; echo "$OUT_IP" > "$WORK/selftest.out" ) & sp=$!
    frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; i=0; printf '%s' "$HIDE"
    while kill -0 $sp 2>/dev/null; do printf '\r  %s%s%s подключаюсь через %s:443 как настоящий клиент' "$MAG" "${frames:i%10:1}" "$R" "$PUB_IP"; i=$((i+1)); sleep 0.1; done
    wait $sp || true; printf '\r\e[K%s' "$SHOW"
    OUT_IP=$(cat "$WORK/selftest.out" 2>/dev/null || true); rm -f "$WORK/selftest.out"
else
    selftest || true
fi
if [[ "$OUT_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    VLESS_OK=yes; ok "VLESS Reality через $PUB_IP:443 ${GRN}${B}РАБОТАЕТ${R} (выход $OUT_IP)"
else
    VLESS_OK=no; warn "VLESS Reality через $PUB_IP:443 ${RED}${B}НЕ ПРОШЁЛ ПРОВЕРКУ${R}"
fi

# ================================================================ DNS (только владелец)
DNS_DONE=no
if [ "$MODE" = owner ] && [ "$VLESS_OK" = yes ] && [ "$DNS" != no ]; then
    if [ "$DNS" = ask ] && [ -t 0 ]; then
        ask "Переключить $DOMAIN на $PUB_IP?" "все устройства с профилем $([ "$SOURCE" = lon ] && echo London || echo Bucharest) пойдут через этот сервер — да/нет"
        case "$REPLY" in да|Да|ДА|y|Y|yes) DNS=yes ;; *) DNS=no ;; esac
    fi
    if [ "$DNS" = yes ]; then
        [ -n "${CF_TOKEN:-}" ] || die "в снимке нет токена Cloudflare"
        if CF_TOKEN=$CF_TOKEN DOMAIN=$DOMAIN ZONE=$ZONE IP=$PUB_IP python3 - <<'PY'
import json, os, urllib.request
tok, dom, zone, ip = (os.environ[k] for k in ("CF_TOKEN", "DOMAIN", "ZONE", "IP"))
def cf(url, data=None, method="GET"):
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data else None, method=method,
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=20))
zid = cf(f"https://api.cloudflare.com/client/v4/zones?name={zone}")["result"][0]["id"]
rec = cf(f"https://api.cloudflare.com/client/v4/zones/{zid}/dns_records?type=A&name={dom}")["result"][0]
r = cf(f"https://api.cloudflare.com/client/v4/zones/{zid}/dns_records/{rec['id']}",
       {"type": "A", "name": dom, "content": ip, "ttl": 60, "proxied": False}, "PUT")
assert r["success"], r
print(f"  ✔ DNS: {dom}  {rec['content']} -> {ip}  (старый адрес {rec['content']})")
PY
        then DNS_DONE=yes; else warn "DNS переключить не удалось"; fi
    fi
fi
progress $STEPS

# ================================================================ итог
rm -rf "$WORK/data" "$WORK/xui-tmp" "$WORK/bundle.enc"
PANEL_HOST=$PUB_IP; [ "$DNS_DONE" = yes ] && PANEL_HOST=$DOMAIN
MODE_T=$([ "$MODE" = owner ] && echo "копия $([ "$SOURCE" = lon ] && echo London || echo Bucharest)" || echo "новый пользователь")
VL_T=$([ "$VLESS_OK" = yes ] && echo "${GRN}${B}РАБОТАЕТ${R}" || echo "${RED}${B}НЕ ПРОШЁЛ ПРОВЕРКУ${R}")
lines=( "$(kv 'Сервер' "$PUB_IP  ${D}($MODE_T)${R}")" "$(kv 'VLESS' "$VL_T")" )
[ "$MODE" = owner ] && lines+=( "$(kv 'DNS' "$([ "$DNS_DONE" = yes ] && echo "$DOMAIN → $PUB_IP" || echo 'не менялся')")" )
lines+=( "" "$(kv 'Панель' "${CYN}https://$PANEL_HOST:$PANEL_PORT/$PANEL_PATH/${R}")"
         "$(kv '' "${D}браузер предупредит о сертификате — это нормально${R}")"
         "$(kv 'Логин' "${B}$PANEL_USER${R}")" "$(kv 'Пароль' "${B}$PANEL_PASS${R}")" )
card "ГОТОВО за $(elapsed)" "${lines[@]}"
printf '\n  %s%sСсылка (%s)%s — вставить в v2rayN / Hiddify / v2rayNG:%s\n\n' "$WHT" "$B" "$LINK_NAME" "$R$D" "$R"
printf '  %s%s%s\n' "$YEL" "$LINK" "$R"
{
    echo "Сервер:   $PUB_IP   режим: $MODE_T"
    echo "VLESS:    $([ "$VLESS_OK" = yes ] && echo РАБОТАЕТ || echo 'НЕ ПРОШЁЛ ПРОВЕРКУ')"
    [ "$MODE" = owner ] && echo "DNS:      $([ "$DNS_DONE" = yes ] && echo "$DOMAIN -> $PUB_IP" || echo 'не менялся')"
    echo "Панель:   https://$PANEL_HOST:$PANEL_PORT/$PANEL_PATH/"
    echo "Логин:    $PANEL_USER"
    echo "Пароль:   $PANEL_PASS"
    echo "Ссылка ($LINK_NAME):"
    echo "$LINK"
} > "$RESULT"
chmod 600 "$RESULT"
if command -v qrencode >/dev/null && [ "$TTY" = 1 ]; then printf '\n  %sQR для телефона:%s\n' "$D" "$R"; qrencode -t ANSIUTF8 -m 2 "$LINK" | sed 's/^/  /'; fi
printf '\n  %sИтог сохранён в %s%s\n\n' "$D" "$RESULT" "$R"
[ "$VLESS_OK" = yes ] || exit 3
