#!/usr/bin/env bash
# Probe listed sites from the host that runs this script (HTTPS, follows redirects).
# Usage: check-ru-websites.sh [--timeout SECONDS] [--insecure]
set -u
set -o pipefail

usage() {
  printf '%s\n' "Usage: ${0##*/} [--timeout SECONDS] [--insecure]" >&2
  printf '%s\n' "  --timeout   Connect + transfer limit per site (default: 20)" >&2
  printf '%s\n' "  --insecure  Pass -k to curl (skip TLS certificate verification)" >&2
}

insecure=0
max_time=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --insecure)
      insecure=1
      shift
      ;;
    --timeout)
      if [[ -z ${2-} ]]; then
        printf '%s\n' "Error: --timeout needs a value" >&2
        exit 1
      fi
      max_time="$2"
      shift 2
      ;;
    *)
      printf '%s\n' "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' "Error: curl is not installed" >&2
  exit 1
fi

# Sites to check (no scheme — HTTPS is used)
readarray -t sites <<'SITES'
vk.ru
hh.ru
avito.ru
2gis.ru
dzen.ru
mail.ru
rambler.ru
max.ru
ok.ru
nalog.ru
pochta.ru
rutube.ru
sberbank.ru
SITES

curl_insecure=()
if [[ "$insecure" -eq 1 ]]; then
  curl_insecure=(-k)
fi

check_one() {
  local host=$1
  local url="https://${host}/"
  local code stderr err rc
  stderr=$(mktemp) || { printf 'FAIL %-20s  mktemp failed\n' "$host"; return 1; }
  # -L: follow redirects; -sS: silent but surface errors; -w: last response code
  code=$(
    curl "${curl_insecure[@]}" -sS -L -o /dev/null -w '%{http_code}' \
      --connect-timeout 10 --max-time "$max_time" \
      --user-agent "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
      "$url" 2>"$stderr"
  )
  rc=$?
  if (( rc == 0 )); then
    rm -f -- "$stderr"
    if [[ -n "$code" && "$code" =~ ^[0-9]{3}$ ]]; then
      if (( code >= 200 && code < 400 )); then
        printf 'OK   %-20s  HTTP %s\n' "$host" "$code"
        return 0
      fi
      printf 'WARN %-20s  HTTP %s (not 2xx/3xx)\n' "$host" "$code"
      return 1
    fi
    printf 'FAIL %-20s  no HTTP code in response\n' "$host"
    return 1
  fi
  err=$(tr -d '\r' <"$stderr" | head -c 200)
  rm -f -- "$stderr"
  if [[ -z "$err" ]]; then
    err="curl failed (rc=${rc}, last code: ${code:-?})"
  fi
  printf 'FAIL %-20s  %s\n' "$host" "$err"
  return 1
}

printf '%s\n' "From: $(hostname -f 2>/dev/null || hostname)  |  max-time: ${max_time}s  |  ${#sites[@]} host(s)"
printf '%s\n' "----"

ok=0
for host in "${sites[@]}"; do
  if check_one "$host"; then
    ((ok++)) || true
  fi
done

printf '%s\n' "----"
printf 'Summary: %d/%d reachable with HTTP 2xx/3xx\n' "$ok" "${#sites[@]}"
# Exit 0 if all ok, 1 if any failed
if [[ "$ok" -eq "${#sites[@]}" ]]; then
  exit 0
fi
exit 1
