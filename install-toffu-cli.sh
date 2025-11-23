#!/usr/bin/env bash
set -e

IMAGE_NAME="ruvelro/toffu-docker"
BASE_DIR="$(pwd)"
LOCAL_BIN="$HOME/.local/bin"
WRAPPER_PATH="$LOCAL_BIN/toffu-docker"

USER="$1"
PASS="$2"

echo "== Toffu Docker CLI =="
echo "Directorio de trabajo: $BASE_DIR"
echo

mkdir -p "$LOCAL_BIN"

if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.local/bin:$PATH"
fi

# Detectar si hay TTY
has_tty() {
  [ -t 0 ]
}

# ------------------------------------------
# 1. Obtener credenciales
# ------------------------------------------
if [ -n "$USER" ] && [ -n "$PASS" ]; then
  echo "Usando credenciales pasadas como parámetros."
else
  if has_tty; then
    echo "No se han pasado credenciales. Introduce los datos manualmente:"
    read -rp "Email de Woffu: " USER
    read -rsp "Contraseña de Woffu: " PASS
    echo
  else
    echo "ERROR: No se han pasado credenciales y no hay TTY para pedirlas."
    echo "Ejemplo de uso automático:"
    echo "  curl -s https://.../install.sh | bash -s -- user@correo.com password"
    exit 1
  fi
fi

CREDS_FILE="$BASE_DIR/toffu-credentials.json"

cat > "$CREDS_FILE" <<EOF
{
  "username": "$USER",
  "password": "$PASS"
}
EOF

echo "Credenciales guardadas en $CREDS_FILE"
echo

# ------------------------------------------
# 2. Crear Dockerfile (versión original)
# ------------------------------------------
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

# ------------------------------------------
# 3. entrypoint.sh
# ------------------------------------------
cat > "$BASE_DIR/entrypoint.sh" <<"EOF"
#!/bin/sh
set -e

CREDS_FILE="/work/toffu-credentials.json"
TOKEN_DIR="/root/.toffu"
TOKEN_FILE="$TOKEN_DIR/toffu.json"

USERNAME=$(jq -r '.username' "$CREDS_FILE")
PASSWORD=$(jq -r '.password' "$CREDS_FILE")

mkdir -p "$TOKEN_DIR"

TOKEN=$(curl -s \
  -d "grant_type=password&username=$USERNAME&password=$PASSWORD" \
  https://app.woffu.com/token \
  | jq -r '.access_token')

printf '{ "debug": false, "woffu_token": "%s" }' "$TOKEN" > "$TOKEN_FILE"

exec toffu "$@"
EOF

chmod +x "$BASE_DIR/entrypoint.sh"

# ------------------------------------------
# 4. Build sin caché
# ------------------------------------------
echo "Construyendo imagen Docker..."
docker build --no-cache -t "$IMAGE_NAME" "$BASE_DIR"

# ------------------------------------------
# 5. Wrapper
# ------------------------------------------
echo "Instalando wrapper en $WRAPPER_PATH..."
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
echo
echo "Ejemplos:"
echo "  toffu-docker status"
echo "  toffu-docker in"
echo "  toffu-docker out"
