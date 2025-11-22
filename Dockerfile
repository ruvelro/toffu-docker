# -------------------------
# Stage 1: build (Go + make)
# -------------------------
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache git make

WORKDIR /src

# Clonar tu fork de toffu
RUN git clone https://github.com/ruvelro/toffu-docker.git .

# Compilar e instalar el binario en /usr/local/bin/toffu
RUN make install

# -------------------------
# Stage 2: runtime mínimo
# -------------------------
FROM alpine:latest

RUN apk add --no-cache \
      ca-certificates \
      curl \
      jq \
      tzdata && \
    update-ca-certificates

# Zona horaria para evitar el panic de Go
ENV TZ=Europe/Madrid
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Copiamos únicamente el binario
COPY --from=builder /usr/local/bin/toffu /usr/local/bin/toffu

# Script de entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /root

ENTRYPOINT ["/entrypoint.sh"]
# Sin CMD: si no pasas argumentos, se ejecuta "toffu" a secas dentro
