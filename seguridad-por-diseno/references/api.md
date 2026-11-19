# APIs seguras (Node/Express, aplica a cualquier stack)

Basado en OWASP API Security Top 10 (2023) y ASVS 4.0 capítulos V2–V5, V13.

## Índice
1. Autenticación
2. Sesiones y JWT
3. Autorización (roles, objetos, multi-tenant)
4. Validación de entrada y salida
5. Abuso: rate limit, tamaño, paginación, tiempo
6. Webhooks y callbacks
7. Subida y descarga de archivos
8. Llamadas salientes (SSRF) e integraciones
9. Funciones con IA (LLM)
10. Errores y respuestas
11. Pruebas negativas obligatorias

---

## 1. Autenticación

- Contraseñas con `bcrypt` (costo ≥ 12) o `argon2id`. Nunca SHA/MD5, nunca cifrado reversible.
- Política: mínimo 10 caracteres; rechazar las comunes/filtradas; sin reglas absurdas de símbolos.
- Login, registro, "olvidé mi clave", verificación 2FA y reenvío de códigos: **rate limit por IP y por cuenta** + bloqueo temporal tras N fallos (ej. 5 en 15 min).
- Mensaje único para usuario o clave incorrectos ("Correo o contraseña incorrectos"); igual tiempo de respuesta aunque el usuario no exista (comparar contra un hash falso).
- Restablecer contraseña: token aleatorio de 32 bytes (`crypto.randomBytes`), guardado **hasheado**, de un solo uso, caducidad corta (≤ 1 h), invalida sesiones al usarse.
- Códigos OTP (WhatsApp/SMS/correo): `crypto.randomInt`, caducidad ≤ 10 min, máx. 5 intentos, comparación en tiempo constante.
- OAuth/Google: verificar el ID token en el servidor (firma, `aud` = tu client id, `iss`, `exp`, `email_verified`). Nunca aceptar el correo que manda el cliente.

## 2. Sesiones y JWT

- Access token corto (5–15 min) + refresh token largo y **revocable** (versión de token en la tabla `users`, o tabla de sesiones). Cambiar/restablecer clave incrementa la versión → cierra todas las sesiones.
- Firmar con secreto ≥ 32 bytes aleatorios; fijar el algoritmo al verificar (`jwt.verify(t, secret, { algorithms: ['HS256'] })`). Rechazar `alg: none`.
- El payload no lleva datos sensibles (es solo base64). Sí lleva `sub`, `tenant_id`, `role`, versión.
- Releer de la base lo que pueda cambiar y sea crítico (usuario desactivado, plan vencido, rol cambiado) en rutas sensibles; no confiar 15 min en un token viejo para eso.
- En navegador: preferir refresh token en cookie `HttpOnly; Secure; SameSite=Lax/Strict; Path=/api/auth`. Si se usa `localStorage`, la CSP y la ausencia de XSS pasan a ser críticas.

## 3. Autorización

Tres capas, todas obligatorias:

```js
router.use(verifyToken, requireTenant);                 // 1. identidad
router.patch('/:id', requireRoles(OWNER, ADMIN), ...);  // 2. función (rol)
// 3. objeto: el WHERE lleva el negocio del token, nunca el del body
const { rows } = await pool.query(
  'UPDATE products SET price = $1 WHERE id = $2 AND tenant_id = $3 RETURNING id',
  [price, req.params.id, req.user.tenant_id]
);
if (!rows.length) return res.status(404).json({ error: 'Ese producto no existe' });
```

- **BOLA/IDOR**: cada consulta por id incluye `tenant_id` (o dueño). Revisar también JOINs: el objeto relacionado (ej. `category_id` que manda el cliente) debe pertenecer al mismo negocio.
- **BFLA**: rutas de admin/super-admin con su propio middleware (`requireSuperAdmin`), montadas aparte (`/api/platform`). Un dueño de negocio nunca es super-admin por defecto.
- **Mass assignment (BOPLA)**: construir el UPDATE desde una lista blanca de columnas, nunca `Object.keys(req.body)`. Campos como `role`, `is_super_admin`, `tenant_id`, `plan`, `status`, `price` pagado, jamás editables por el cliente.
- **Escalada de rol**: un admin no puede crear/elevar a owner; nadie se asigna permisos a sí mismo; el último owner no se puede degradar.
- **Multi-tenant**: aislamiento por app + (ideal) RLS en Postgres como segunda red (ver base-de-datos.md). Prueba de barrido: con el token del negocio A, pedir cada recurso del negocio B → todo 404.
- Identificadores: UUID v4 o enteros + verificación de dueño. Los UUID no reemplazan la autorización.

## 4. Validación de entrada y salida

