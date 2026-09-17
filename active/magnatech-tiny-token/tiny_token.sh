#!/usr/bin/env bash
# tiny_token.sh — OAuth2 (Authorization Code) da API Tiny v3 / Olist para a Magnatech.
#
# Fluxo do Tiny: um humano dono da conta (a Bruna) autoriza o app no navegador,
# o que gera um `code` de uso único e curto. Trocamos o `code` por um par
# access_token (~4h) + refresh_token (~24h). Enquanto renovarmos dentro das 24h,
# a corrente vive; se lapsar, tem que reautorizar com a Bruna de novo.
#
# Uso:
#   bash tiny_token.sh authorize-url    # imprime a URL para mandar pra Bruna
#   bash tiny_token.sh exchange         # troca o code pelos tokens e salva (pergunta o code e o secret)
#   bash tiny_token.sh refresh          # renova usando o refresh_token salvo
#   bash tiny_token.sh test             # bate na API v3 (leitura) com o access_token salvo
#
# Segredos: o CLIENT_SECRET nunca fica no script. É lido do ambiente
# (TINY_CLIENT_SECRET) ou perguntado com `read -rs`. Os tokens são salvos com
# permissão 600 e nunca impressos.
#
# CONFIRMAR antes de usar: CLIENT_ID e REDIRECT_URI têm que ser IDÊNTICOS aos
# registrados no app "4Shark Integrator" dentro do Tiny. Os valores abaixo são
# os do registro de ab/2026 (do histórico); se o app foi recriado, sobrescreva
# via env TINY_CLIENT_ID / TINY_REDIRECT_URI.

set -euo pipefail

CLIENT_ID="${TINY_CLIENT_ID:-tiny-api-3e15fb0a0260332659f34add29f875a93adf6828-1776193439}"
REDIRECT_URI="${TINY_REDIRECT_URI:-http://localhost:8080/oauth/tiny/callback}"
AUTH_BASE="https://accounts.tiny.com.br/realms/tiny/protocol/openid-connect"
API_BASE="https://api.tiny.com.br/public-api/v3"
TOKEN_FILE="${TINY_TOKEN_FILE:-$HOME/.magnatech_tiny_tokens}"

urlencode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

read_secret() {
  if [ -n "${TINY_CLIENT_SECRET:-}" ]; then
    client_secret="$TINY_CLIENT_SECRET"
    return
  fi
  printf 'CLIENT_SECRET do app Tiny (não aparece na tela): ' >&2
  read -rs client_secret
  printf '\n' >&2
}

save_tokens() {
  response_json="$1"
  mkdir -p "$(dirname "$TOKEN_FILE")"
  umask 077
  python3 - "$TOKEN_FILE" <<'PY'
import json, sys, time
token_file = sys.argv[1]
data = json.load(sys.stdin)
now = int(time.time())
lines = [
    f'TINY_ACCESS_TOKEN={data["access_token"]}',
    f'TINY_REFRESH_TOKEN={data["refresh_token"]}',
    f'TINY_ACCESS_EXPIRES_AT={now + int(data.get("expires_in", 0))}',
    f'TINY_REFRESH_EXPIRES_AT={now + int(data.get("refresh_expires_in", 0))}',
    f'TINY_OBTAINED_AT={now}',
]
with open(token_file, 'w') as handle:
    handle.write('\n'.join(lines) + '\n')
print(f'access expira em ~{int(data.get("expires_in",0))//60} min, refresh em ~{int(data.get("refresh_expires_in",0))//3600}h')
PY
}

cmd_authorize_url() {
  encoded_redirect="$(urlencode "$REDIRECT_URI")"
  printf 'Mande esta URL para a Bruna abrir logada na conta Tiny da Magnatech:\n\n'
  printf '%s/auth?response_type=code&client_id=%s&redirect_uri=%s\n\n' "$AUTH_BASE" "$CLIENT_ID" "$encoded_redirect"
  printf 'Depois de autorizar, ela é redirecionada para o redirect_uri com ?code=... na barra.\n'
  printf 'Peça para ela copiar SÓ o valor do code e te mandar. Ele expira em segundos — troque rápido.\n'
}

cmd_exchange() {
  code="${1:-}"
  if [ -z "$code" ]; then
    printf 'Cole o code que a Bruna te passou: ' >&2
    read -r code
  fi
  read_secret
  response_json="$(curl -sS -X POST "$AUTH_BASE/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=authorization_code' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_secret=$client_secret" \
    --data-urlencode "redirect_uri=$REDIRECT_URI" \
    --data-urlencode "code=$code")"
  if printf '%s' "$response_json" | grep -q '"access_token"'; then
    save_tokens "$response_json"
    printf 'OK — tokens salvos em %s\n' "$TOKEN_FILE"
  else
    printf 'FALHOU. Resposta do Tiny:\n%s\n' "$response_json" >&2
    exit 1
  fi
}

cmd_refresh() {
  # shellcheck disable=SC1090
  . "$TOKEN_FILE"
  read_secret
  response_json="$(curl -sS -X POST "$AUTH_BASE/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=refresh_token' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "client_secret=$client_secret" \
    --data-urlencode "refresh_token=$TINY_REFRESH_TOKEN")"
  if printf '%s' "$response_json" | grep -q '"access_token"'; then
    save_tokens "$response_json"
    printf 'OK — tokens renovados em %s\n' "$TOKEN_FILE"
  else
    printf 'FALHOU (refresh provavelmente expirou — reautorizar com a Bruna). Resposta:\n%s\n' "$response_json" >&2
    exit 1
  fi
}

cmd_test() {
  # shellcheck disable=SC1090
  . "$TOKEN_FILE"
  printf 'GET %s/produtos?limit=1 (leitura de produtos)\n' "$API_BASE"
  curl -sS -o /dev/null -w 'HTTP %{http_code}\n' \
    -H "Authorization: Bearer $TINY_ACCESS_TOKEN" \
    -H 'Content-Type: application/json' \
    "$API_BASE/produtos?limit=1"
}

case "${1:-}" in
  authorize-url) cmd_authorize_url ;;
  exchange) shift; cmd_exchange "${1:-}" ;;
  refresh) cmd_refresh ;;
  test) cmd_test ;;
  *) printf 'uso: bash tiny_token.sh {authorize-url|exchange|refresh|test}\n' >&2; exit 2 ;;
esac
