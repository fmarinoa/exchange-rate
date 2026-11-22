#!/bin/sh
# Check de xr sin red: cálculo, dedup del CSV, respuesta inválida y monto inválido.
set -eu
cd "$(dirname "$0")"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

printf '21/11/2026|3.447|3.453|\n' > "$tmp/ok.txt"
printf '<html>error</html>\n' > "$tmp/bad.txt"
ok() { XR_URL="file://$tmp/ok.txt" XR_CSV="$tmp/history.csv" ./xr "$@"; }

out=$(ok 100)
echo "$out" | grep -q '^100.00 USD -> 344.70 PEN$' || fail "USD -> PEN"
echo "$out" | grep -q '^100.00 PEN -> 28.96 USD$' || fail "PEN -> USD"
if echo "$out" | grep -q ALERTA; then fail "sin alerta con menos de 20 filas"; fi

# 20 filas con sell 3.500, la última con sell $1
win() {
  awk -v low="$1" 'BEGIN { print "sunat_date,buy,sell"
    for (i = 1; i <= 20; i++) printf "%02d/10/2026,3.490,%s\n", i, (i == 20 ? low : "3.500") }' > "$tmp/w.csv"
  XR_URL="file://$tmp/ok.txt" XR_CSV="$tmp/w.csv" ./xr
}
out=$(win 3.500)
echo "$out" | grep -q '^ALERTA: venta 3.453 < mín 20 días 3.500$' || fail "alerta si venta < mín 20 días"
out=$(win 3.400)
if echo "$out" | grep -q ALERTA; then fail "sin alerta si venta >= mín 20 días"; fi

ok 100 > /dev/null
[ "$(cat "$tmp/history.csv")" = "sunat_date,buy,sell
21/11/2026,3.447,3.453" ] || fail "CSV con header + 1 fila tras 2 corridas"

code=0; XR_URL="file://$tmp/bad.txt" XR_CSV="$tmp/bad.csv" ./xr 2>/dev/null || code=$?
[ "$code" -eq 1 ] || fail "respuesta inválida debe salir con 1 (salió $code)"
[ ! -e "$tmp/bad.csv" ] || fail "respuesta inválida no debe escribir CSV"

for a in abc 0; do
  code=0; ok "$a" 2>/dev/null || code=$?
  [ "$code" -eq 2 ] || fail "monto '$a' debe salir con 2 (salió $code)"
done

echo ok
