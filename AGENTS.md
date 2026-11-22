# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, etc.) when working with code in this repository.

Detalle funcional (regla de simulación, formato SUNAT, salida) en `README.md`. Aquí solo lo necesario para cambiar código sin romper nada.

## Comandos

```sh
./check.sh                       # único test, sin red: imprime "ok" o "FAIL: <caso>" (para en el primer fallo)
XR_CSV=$(mktemp) ./xr 250.50     # correr contra SUNAT real SIN tocar history.csv
```

- No hay build ni lint configurado.
- No hay forma de correr un caso aislado de `check.sh`. Para reproducir uno a mano, usar fixture:
  ```sh
  printf '21/11/2026|3.447|3.453|\n' > /tmp/f.txt
  XR_URL=file:///tmp/f.txt XR_CSV=/tmp/h.csv ./xr 100
  ```
- `./xr` sin `XR_CSV` escribe en `history.csv` versionado. No commitear filas generadas localmente: ese archivo lo mantiene el bot de CI.

## Arquitectura

Toda la lógica vive en `xr` (POSIX `sh`, ~30 líneas). Flujo lineal:

1. Valida monto con awk → `exit 2` si no es numérico > 0.
2. `curl` al endpoint SUNAT (no documentado) → normaliza `\r\n` → valida con regex `dd/mm/yyyy|buy|sell|` → `exit 1` sin escribir CSV si falla.
3. awk imprime simulación: USD→PEN multiplica por `buy`, PEN→USD divide por `sell`. No invertir.
4. awk imprime `ALERTA: venta X < mín 20 días Y` si `sell` < mínimo de las últimas 20 filas con otra fecha (estricto: valores repetidos de feriados no alertan; < 20 filas no alerta).
5. Append idempotente a CSV: solo si `grep "^$date,"` no encuentra la fecha. El CSV guarda tasas, nunca simulaciones.

Contratos que `check.sh` y CI asumen:

- **Exit codes**: `1` = red/respuesta inválida, `2` = monto inválido.
- **Inyección por env**: `XR_URL` (acepta `file://`) y `XR_CSV`. `check.sh` depende de ambos; no hardcodear URL ni ruta.
- **Formato de stdout**: `check.sh` hace match exacto de `^100.00 USD -> 344.70 PEN$` y de la línea `ALERTA`. El workflow dispara WhatsApp con `grep '^ALERTA'`. Cambiar el formato obliga a actualizar ambos.
- **`LC_ALL=C`**: obligatorio; sin él awk usa coma decimal en locales `es_PE`.
- **Ruta del CSV por `dirname "$0"`**: por eso la instalación global es con `alias`, no symlink.

## CI

`.github/workflows/update-exchange-rate.yml` (cron `0 16 * * 1-5` UTC = 11:00 Lima L-V + manual): corre `./check.sh`, luego `./xr 100` y commitea `history.csv` como `github-actions[bot]` solo si cambió. Si commiteó y hubo `ALERTA`, envía la salida de `xr` por WhatsApp (CallMeBot).

- Secrets `CALLMEBOT_PHONE`/`CALLMEBOT_APIKEY` solo por `env:`. Repo público: no imprimir la respuesta de CallMeBot (incluye el teléfono).
- CallMeBot responde 2xx aun con error: validar éxito con `grep 'Message queued'`, no con `curl -f`.

- `actions/checkout` está fijado por SHA (v7.0.1). Al actualizar, mantener pin por SHA con comentario de versión.
- Runner `ubuntu-slim` (1 CPU): no agregar pasos pesados.

## Restricciones

- Solo POSIX `sh` + `curl` + `awk` + `grep`/`tr`. Debe correr en macOS y en `dash`. Sin bashisms (`[[ ]]`, arrays, `$'..'`), sin dependencias nuevas, sin build.
- Mantener la validación de formato antes de usar la respuesta de SUNAT: el endpoint puede cambiar sin aviso.
- Float de awk es aceptable solo para simular; si se usa para dinero real, pasar a centavos enteros (ver comentario en `xr`).
- Mensajes, docs y commits en español.
