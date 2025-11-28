#!/usr/bin/env bash
set -e

# ==============================================================================
#  COLORES
# ==============================================================================
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RESET="\033[0m"

echo -e "${BLUE}== Toffu Docker CLI Installer ==${RESET}"

# ==============================================================================
#  PARÁMETROS
# ==============================================================================
USER="$1"
PASS="$2"
TG_TOKEN="$3"
TG_CHAT="$4"

BASE_DIR="$(pwd)"
IMAGE_NAME="ruvelro/toffu-docker"
LOCAL_BIN="$HOME/.local/bin"
WRAPPER_PATH="$LOCAL_BIN/toffu-docker"

CONFIG_FILE="$BASE_DIR/toffu-docker.conf"
CREDS_FILE="$BASE_DIR/toffu-credentials.json"

echo "Directorio de instalación: $BASE_DIR"
echo

# Crear carpeta ~/.local/bin si no existe
mkdir -p "$LOCAL_BIN"

# Añadir ~/.local/bin al PATH si no está
if ! echo "$PATH" | grep -q "$LOCAL_BIN"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    export PATH="$HOME/.local/bin:$PATH"
    echo -e "${GREEN}Añadido ~/.local/bin al PATH.${RESET}"
fi

# ==============================================================================
#  DETECTAR SI HAY TTY
# ==============================================================================
has_tty() {
  [ -t 0 ]
}

# ==============================================================================
#  1. CREDENCIALES WOFFU
# ==============================================================================
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
        echo "Forma correcta:"
        echo "  curl -s ... | bash -s -- email pass"
        exit 1
    fi
fi

echo -e "${BLUE}Generando archivo de credenciales Woffu...${RESET}"

cat > "$CREDS_FILE" <<EOF
{
  "username": "$USER",
  "password": "$PASS"
}
EOF

echo -e "${GREEN}Credenciales guardadas: $CREDS_FILE${RESET}"
echo

# ==============================================================================
#  2. CONFIGURACIÓN TELEGRAM + GENERAL
# ==============================================================================
echo -e "${BLUE}Generando archivo de configuración...${RESET}"

cat > "$CONFIG_FILE" <<EOF
TELEGRAM_TOKEN=${TG_TOKEN:-}
TELEGRAM_CHAT_ID=${TG_CHAT:-}
TELEGRAM_MODE=errors
DAYS_RANGE=1-5
PAUSED=0
EOF

echo -e "${GREEN}Archivo de configuración generado: $CONFIG_FILE${RESET}"
echo

# ==============================================================================
#  3. GENERAR DOCKERFILE
# ==============================================================================
echo -e "${BLUE}Creando Dockerfile...${RESET}"

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

echo -e "${GREEN}Dockerfile creado.${RESET}"
echo

# ==============================================================================
#  4. GENERAR ENTRYPOINT
# ==============================================================================
echo -e "${BLUE}Creando entrypoint.sh...${RESET}"

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

echo -e "${GREEN}entrypoint.sh creado.${RESET}"
echo

# ==============================================================================
#  5. BUILD DOCKER IMAGE
# ==============================================================================
echo -e "${BLUE}Construyendo imagen Docker (sin caché)...${RESET}"
docker build --no-cache -t "$IMAGE_NAME" "$BASE_DIR"
echo -e "${GREEN}Imagen creada: $IMAGE_NAME${RESET}"
echo

# ==============================================================================
#  6. INSTALAR WRAPPER
# ==============================================================================
echo -e "${BLUE}Instalando wrapper toffu-docker...${RESET}"

cat > "$WRAPPER_PATH" <<"EOF"
#!/bin/sh

# ============================================================================
#  WRAPPER COMPLETO TOFFU-DOCKER (Versión Final)
#  - DEBUG
#  - NOTIFICACIONES TELEGRAM (errors | success | all)
#  - LOGIN / TOKEN AUTO
#  - SCHEDULE (add/del/list/pause/resume)
#  - DESINSTALACIÓN COMPLETA
# ============================================================================

BASE_DIR="__BASE_DIR__"
IMAGE_NAME="ruvelro/toffu-docker"
WRAPPER_PATH="$HOME/.local/bin/toffu-docker"

CONFIG_FILE="$BASE_DIR/toffu-docker.conf"
CREDS_FILE="$BASE_DIR/toffu-credentials.json"

TAG_ENTRADA="TOFFU_DOCKER_ENTRADA"
TAG_SALIDA="TOFFU_DOCKER_SALIDA"

GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RESET="\033[0m"

DEBUG=0

# ============================================================================
#  UTILS
# ============================================================================

