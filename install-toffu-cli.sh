#!/usr/bin/env bash
set -e

IMAGE_NAME="ruvelro/toffu-docker"
BASE_DIR="$(pwd)"

echo "== Toffu Docker CLI =="
echo "Directorio de trabajo: $BASE_DIR"
echo

# 1. Comprobar Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker no está instalado o no está en el PATH."
  echo "Instálalo manualmente y vuelve a ejecutar este script."
  exit 1
fi

# 2. Crear Dockerfile si no existe
if [ -f "$BASE_DIR/Dockerfile" ]; then
  echo "Dockerfile ya existe, no se sobreescribe."
else
  echo "Creando Dockerfile..."
  cat > "$BASE_DIR/Dockerfile" <<"EOF"
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git make

WORKDIR /src
RUN git clone https://github.com/ruvelro/toffu-docker.git .
RUN make install

FROM alpine:latest

RUN apk add --no-cache \
      ca-certificates \
      curl \
      jq \
      tzdata && \
    update-ca-certificates

ENV TZ=Europe/Madrid
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY --from=builder /usr/local/bin/toffu /usr/local/bin/toffu
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /root
ENTRYPOINT ["/entrypoint.sh"]
EOF
fi

# 3. Crear entrypoint.sh si no existe
if [ -f "$BASE_DIR/entrypoint.sh" ]; then
  echo "entrypoint.sh ya existe, no se sobreescribe."
else
  echo "Creando entrypoint.sh..."
  cat > "$BASE_DIR/entrypoint.sh" <<"EOF"
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

printf '{\n  "debug": false,\n  "woffu_token": "%s"\n}\n' "$TOKEN" > "$TOKEN_FILE"

exec toffu "$@"
EOF

  chmod +x "$BASE_DIR/entrypoint.sh"
fi

# 4. Construir imagen
echo
echo "Construyendo imagen Docker: $IMAGE_NAME ..."
docker build -t "$IMAGE_NAME" "$BASE_DIR"

# 5. Pedir credenciales y crear toffu-credentials.json
CREDS_FILE="$BASE_DIR/toffu-credentials.json"
if [ -f "$CREDS_FILE" ]; then
  echo
  echo "toffu-credentials.json ya existe, no se sobreescribe."
else
  echo
  echo "Introduce tus credenciales de Woffu (solo se guardarán en este directorio)."
  read -rp "Email de Woffu: " WOFFU_USERNAME
  read -rsp "Contraseña de Woffu: " WOFFU_PASSWORD
  echo

  cat > "$CREDS_FILE" <<EOF
{
  "username": "$WOFFU_USERNAME",
  "password": "$WOFFU_PASSWORD"
}
EOF

  echo "Creado $CREDS_FILE"
fi

# 6. Crear wrapper en /usr/local/bin/toffu-docker
WRAPPER_PATH="/usr/local/bin/toffu-docker"
if [ -f "$WRAPPER_PATH" ]; then
  echo
  echo "$WRAPPER_PATH ya existe, no se sobreescribe."
else
  echo
  echo "Instalando wrapper en $WRAPPER_PATH (puede pedir sudo)..."
  sudo sh -c "cat > '$WRAPPER_PATH'" <<EOF
#!/bin/sh
BASE_DIR="$BASE_DIR"
IMAGE_NAME="$IMAGE_NAME"

docker run --rm \\
  -v "\$BASE_DIR:/work" \\
  "\$IMAGE_NAME" "\$@"
EOF

  sudo chmod +x "$WRAPPER_PATH"
  echo "Wrapper instalado: $WRAPPER_PATH"
fi

echo
echo "Instalación completada."
echo "Ejemplos de uso:"
echo "  toffu-docker status"
echo "  toffu-docker in"
echo "  toffu-docker out"
