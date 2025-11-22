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

# Asegurar PATH
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.local/bin:$PATH"
fi

# Detectar si hay TTY para decidir si preguntar o no
has_tty() {
  [ -t 0 ]
}

ask_overwrite() {
  FILE="$1"

  # No existe -> crear sin preguntar
  if [ ! -f "$FILE" ]; then
    return 0
  fi

  # Si NO hay TTY (curl | bash) -> sobrescribir siempre
  if ! has_tty; then
    echo "Sobrescribiendo $FILE (ejecución no interactiva)."
    return 0
  fi

  # Modo interactivo: pedir confirmación
  echo -n "El archivo $FILE ya existe. ¿Quieres sobrescribirlo? (s/n) "
  read -r ANSWER
  if [ "$ANSWER" = "s" ] || [ "$ANSWER" = "S" ]; then
    return 0
  else
    return 1
  fi
}

# ---------------------------------------------------------
# 1. Dockerfile
# ---------------------------------------------------------
if ask_overwrite "$BASE_DIR/Dockerfile"; then
  echo "Creando Dockerfile..."
  cat > "$BASE_DIR/Dockerfile" <<"EOF"
# -------------------------
# Stage 1: build (Go + make) desde Quay.io
# -------------------------
FROM quay.io/toolbx-images/golang:1.22 AS builder

RUN apt-get update && apt-get install -y git make

WORKDIR /src
RUN git clone https://github.com/ruvelro/toffu-docker.git .
RUN make install

# -------------------------
# Stage 2: runtime mínimo (Alpine desde Quay)
# -------------------------
FROM quay.io/toolbx-images/alpine:latest

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

# ---------------------------------------------------------
# 2. entrypoint.sh
# ---------------------------------------------------------
if ask_overwrite "$BASE_DIR/entrypoint.sh"; then
  echo "Creando entrypoint.sh..."
  cat > "$BASE_DIR/entrypoint.sh" <<"EOF"
#!/bin/sh
set -e

CREDS_FILE="/work/toffu-credentials.json"
TOKEN_DIR="/root/.toffu"
TOKEN_FILE="$TOKEN_DIR/toffu.json"

USERNAME=$(jq -r '.username' "$CREDS_FILE")
PASSWORD=$(jq -r '.password' "$CREDS_FILE")

mkdir -p "$TOKEN_DIR"

TOKEN=$(curl -s -d "grant_type=password&username=$USERNAME&password=$PASSWORD" \
  https://app.woffu.com/token | jq -r '.access_token')

printf '{ "debug": false, "woffu_token": "%s" }' "$TOKEN" > "$TOKEN_FILE"

exec toffu "$@"
EOF

  chmod +x "$BASE_DIR/entrypoint.sh"
else
  echo "Conservando entrypoint.sh existente."
fi

# ---------------------------------------------------------
# 3. Build sin caché
# ---------------------------------------------------------
echo
echo "Construyendo imagen Docker (sin caché): $IMAGE_NAME ..."
docker build --no-cache -t "$IMAGE_NAME" "$BASE_DIR"

# ---------------------------------------------------------
# 4. Credenciales
# ---------------------------------------------------------
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
fi

# ---------------------------------------------------------
# 5. Wrapper (sin sudo)
# ---------------------------------------------------------
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
echo "Ejemplos:"
echo "  toffu-docker status"
echo "  toffu-docker in"
echo "  toffu-docker out"