debug_echo() {
  if [ "$DEBUG" = "1" ]; then
    printf "${YELLOW}[DEBUG]${RESET} %s\n" "$1"
  fi
}

load_config() {
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
}

save_config() {
  {
    echo "TELEGRAM_TOKEN=${TELEGRAM_TOKEN:-}"
    echo "TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}"
    echo "TELEGRAM_MODE=${TELEGRAM_MODE:-errors}"
    echo "DAYS_RANGE=${DAYS_RANGE:-1-5}"
    echo "PAUSED=${PAUSED:-0}"
  } > "$CONFIG_FILE"
}

notify() {
  load_config

  TYPE="$1"  # success | error
  TEXT="$2"

  [ -z "$TELEGRAM_TOKEN" ] && return
  [ -z "$TELEGRAM_CHAT_ID" ] && return

  case "$TELEGRAM_MODE" in
    errors)
      [ "$TYPE" != "error" ] && return
      ;;
    success)
      [ "$TYPE" != "success" ] && return
      ;;
    all)
      ;;
    *)
      return
      ;;
  esac

  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$TEXT" >/dev/null 2>&1 || true
}

ensure_cron_available() {
  if ! command -v crontab >/dev/null 2>&1; then
    echo "Cron no está disponible en este sistema."
    exit 1
  fi
}

# ============================================================================
#  EJECUTAR TOFFU EN DOCKER
# ============================================================================

run_toffu() {
  load_config

  debug_echo "Ejecutando: docker run --rm -v $BASE_DIR:/work $IMAGE_NAME $*"

  OUTPUT=$(docker run --rm -v "$BASE_DIR:/work" "$IMAGE_NAME" "$@" 2>&1)
  STATUS=$?

  printf "%s\n" "$OUTPUT"

  if [ "$DEBUG" != "1" ]; then
    if [ $STATUS -eq 0 ]; then
      notify "success" "✔ Fichaje correcto ($*)"
    else
      notify "error" "⚠️ Error en toffu-docker $*\n\n$OUTPUT"
    fi
  fi

  return $STATUS
}

# ============================================================================
#  SCHEDULE (CRONTAB)
# ============================================================================

add_schedule() {
  TYPE="$1"
  TIME="$2"

  ensure_cron_available
  load_config

  HOUR=${TIME%:*}
  MIN=${TIME#*:}

  case "$TYPE" in
    entrada) TAG="$TAG_ENTRADA"; CMD="in" ;;
    salida) TAG="$TAG_SALIDA"; CMD="out" ;;
    *) echo "Tipo inválido"; exit 1 ;;
  esac

  LABEL="${TAG}_${HOUR}_${MIN}"

  TMP=$(mktemp)
  crontab -l 2>/dev/null > "$TMP" || true

  if grep -q "$LABEL" "$TMP"; then
    echo "Ya existe una programación a las $TIME"
    rm -f "$TMP"
    exit 0
  fi

  DR="${DAYS_RANGE:-1-5}"

  echo "$MIN $HOUR * * $DR $WRAPPER_PATH $CMD # $LABEL" >> "$TMP"
  crontab "$TMP"
  rm -f "$TMP"

  echo "Programado $TYPE a las $TIME"
}

del_schedule() {
  TYPE="$1"
  TIME="$2"

  ensure_cron_available
  load_config

  HOUR=${TIME%:*}
  MIN=${TIME#*:}

  case "$TYPE" in
    entrada) TAG="$TAG_ENTRADA" ;;
    salida) TAG="$TAG_SALIDA" ;;
    *) echo "Tipo inválido"; exit 1 ;;
  esac

  LABEL="${TAG}_${HOUR}_${MIN}"

  TMP=$(mktemp)
  crontab -l 2>/dev/null | grep -v "$LABEL" > "$TMP"
  crontab "$TMP"
  rm -f "$TMP"

  echo "Eliminado $TYPE a las $TIME"
}

list_schedules() {
  ensure_cron_available
  crontab -l 2>/dev/null | grep "TOFFU_DOCKER_" || echo "No hay programaciones activas."
}

pause_schedules() {
  ensure_cron_available

  TMP=$(mktemp)
  crontab -l 2>/dev>null > "$TMP" || true
  sed -e '/TOFFU_DOCKER_/ s/^[^#]/# &/' "$TMP" > "${TMP}.new"
  crontab "${TMP}.new"

  rm -f "$TMP" "${TMP}.new"

  load_config
  PAUSED=1
  save_config

  echo "Programaciones pausadas."
}

