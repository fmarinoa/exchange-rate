# exchange-rate

Comando on-demand (`xr`) que consulta el tipo de cambio SUNAT y simula la conversión USD ⇄ PEN. Imprime la simulación en terminal y guarda el histórico de tasas en CSV.

## Stack

POSIX `sh` + `curl` + `awk`. Corre en macOS y Linux (`dash`/`bash`) sin dependencias ni build.

- **macOS:** todo viene preinstalado.
- **Linux:** `awk` siempre está; `curl` puede faltar en imágenes mínimas (`apt install curl`).

**Por qué no Python/Node/Go:** el tiempo total lo pone la red (~60 ms en el request a SUNAT); el cómputo es una multiplicación. Ningún lenguaje lo hace "más rápido" de forma perceptible, así que gana el que no instala ni compila nada.

## Fuente

```
GET https://www.sunat.gob.pe/a/txt/tipoCambio.txt
21/11/2026|3.447|3.453|
```

Formato `fecha|compra|venta|`. El endpoint **no está documentado** como API: puede cambiar sin aviso, por eso se valida el formato antes de usarlo.

El valor es el promedio ponderado SBS del **día hábil anterior** (no es tiempo real): sábado, domingo y lunes muestran el cierre del viernes.

## Regla de simulación

La tasa se elige según **quién compra el dólar**:

| Operación | Tú… | Tasa | Fórmula |
|---|---|---|---|
| USD → PEN | vendes USD | **compra** (`buy`) | `PEN = USD × buy` |
| PEN → USD | compras USD | **venta** (`sell`) | `USD = PEN ÷ sell` |

Ejemplo con 21/11/2026, monto 100:

```
100.00 USD -> 344.70 PEN   (100 × 3.447)
100.00 PEN ->  28.96 USD   (100 ÷ 3.453)
```

> El tipo SUNAT es **referencial**. Bancos y casas de cambio aplican un spread mayor, así que el monto real será menor en ambos sentidos.

Redondeo a 2 decimales con `printf "%.2f"` de awk (float). Sirve para simular, no para contabilidad.

## Uso

```sh
./xr          # monto 100 por defecto
./xr 250.50   # monto custom
```

Como comando global, agregar en `~/.zshrc` (macOS) o `~/.bashrc` (Linux):

```sh
alias xr=~/dev/personal/exchange-rate/xr
```

Usar `alias`, no symlink: el script ubica `history.csv` con `dirname "$0"`, y con un symlink apuntaría a la carpeta del link.

## Salida

**Terminal**

```
SUNAT 21/11/2026  buy 3.447  sell 3.453
100.00 USD -> 344.70 PEN
100.00 PEN -> 28.96 USD
```

Si `sell` es menor (estricto) que el mínimo de las últimas 20 filas del CSV con otra fecha, agrega una última línea. Con menos de 20 filas no alerta.

```
ALERTA: venta 3.399 < mín 20 días 3.404
```

**CSV** `history.csv` (junto al script): histórico de tasas, una fila por `sunat_date`. Crea el header si no existe; si la fecha ya está, no agrega nada.

```csv
sunat_date,buy,sell
21/11/2026,3.447,3.453
```

La simulación no se guarda: se recalcula con `buy`/`sell` y cualquier monto. `sunat_date` es la fecha que publica SUNAT: en fines de semana o feriados puede ser la del último día hábil.

Las filas 26/10/2026 a 20/11/2026 se cargaron desde la API del BCRP (series `PD04639PD`/`PD04640PD`, SBS compra/venta), asignando el valor SBS del día `d` a la fecha SUNAT del día hábil siguiente.

## Flujo

1. Valida el monto: numérico y > 0. Si no, `exit 2`.
2. `curl -fsS --max-time 10 "$XR_URL"`: falla con HTTP ≥ 400 o timeout.
3. Quita `\r` y `\n`, luego valida con `grep -Eq '^[0-9]{2}/[0-9]{2}/[0-9]{4}\|[0-9]+\.[0-9]+\|[0-9]+\.[0-9]+\|$'`.
4. Si falla el paso 2 o 3: mensaje a stderr, `exit 1`, **no escribe en el CSV** (para no ensuciar el histórico).
5. awk calcula e imprime en terminal.
6. awk compara `sell` contra el mínimo de las últimas 20 filas con otra fecha e imprime `ALERTA: …` si es menor.
7. Agrega `sunat_date,buy,sell` al CSV solo si `grep -q "^$date,"` no la encuentra.

## Configuración (env, opcional)

| Variable | Default | Uso |
|---|---|---|
| `XR_URL` | URL SUNAT | Override para el check (`file://` con fixture) |
| `XR_CSV` | `$(dirname "$0")/history.csv` | Ruta del histórico |

## Estructura

```
exchange-rate/
├── README.md
├── xr            # script POSIX sh ejecutable
├── check.sh      # check del cálculo y del CSV, sin red
└── history.csv   # histórico versionado y actualizado por GitHub Actions
```

## Check

`check.sh` escribe un fixture `21/11/2026|3.447|3.453|` en un tmp, corre `XR_URL=file://… XR_CSV=<tmp> ./xr 100` y verifica:

- stdout contiene `344.70 PEN` y `28.96 USD`
- dos corridas con la misma fecha dejan el CSV con header + 1 fila
- alerta solo con 20 filas previas y `sell` menor al mínimo; sin alerta si hay menos filas o el mínimo es menor
- un fixture con formato inválido termina con `exit 1` y no escribe en el CSV
- montos inválidos (`abc`, `0`) terminan con `exit 2`

```sh
./check.sh   # imprime "ok" o "FAIL: <caso>"
```

## GitHub Action

El workflow `.github/workflows/update-exchange-rate.yml` consulta SUNAT de lunes a viernes a las 16:00 UTC (11:00 Lima), ejecuta el check sin red y agrega la tasa al CSV solo si la fecha aún no existe. También puede ejecutarse manualmente desde la pestaña **Actions**.

Si el commit agregó una fila y la salida de `xr` tiene `ALERTA`, envía esa salida completa por WhatsApp con [CallMeBot](https://www.callmebot.com/). Requiere los secrets `CALLMEBOT_PHONE` y `CALLMEBOT_APIKEY`. CallMeBot responde 2xx aun con apikey inválida, así que el éxito se valida buscando `Message queued` en la respuesta; si no aparece, el job falla. La respuesta no se imprime porque incluye el teléfono y el repo es público.

Si no hay cambios, el workflow termina sin crear un commit vacío. `actions/checkout` está fijado a la versión exacta `v7.0.1` por SHA y el runner usa `ubuntu-slim`, una opción más ligera con una CPU para tareas cortas como esta.

## Fuera de alcance

- **Otras monedas / tasas de casas de cambio:** solo USD SUNAT. El nombre `exchange-rate` deja espacio para esto si llega a hacer falta.
