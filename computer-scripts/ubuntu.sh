#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Wyszukanie pliku hostbook.env w katalogu Home.Configuration
CANDIDATE_PATHS=(
  "$SCRIPT_DIR/../../Home.Configuration/hostbook.env"
  "$SCRIPT_DIR/../../github/Home.Configuration/hostbook.env"
  "$SCRIPT_DIR/../Home.Configuration/hostbook.env"
  "$HOME/Home.Configuration/hostbook.env"
  "$HOME/github/Home.Configuration/hostbook.env"
)

ENV_FILE=""
for p in "${CANDIDATE_PATHS[@]}"; do
  if [[ -f "$p" ]]; then
    ENV_FILE="$p"
    break
  fi
done

if [[ -z "$ENV_FILE" ]]; then
  echo "Blad: Nie znaleziono pliku hostbook.env w katalogu Home.Configuration." >&2
  exit 1
fi

# Wczytanie zmiennych z obsługą ewentualnych znaków końca linii Windows (\r)
while IFS='=' read -r key value || [[ -n "$key" ]]; do
  key="$(echo "$key" | tr -d '\r' | xargs)"
  value="$(echo "${value:-}" | tr -d '\r' | xargs)"
  if [[ -n "$key" && ! "$key" =~ ^# ]]; then
    export "$key=$value"
  fi
done < "$ENV_FILE"

API_KEY="${FIREBASE_API_KEY}"
DB_URL="${FIREBASE_DB_URL%/}"
EMAIL="${FIREBASE_EMAIL}"
PASSWORD="${FIREBASE_PASSWORD}"

# 2. Pobranie wszystkich aktywnych adresów IPv4 (poza 127.0.0.1 i 169.254.x.x)
mapfile -t LOCAL_IPS < <(
  ip -4 -o addr show scope global 2>/dev/null |
    awk '{split($4, a, "/"); if (a[1] !~ /^127\./ && a[1] !~ /^169\.254\./) print a[1]}'
)

if [[ ${#LOCAL_IPS[@]} -eq 0 ]]; then
  echo "Brak aktywnych adresow IP - pomijam wysylke."
  exit 0
fi

HOSTNAME_VAL="$(hostname)"
HOST_KEY="$(echo "$HOSTNAME_VAL" | tr '[:upper:]' '[:lower:]' | sed 's/[.#$\[\]\/]/-/g')"

# 3. Pobranie czasu działania (Uptime) oraz czasu uruchomienia (bootTime)
UPTIME_SECONDS="$(awk '{print int($1)}' /proc/uptime)"
DAYS=$((UPTIME_SECONDS / 86400))
HOURS=$(((UPTIME_SECONDS % 86400) / 3600))
MINUTES=$(((UPTIME_SECONDS % 3600) / 60))
UPTIME_STR="$(printf "%dd %02dh %02dm" "$DAYS" "$HOURS" "$MINUTES")"
BOOT_TIME="$(uptime -s 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')"
UPDATED_AT="$(date '+%Y-%m-%d %H:%M:%S')"

# 4. Pobranie tokenu (idToken) z Firebase Auth
AUTH_URL="https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}"
AUTH_BODY="$(printf '{"email":"%s","password":"%s","returnSecureToken":true}' "$EMAIL" "$PASSWORD")"

AUTH_RESPONSE="$(curl -sS -f -X POST "$AUTH_URL" \
  -H "Content-Type: application/json" \
  -d "$AUTH_BODY")"

ID_TOKEN="$(echo "$AUTH_RESPONSE" | sed -n 's/.*"idToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

if [[ -z "$ID_TOKEN" ]]; then
  echo "Blad: Nie udalo sie pobrac idToken z Firebase Auth." >&2
  exit 1
fi

# 5. Budowa tablicy JSON dla adresów IP i wysłanie danych (PUT) do Firebase
IPS_JSON="["
for i in "${!LOCAL_IPS[@]}"; do
  [[ $i -gt 0 ]] && IPS_JSON+=","
  IPS_JSON+="\"${LOCAL_IPS[$i]}\""
done
IPS_JSON+="]"

PAYLOAD="$(printf '{"hostname":"%s","ips":%s,"os":"ubuntu","uptime":"%s","bootTime":"%s","updatedAt":"%s"}' \
  "$HOSTNAME_VAL" "$IPS_JSON" "$UPTIME_STR" "$BOOT_TIME" "$UPDATED_AT")"

REPORT_URL="${DB_URL}/hosts/${HOST_KEY}.json?auth=${ID_TOKEN}"

curl -sS -f -X PUT "$REPORT_URL" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "$PAYLOAD" > /dev/null

echo "OK: Zaktualizowano $HOSTNAME_VAL (${LOCAL_IPS[*]}) - Uptime: $UPTIME_STR"