resume_schedules() {
  ensure_cron_available

  TMP=$(mktemp)
  crontab -l 2>/dev/null > "$TMP" || true
  sed -e 's/^# \(.*TOFFU_DOCKER_.*\)$/\1/' "$TMP" > "${TMP}.new"
  crontab "${TMP}.new"

  rm -f "$TMP" "${TMP}.new"

  load_config
  PAUSED=0
  save_config

  echo "Programaciones reanudadas."
}

# ============================================================================
#  MAIN COMMANDS
# ============================================================================

case "$1" in

  login)
    USER="$2"
    PASS="$3"
    echo "{ \"username\": \"$USER\", \"password\": \"$PASS\" }" > "$CREDS_FILE"
    echo "Credenciales actualizadas."
    ;;

  telegram)
    TELEGRAM_TOKEN="$2"
    TELEGRAM_CHAT_ID="$3"
    load_config
    TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
    TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
    save_config
    echo "Telegram configurado."
    ;;

  telegram-mode)
    MODE="$2"
    case "$MODE" in
      errors|success|all)
        load_config
        TELEGRAM_MODE="$MODE"
        save_config
        echo "Modo Telegram actualizado a: $MODE"
        ;;
      *)
        echo "Modos permitidos: errors | success | all"
        ;;
    esac
    ;;

  uninstall)
    echo "Desinstalando Toffu Docker CLI..."

    rm -f "$CREDS_FILE" "$CONFIG_FILE"
    rm -f "$BASE_DIR/Dockerfile" "$BASE_DIR/entrypoint.sh"

    docker rmi -f "$IMAGE_NAME" >/dev/null 2>&1 || true

    if command -v crontab >/dev/null 2>&1; then
      TMP=$(mktemp)
      crontab -l 2>/dev/null | grep -v "TOFFU_DOCKER_" > "$TMP" || true
      crontab "$TMP" || true
      rm -f "$TMP"
    fi

    rm -f "$WRAPPER_PATH"

    echo "Eliminación completa."
    ;;

  schedule)
    SUB="$2"
    case "$SUB" in
      entrada)
        case "$3" in
          add) del_schedule entrada "$4" 2>/dev/null || true; add_schedule entrada "$4" ;;
          del) del_schedule entrada "$4" ;;
        esac
        ;;
      salida)
        case "$3" in
          add) del_schedule salida "$4" 2>/dev/null || true; add_schedule salida "$4" ;;
          del) del_schedule salida "$4" ;;
        esac
        ;;
      list) list_schedules ;;
      pause) pause_schedules ;;
      resume) resume_schedules ;;
      *)
        echo "Uso: toffu-docker schedule entrada|salida add|del HH:MM"
        ;;
    esac
    ;;

  debug)
    DEBUG=1
    shift
    run_toffu "$@"
    ;;

  *)
    run_toffu "$@"
    ;;
esac
EOF

# Reemplazar __BASE_DIR__ por el directorio real
sed -i "s#__BASE_DIR__#$BASE_DIR#g" "$WRAPPER_PATH"
chmod +x "$WRAPPER_PATH"

echo -e "${GREEN}Wrapper instalado: $WRAPPER_PATH${RESET}"
echo

# ==============================================================================
#  7. PROGRAMACIONES POR DEFECTO
# ==============================================================================

echo -e "${BLUE}Creando programaciones por defecto...${RESET}"

# Añadir entrada 09:00
$WRAPPER_PATH schedule entrada add 09:00

# Añadir salida 13:00
$WRAPPER_PATH schedule salida add 13:00

# Añadir entrada 14:30
$WRAPPER_PATH schedule entrada add 14:30

# Añadir salida 18:00
$WRAPPER_PATH schedule salida add 18:00

echo -e "${GREEN}Horario por defecto configurado (L-V: 09:00 / 13:00 / 14:30 / 18:00).${RESET}"
echo

# ==============================================================================
#  MOSTRAR RESULTADOS
# ==============================================================================
echo -e "${BLUE}Credenciales Woffu:${RESET}"
cat "$CREDS_FILE"

echo
echo -e "${BLUE}Configuración general:${RESET}"
cat "$CONFIG_FILE"

echo
echo -e "${GREEN}Instalación completada ✔${RESET}"
echo "Comandos útiles:"
echo "  toffu-docker status"
echo "  toffu-docker in"
echo "  toffu-docker out"
echo "  toffu-docker login USER PASS"
echo "  toffu-docker telegram BOT_TOKEN CHAT_ID"
echo "  toffu-docker telegram-mode errors|success|all"
echo "  toffu-docker schedule entrada add HH:MM"
echo "  toffu-docker schedule salida add HH:MM"
echo "  toffu-docker schedule list"
echo "  toffu-docker schedule pause"
echo "  toffu-docker schedule resume"
echo "  toffu-docker uninstall"
