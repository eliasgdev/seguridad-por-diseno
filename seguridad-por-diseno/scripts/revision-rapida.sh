#!/usr/bin/env bash
# Primera pasada de patrones de riesgo en un repositorio (JS/TS/SQL/HTML).
# Solo LEE archivos; no ejecuta código del repo ni hace peticiones.
# Cada resultado es una PISTA para revisar a mano, no un hallazgo confirmado.
#
#   bash revision-rapida.sh /ruta/al/repo
set -uo pipefail

REPO="${1:-.}"
if [ ! -d "$REPO" ]; then echo "No existe la carpeta: $REPO" >&2; exit 1; fi

EXCL=(--exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.git --exclude-dir=.angular
      --exclude-dir=coverage --exclude-dir=android --exclude-dir=ios --exclude-dir=build --exclude-dir=.next)
INC=(--include=*.js --include=*.ts --include=*.mjs --include=*.cjs --include=*.html --include=*.sql --include=*.json --include=*.toml --include=*.yml --include=*.yaml)

seccion() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
buscar() { # $1 = descripción, $2 = regex (grep -E)
  local out
  out=$(grep -rnE "${EXCL[@]}" "${INC[@]}" -- "$2" "$REPO" 2>/dev/null | grep -vE '\.(test|spec)\.(js|ts)|/test/|/tests/|\.min\.js' | head -15)
  if [ -n "$out" ]; then printf '\n-- %s\n%s\n' "$1" "$out"; fi
}

seccion "Secretos posibles en el código"
buscar "Llaves privadas" '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
buscar "Tokens con formato conocido" '(sk_live_|sk_test_|prv_prod_|prod_integrity_|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|xox[baprs]-|AIza[0-9A-Za-z_-]{35}|EAA[A-Za-z0-9]{40,})'
buscar "Asignación de secreto literal" "(secret|password|passwd|api_?key|token)[\"']?\s*[:=]\s*[\"'][^\"'\$\{]{12,}[\"']"
if [ -d "$REPO/.git" ]; then
  tracked=$(git -C "$REPO" ls-files | grep -E '(^|/)\.env($|\.)|\.pem$|\.p12$|\.pfx$|id_rsa' | grep -v '\.example$')
  [ -n "$tracked" ] && printf '\n-- Archivos sensibles versionados en git\n%s\n' "$tracked"
fi

seccion "Inyección SQL (concatenación o template con datos)"
buscar "query con template string que interpola" '\.query\(\s*`[^`]*\$\{(req\.|body|params|query|input|data)'
buscar "query con concatenación" '\.query\(\s*["'"'"'][^"'"'"']*["'"'"']\s*\+'
buscar "ORDER BY / columnas dinámicas" 'ORDER BY \$\{|ORDER BY .*\+ *req\.'

seccion "Autorización (posible IDOR / mass assignment)"
buscar "UPDATE/DELETE por id sin tenant_id en la misma línea" '(UPDATE|DELETE FROM) [a-z_]+ .*WHERE id = \$[0-9]+[^a-z]*$'
buscar "Columnas del UPDATE tomadas del body" 'Object\.(keys|entries)\(req\.body\)'
buscar "tenant_id leído del cliente" 'req\.(body|query|params)\.(tenant_id|tenantId|is_super_admin|role)\b'

seccion "Rutas y webhooks"
buscar "Rutas de webhook (revisar firma + idempotencia)" "router\.(post|get)\(['\"][^'\"]*(webhook|callback|notify|events)"
buscar "Comparación de secretos con === (usar timingSafeEqual)" '(token|secret|signature|sig|apiKey|api_key|hmac)[A-Za-z_]*\s*(===|!==)\s*(req\.|process\.env)'

seccion "XSS y DOM inseguro (frontend)"
buscar "bypassSecurityTrust (solo con contenido propio)" 'bypassSecurityTrust(Html|Url|ResourceUrl|Script|Style)'
buscar "innerHTML / outerHTML / document.write" '(\.innerHTML\s*=|\.outerHTML\s*=|document\.write\(|\[innerHTML\])'
buscar "eval / new Function / setTimeout con string" '(\beval\(|new Function\(|setTimeout\(\s*["'"'"'])'
out=$(grep -rnE "${EXCL[@]}" --include=*.html --include=*.ts -- 'target="_blank"' "$REPO" 2>/dev/null | grep -v noopener | head -15)
[ -n "$out" ] && printf '\n-- target=_blank sin rel=noopener\n%s\n' "$out"

seccion "Configuración"
buscar "CORS abierto" "(origin:\s*(true|['\"]\*['\"])|Access-Control-Allow-Origin['\"]?\s*[:,]\s*['\"]\*)"
buscar "Verificación TLS desactivada" '(rejectUnauthorized:\s*false|NODE_TLS_REJECT_UNAUTHORIZED)'
buscar "JWT sin algoritmo fijo o con none" "(jwt\.verify\([^)]*\)\s*;?$|algorithms:\s*\[[^]]*none)"
buscar "Logs de cuerpos/cabeceras completos" 'console\.(log|info)\([^)]*(req\.body|req\.headers|JSON\.stringify\(req)'
buscar "Hash débil para contraseñas" "createHash\(['\"](md5|sha1)['\"]\)"
buscar "Aleatorio no criptográfico para códigos/tokens" 'Math\.random\(\).*(code|token|otp|password|secret)|(code|token|otp)[^=]*=\s*Math\.random'

seccion "Dependencias"
if [ -f "$REPO/package-lock.json" ]; then
  echo "Sugerido (no se ejecuta aquí): (cd \"$REPO\" && npm audit --omit=dev)"
fi

printf '\nListo. Revisa cada pista leyendo el código: muchas serán falsos positivos.\n'