- Validar en el borde con esquema (zod/joi/validador propio): tipo, `max` de largo, rangos, enums, formato (email, teléfono E.164, URL `https://`). Un solo archivo de límites compartido con la base (CHECK) y la pantalla (`maxlength`).
- `express.json({ limit })` acorde a la ruta; para rutas con archivos, límites propios.
- Normalizar antes de validar (trim, NFC, minúsculas en correos). Cuidado con homoglifos en nombres de usuario.
- Strings que van a una búsqueda `ILIKE`: escapar `%`, `_`, `\`.
- Orden/columnas dinámicas: mapa cerrado `{ fecha: 'created_at', total: 'total' }`.
- Respuestas: DTO explícito. Nunca devolver `password_hash`, tokens, códigos, secretos de integración, datos de otros usuarios. Revisar `RETURNING *` que va directo al cliente.
- Expresiones regulares sobre entrada del usuario: evitar backtracking catastrófico (ReDoS); limitar el largo antes de aplicar la regex.

## 5. Abuso de recursos

- Rate limit global por IP y específico en auth, formularios públicos (leads, contacto), envío de correos/WhatsApp, generación de PDF, IA. Detrás de proxy: `app.set('trust proxy', 1)` correcto o todos comparten IP.
- Paginación con tope (`limit` máx. 100–500) y keyset para listas grandes.
- Timeouts en toda llamada saliente (`AbortSignal.timeout(15000)`) y en consultas pesadas (`statement_timeout` por rol).
- Operaciones caras (exportar, reportes, PDF) en cola o con límite de concurrencia por negocio.
- Costos: un endpoint público que envía WhatsApp/SMS/correo es un vector de gasto (toll fraud). Rate limit + captcha/turnstile si es anónimo.

## 6. Webhooks y callbacks

```js
// app.js: guardar el cuerpo crudo SOLO para las rutas de webhook
app.use(express.json({ verify: (req, _res, buf) => {
  if (req.originalUrl.startsWith('/api/whatsapp/')) req.rawBody = buf;
}}));

// verificación: HMAC del cuerpo EXACTO + comparación en tiempo constante
const expected = crypto.createHmac('sha256', secret).update(req.rawBody).digest();
const given = Buffer.from(sig.replace(/^sha256=/, ''), 'hex');
if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return res.sendStatus(401);
```

- Sin secreto configurado en producción → 401 (fallar cerrado).
- Idempotencia: guardar el id del evento (índice único) y no procesar dos veces; los proveedores reintentan.
- Responder 200 rápido y procesar después; pero **verificar la firma antes** de responder 200.
- Revalidar contra la fuente lo crítico (ej. pagos: consultar el estado de la transacción en la API del proveedor y comparar monto/moneda/referencia con lo esperado antes de activar un plan).
- No registrar el cuerpo completo (trae datos personales).
- Proveedores comunes: Meta/WhatsApp `X-Hub-Signature-256` (secreto de la app); Wompi `signature.checksum` con el secreto de eventos; Stripe `stripe-signature` con tolerancia de tiempo.

## 7. Archivos

- Subida: límite de tamaño, lista blanca de tipos por **contenido** (magic bytes), no por extensión ni `Content-Type` del cliente. Nombre generado por el servidor (UUID), nunca el del usuario en la ruta.
- Guardar fuera del webroot o en bucket privado (R2/S3) y servir con URL firmada de corta duración, verificando dueño antes de firmar.
- Descarga: `Content-Disposition: attachment` para lo que no deba renderizarse; `X-Content-Type-Options: nosniff`. SVG y HTML subidos por usuarios = XSS: servirlos como descarga o desde otro dominio.
- Archivos comprimidos: limitar entradas/tamaño descomprimido (zip bomb) y rechazar rutas con `..` (zip slip).
- Imágenes: re-codificar (sharp) para quitar metadatos (EXIF con GPS) y payloads.

## 8. Llamadas salientes (SSRF)

- Si el usuario da una URL (logo, webhook propio, importar), validar esquema `https`, resolver DNS y rechazar IPs privadas/locales (`10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `::1`, `fc00::/7`), sin seguir redirecciones a ellas.
- Lista blanca de dominios cuando sea posible.
- Timeout y tamaño máximo de respuesta.

## 9. Funciones con IA (LLM)

- El texto del usuario y los documentos son **datos**, no instrucciones: el modelo no debe poder ejecutar acciones con permisos que el usuario no tenga (prompt injection). Las herramientas que el modelo puede llamar validan permisos igual que un endpoint.
- No meter en el prompt datos de otros negocios ni secretos. Filtrar por `tenant_id` antes de armar el contexto.
- Salida del modelo = entrada no confiable: escapar al mostrar, validar antes de guardar o ejecutar.
- Límite de costo: rate limit por negocio, `max_tokens`, tiempo máximo y caché.

## 10. Errores y respuestas

- Manejador global: al cliente, mensaje genérico en su idioma + id de correlación; al log, el detalle. Nunca stack traces, SQL ni rutas internas en la respuesta.
- 401 sin identidad, 403 sin permiso de función, 404 para objetos de otro dueño, 409 conflictos, 422/400 validación, 429 límite.
- `helmet()` y `app.disable('x-powered-by')`.

## 11. Pruebas negativas obligatorias (por ruta nueva)

Con base desechable y HTTP real (supertest o fetch contra `app.listen(0)`):

| Caso | Esperado |
|---|---|
| Sin token / token alterado / vencido | 401 |
| Rol sin permiso | 403 |
| Objeto de otro negocio (lectura, edición, borrado) | 404 y sin cambios en la base |
| Campo prohibido en el body (`role`, `tenant_id`) | ignorado o 400 |
| Valor fuera de rango / muy largo / tipo incorrecto | 400 con mensaje claro |
| Repetir la misma petición idempotente / webhook duplicado | sin efecto doble |
| Webhook sin firma o con firma de otro cuerpo | 401 |
| Ráfaga sobre login / formulario público | 429 |
