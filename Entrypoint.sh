#!/bin/sh
set -e

CREDS_FILE="/work/toffu-credentials.json"
TOKEN_DIR="/root/.toffu"
TOKEN_FILE="$TOKEN_DIR/toffu.json"

if [ ! -f "$CREDS_FILE" ]; then
  echo "ERROR: No se encuentra $CREDS_FILE" >&2
  echo "Crea un fichero toffu-credentials.json con:" >&2
  echo '{ "username": "TU_EMAIL", "password": "TU_PASSWORD" }' >&2
  exit 1
fi

USERNAME=$(jq -r '.username' "$CREDS_FILE")
PASSWORD=$(jq -r '.password' "$CREDS_FILE")

if [ -z "$USERNAME" ] || [ "$USERNAME" = "null" ] || \
   [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then
  echo "ERROR: username o password inválidos en $CREDS_FILE" >&2
  exit 1
fi

mkdir -p "$TOKEN_DIR"

echo ">> Obteniendo token de Woffu..."
TOKEN=$(curl -s \
   -d "grant_type=password&username=$USERNAME&password=$PASSWORD" \
   https://app.woffu.com/token | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: no se pudo obtener token de Woffu" >&2
  exit 1
fi

# Escribimos el archivo de configuración que espera toffu
printf '{\n  "debug": false,\n  "woffu_token": "%s"\n}\n' "$TOKEN" > "$TOKEN_FILE"

# Ejecutamos toffu con los argumentos que haya recibido el contenedor
exec toffu "$@"
