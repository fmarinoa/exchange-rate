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
