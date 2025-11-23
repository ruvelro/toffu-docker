#!/usr/bin/env bash
set -e

# -----------------------------------------------------
# COLORES
# -----------------------------------------------------
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RESET="\033[0m"

IMAGE_NAME="ruvelro/toffu-docker"
BASE_DIR="$(pwd)"
LOCAL_BIN="$HOME/.local/bin"
WRAPPER_PATH="$LOCAL_BIN/toffu-docker"

USER="$1"
PASS="$2"

echo -e "${BLUE}== Toffu Docker CLI ==${RESET}"
echo "Directorio de trabajo: $BASE_DIR"
echo

mkdir -p "$LOCAL_BIN"

if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.local/bin:$PATH"
fi

has_tty() {
  [ -t 0 ]
}

# -----------------------------------------------------
# 1. CREDENCIALES
# -----------------------------------------------------
if [ -n "$USER" ] && [ -n "$PASS" ]; then
  echo -e "${GREEN}Usando credenciales pasadas como parámetros.${RESET}"
else
  if has_tty; then
    echo -e "${YELLOW}No se han pasado credenciales. Introduce los datos:${RESET}"
    read -rp "Email de Woffu: " USER
    read -rsp "Contraseña de Woffu: " PASS
    echo
  else
    echo -e "${RED}ERROR: No se han pasado credenciales y no hay TTY.${RESET}"
    echo "Ejemplo:"
    echo "  curl -s https://.../install.sh | bash -s -- user pass"
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

echo -e "${GREEN}Credenciales guardadas en:$RESET $CREDS_FILE"
echo

# -----------------------------------------------------
# 2. DOCKERFILE (versión original)
# -----------------------------------------------------
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

# -----------------------------------------------------
# 3. ENTRYPOINT
# -----------------------------------------------------
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

# -----------------------------------------------------
# 4. BUILD
# -----------------------------------------------------
echo -e "${BLUE}Construyendo imagen Docker...${RESET}"
docker build --no-cache -t "$IMAGE_NAME" "$BASE_DIR"

# -----------------------------------------------------
# 5. WRAPPER
# -----------------------------------------------------
echo -e "${BLUE}Instalando wrapper...${RESET}"

cat > "$WRAPPER_PATH" <<EOF
#!/bin/sh
BASE_DIR="$BASE_DIR"
IMAGE_NAME="ruvelro/toffu-docker"

case "\$1" in
  login)
    USER="\$2"
    PASS="\$3"
    if [ -z "\$USER" ] || [ -z "\$PASS" ]; then
      echo "Uso: toffu-docker login usuario contraseña"
      exit 1
    fi
    echo "{ \"username\": \"\$USER\", \"password\": \"\$PASS\" }" > "\$BASE_DIR/toffu-credentials.json"
    echo "Credenciales actualizadas."
    exit 0
    ;;
esac

docker run --rm \
  -v "\$BASE_DIR:/work" \
  "\$IMAGE_NAME" "\$@"
EOF

chmod +x "$WRAPPER_PATH"

# -----------------------------------------------------
# 6. MOSTRAR CREDENCIALES
# -----------------------------------------------------
echo -e "${BLUE}Credenciales generadas:${RESET}"
cat "$CREDS_FILE"
echo

# -----------------------------------------------------
# 7. PRUEBA DE CONEXIÓN
# -----------------------------------------------------
echo -e "${BLUE}Probando token...${RESET}"
if "$WRAPPER_PATH" status >/dev/null 2>&1; then
  echo -e "${GREEN}Token verificado correctamente ✔${RESET}"
else
  echo -e "${RED}ADVERTENCIA: No se pudo verificar el token.${RESET}"
fi

echo
echo -e "${GREEN}Instalación completada ✔${RESET}"
echo
echo "Comandos disponibles:"
echo "  toffu-docker status"
echo "  toffu-docker in"
echo "  toffu-docker out"
echo "  toffu-docker login usuario contraseña"
