# Toffu Docker CLI

[![MIT license](https://img.shields.io/badge/License-MIT-blue.svg)](https://lbesson.mit-license.org/)

Automatización avanzada para fichar en Woffu usando Toffu dentro de contenedores Docker.

- Ejecuta `toffu` dentro de un contenedor, sin instalar Go ni dependencias en el host.
- Gestiona automáticamente el token de Woffu.
- Permite programar entradas y salidas mediante `cron`.
- Notifica errores o éxitos mediante Telegram (soporta `message_thread_id`).
- Proporciona instalación limpia, configuración automática y desinstalación completa.

Basado en el proyecto original: https://github.com/Madh93/toffu  
Agradecimientos al autor original — esta versión añade automatizaciones, Docker y características extra.

<img alt="Toffu Demo" src="docs/gif/demo.gif"/>

---

## Tabla de contenidos

- [Características](#características)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Estructura generada](#estructura-generada)
- [Uso básico](#uso-básico)
- [Configuración de Telegram](#configuración-de-telegram)
- [Programación automática (cron)](#programación-automática-cron)
- [Modo debug](#modo-debug)
- [Desinstalación](#desinstalación)
- [Archivos importantes](#archivos-importantes)
- [Funcionamiento interno](#funcionamiento-interno)
- [Ejemplos avanzados](#ejemplos-avanzados)
- [Créditos y licencia](#créditos-y-licencia)
- [Contribuciones](#contribuciones)

---

## Características

- Contenedor efímero por ejecución: cada comando arranca un contenedor desde cero.
- Token de Woffu generado en runtime y nunca persistido en el host.
- Envío de notificaciones por Telegram con soporte para hilos (`message_thread_id`).
- Programación simple y segura de fichajes con etiquetas en `crontab`.
- Instalador automático que genera wrapper ejecutable en `~/.local/bin/toffu-docker`.

---

## Requisitos

- Docker instalado y funcionando en el host.
- (Opcional) Permisos para escribir en `~/.local/bin` y `crontab` del usuario.
- (Opcional) Bot de Telegram y `chat_id` si quieres notificaciones.

---

## Instalación

Ejecuta el instalador (reemplaza los parámetros según corresponda):

```bash
curl -s https://raw.githubusercontent.com/ruvelro/toffu-docker/main/install-toffu-cli.sh \
| bash -s -- "correo@empresa.com" "PASSWORD123" "123456:ABC" "-1002313693703" "516"
```

Uso general:

- Si pasas `EMAIL` y `PASSWORD` (obligatorios), el instalador cifrará y almacenará credenciales.
- `TELEGRAM_TOKEN`, `TELEGRAM_CHAT_ID` y `TELEGRAM_THREAD_ID` son opcionales; si no se pasan, se pueden configurar después con el wrapper.
- Si no pasas parámetros y ejecutas en TTY, el script pedirá interactivo `EMAIL` y `PASSWORD`.

Parámetros:
- `EMAIL` — Usuario de Woffu (obligatorio).
- `PASSWORD` — Contraseña de Woffu (obligatorio).
- `TELEGRAM_TOKEN` — Token del bot (sin prefijo `bot`) (opcional).
- `TELEGRAM_CHAT_ID` — Chat o canal donde enviar avisos (opcional).
- `TELEGRAM_THREAD_ID` — ID del hilo en grupos tipo foro (opcional).

---

## Estructura generada

Al instalar, en el directorio donde ejecutes el script se crearán:

- `toffu-credentials.json` — credenciales cifradas para Woffu.
- `toffu-docker.conf` — configuración general (incluye Telegram).
- `Dockerfile` — imagen de compilación + runtime.
- `entrypoint.sh` — genera token y lanza `toffu` dentro del contenedor.

Se instala también un wrapper ejecutable en:

- `~/.local/bin/toffu-docker`

---

## Uso básico

- Comprobar estado:

```bash
toffu-docker status
```

- Fichar entrada:

```bash
toffu-docker in
```

- Fichar salida:

```bash
toffu-docker out
```

Los comandos retornan la salida de `toffu` y, según la configuración, envían notificaciones por Telegram.

---

## Configuración de Telegram

Establece token, chat y thread (si procede):

```bash
toffu-docker telegram TOKEN CHAT_ID THREAD_ID
```

Ejemplo:

```bash
toffu-docker telegram 123456:ABC -1002313693703 516
```

- Puedes usar solo `TOKEN` + `CHAT_ID`, o añadir `THREAD_ID` para foros/temas.
- Para cambiar el modo de notificación usa:

```bash
toffu-docker telegram-mode errors
```

Modos disponibles:
- `errors` — Solo envía en errores.
- `success` — Solo envía cuando el fichaje fue correcto.
- `all` — Envía ambos (éxitos y errores).

---

## Programación automática (cron)

Permite programar múltiples horas de entrada y salida.

- Añadir una entrada:

```bash
toffu-docker schedule entrada add HH:MM
```

- Añadir una salida:

```bash
toffu-docker schedule salida add HH:MM
```

- Eliminar una hora:

```bash
toffu-docker schedule entrada del HH:MM
# o
toffu-docker schedule salida del HH:MM
```

- Listar horarios:

```bash
toffu-docker schedule list
```

- Pausar todas las tareas:

```bash
toffu-docker schedule pause
```

- Reanudar:

```bash
toffu-docker schedule resume
```

Cada línea añadida al `crontab` incluirá una etiqueta con formato:
```
# TOFFU_DOCKER_ENTRADA_09_00
```
Esto facilita su identificación y gestión por el wrapper.

---

## Modo debug

Muestra información extendida y evita enviar mensajes a Telegram (útil para depuración):

```bash
toffu-docker debug in
```

---

## Desinstalación completa

Para borrar todo lo instalado y configurado:

```bash
toffu-docker uninstall
```

Esto elimina:

- Imagen Docker generada.
- Wrapper en `~/.local/bin/toffu-docker`.
- `Dockerfile`, `entrypoint.sh`.
- `toffu-credentials.json` y `toffu-docker.conf`.
- Entradas de `crontab` generadas por el instalador.

---

## Archivos importantes

- `toffu-credentials.json` — credenciales Woffu:

```json
{
  "username": "correo",
  "password": "clave"
}
```

- `toffu-docker.conf` — configuración general, por ejemplo:
```
TELEGRAM_TOKEN=
TELEGRAM_CHAT_ID=
TELEGRAM_THREAD_ID=
TELEGRAM_MODE=errors
DAYS_RANGE=1-5
PAUSED=0
```

---

## Funcionamiento interno

Cada ejecución de `toffu-docker`:

1. Inicia un contenedor desde la imagen definida en `Dockerfile`.
2. El `entrypoint.sh` genera un token de Woffu (autologin) usando las credenciales cifradas.
3. Ejecuta el comando `toffu` solicitado (`in`, `out`, `status`, etc.).
4. Devuelve el resultado al host y destruye el contenedor.
5. Si está configurado, envía notificación por Telegram (token nunca queda en claro en el host).

Ventajas:
- Host limpio (sin Go ni dependencias).
- Token efímero y no persistente.

---

## Ejemplos de uso avanzado

- Fichar y notificar solo errores:

```bash
toffu-docker telegram-mode errors
toffu-docker in
```

- Fichar y notificar todo:

```bash
toffu-docker telegram-mode all
toffu-docker out
```

- Programar una jornada completa:

```bash
toffu-docker schedule entrada add 09:00
toffu-docker schedule salida add 13:00
toffu-docker schedule entrada add 14:30
toffu-docker schedule salida add 18:00
```

---

## Créditos

- Herramienta original: `toffu` por @Madh93  
  Repositorio original: https://github.com/Madh93/toffu

Esta versión amplía la funcionalidad con:
- Docker
- Autologin completo
- Cron
- Telegram (incluido `message_thread_id`)
- Sistema de configuración y wrapper CLI
- Instalación automática

---

## Licencia

Este proyecto mantiene la misma licencia que el proyecto Toffu original. Revisa el archivo `LICENSE` en el repositorio original para detalles.

---

## Contribuciones

PRs bienvenidos: https://github.com/ruvelro/toffu-docker
