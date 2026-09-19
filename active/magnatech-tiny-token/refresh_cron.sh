#!/usr/bin/env bash
# refresh_cron.sh — renovacao horaria do token Tiny da Magnatech (paliativo local).
# Roda tiny_token.sh refresh de forma nao-interativa: le o CLIENT_SECRET de um
# arquivo 600 e injeta via TINY_CLIENT_SECRET, entao o refresh nao pergunta nada.
# Temporario: some quando o integrator-magnatech subir e a renovacao virar job de infra.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
secret_file="${TINY_SECRET_FILE:-$HOME/.magnatech_tiny_secret}"
log_file="${TINY_REFRESH_LOG:-$HOME/.magnatech_tiny_refresh.log}"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }

if [ ! -f "$secret_file" ]; then
  printf '%s FALHOU: arquivo de secret nao encontrado em %s\n' "$(stamp)" "$secret_file" >> "$log_file"
  exit 1
fi

export TINY_CLIENT_SECRET="$(cat "$secret_file")"

if bash "$script_dir/tiny_token.sh" refresh >> "$log_file" 2>&1; then
  printf '%s OK: token renovado\n' "$(stamp)" >> "$log_file"
else
  printf '%s FALHOU: o refresh retornou erro — o refresh token pode ter expirado; reautorizar com a Bruna (authorize-url + exchange de novo)\n' "$(stamp)" >> "$log_file"
  exit 1
fi
