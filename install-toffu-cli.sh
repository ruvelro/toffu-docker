#!/usr/bin/env bash
set -e

IMAGE_NAME="ruvelro/toffu-docker"
BASE_DIR="$(pwd)"
LOCAL_BIN="$HOME/.local/bin"
WRAPPER_PATH="$LOCAL_BIN/toffu-docker"

echo "== Toffu Docker CLI =="
echo "Directorio de trabajo: $BASE_DIR"
echo

mkdir -p "$LOCAL_BIN"

# Añadir ~/.local/bin al PATH si no está
if ! echo "$PATH" | grep -q "$LOCAL_BIN" ; then
  echo "Añadiendo $LOCAL_BIN al PATH en ~/.bashrc ..."
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.local/bin:$PATH"
fi

# 1. Comprobar Docker
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker no está instalado o no está en el PATH."
  exit 1
fi

ask_overwrite() {
  FILE="$1"
  if [ -f "$FILE" ]; then
    echo "El archivo $FILE ya existe. ¿Quieres sobrescribirlo? (s/n) "
    read -r ANSWER
    if [ "$ANSWER" = "s" ] || [ "$ANSWER" = "S" ]; then
      return 0   # Sobrescribir
    else
      return 1   # Conservar
    fi
  fi
  return 0
}

# 2. Dockerfile
if ask_overwrite "$BASE_DIR/Dockerfile"; then
  echo "Creando Dockerfile..."
  cat > "$BASE_DIR/Dockerfile" <<"EOF"
FROM golang:1.22-bookworm AS builder

RUN apt-get update && apt-get install -y git make

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
else
  echo "Conservando Dockerfile existente."
fi

# 3. entrypoint.sh
if ask_overwrite "$BASE_DIR/entrypoint.sh"; then
  echo "Creando entrypoint.sh..."
  cat > "$BASE_DIR/entrypoint.sh" <<"EOF"
#!/bin/sh
set -e

CREDS_FILE="/work/toffu-credentials.json"
TOKEN_DIR="/root/.toffu"
TOKEN_FILE="$TOKEN_DIR/toffu.json"

if [ ! -f "$CREDS_FILE" ]; then
  echo "ERROR: No se encuentra $CREDS_FILE" >&2
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
else
  echo "Conservando entrypoint.sh existente."
fi

# 4. Build con --no-cache para FORZAR reconstrucción completa
echo
echo "Construyendo imagen Docker (sin caché): $IMAGE_NAME ..."
docker build --no-cache -t "$IMAGE_NAME" "$BASE_DIR"

# 5. Pedir credenciales
CREDS_FILE="$BASE_DIR/toffu-credentials.json"

if ask_overwrite "$CREDS_FILE"; then
  echo
  echo "Introduce tus credenciales de Woffu:"
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
else
  echo "Conservando toffu-credentials.json existente."
fi

# 6. Wrapper toffu-docker en ~/.local/bin/
echo
echo "Instalando wrapper en $WRAPPER_PATH ..."
cat > "$WRAPPER_PATH" <<EOF
#!/bin/sh
BASE_DIR="$BASE_DIR"
IMAGE_NAME="$IMAGE_NAME"

docker run --rm \
  -v "\$BASE_DIR:/work" \
  "\$IMAGE_NAME" "\$@"
EOF

chmod +x "$WRAPPER_PATH"

echo
echo "Instalación completada."
echo "Ejemplos de uso:"
echo "  toffu-docker status"
echo "  toffu-docker in"
echo "  toffu-docker out"
