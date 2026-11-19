---
name: seguridad-por-diseno
description: Normas de ciberseguridad para CREAR y REVISAR páginas web, APIs y bases de datos seguras desde el primer commit (OWASP Top 10, OWASP API Security Top 10, ASVS). Úsala siempre que se diseñe o programe un endpoint, login, sesión, formulario, webhook, subida de archivos, panel de administración, tabla o migración, integración con terceros (pagos, WhatsApp, IA), cabeceras HTTP, CORS, cookies o despliegue; y cuando pidan "revisar seguridad", "auditar", "hardening", "¿esto es seguro?", "pentest de mi app", "proteger la API", "proteger la base de datos", "fuga de datos", "multi-tenant", "IDOR", "inyección SQL", "XSS", "CSRF", "secretos" o "OWASP". Pensada para Node/Express + Angular + PostgreSQL (Render, Netlify, Neon, Cloudflare), pero las reglas sirven para cualquier stack.
---

# Seguridad por diseño

La seguridad no es una fase al final: es una forma de escribir cada línea. Esta skill tiene dos modos:

- **Construir**: aplicar las normas mientras se programa (lo normal; no esperar a que lo pidan).
- **Revisar**: auditar código existente y entregar hallazgos priorizados.

Responde siempre en el idioma del usuario. Nunca inventes una vulnerabilidad ni un "todo está bien": cada afirmación sale de código leído o de una prueba ejecutada.

## Los 12 principios (se aplican en todo)

1. **Denegar por defecto.** Toda ruta nace protegida; abrirla es una decisión explícita y comentada (`// público: lo llama Meta`).
2. **El servidor decide.** Nada que venga del cliente es confiable: ni el body, ni la query, ni cabeceras, ni el JWT sin verificar, ni el `tenant_id` que mande la pantalla. La identidad y el negocio salen del token verificado.
3. **Autorizar cada objeto, no solo la ruta.** `WHERE id = $1 AND tenant_id = $2` siempre (anti-IDOR/BOLA). Si no aparece, es 404, no 403 (no confirmar que existe).
4. **Validar con lista blanca y límites.** Tipo, largo máximo, rango, lista cerrada. Lo mismo en pantalla, API y CHECK de la base. Rechazar campos desconocidos al escribir (anti mass-assignment).
5. **Consultas parametrizadas siempre.** Cero concatenación de SQL con datos; identificadores dinámicos (columna, orden) solo desde una lista blanca.
6. **Codificar al mostrar.** Escapar según contexto (HTML, atributo, URL, JS). En Angular, nunca `bypassSecurityTrust*` con datos de usuario ni `innerHTML` sin sanitizar.
7. **Secretos fuera del código y de los logs.** Variables de entorno, rotación documentada, comparación en tiempo constante (`crypto.timingSafeEqual`).
8. **Fallar cerrado.** Si falta una configuración de seguridad (secreto de webhook, clave de cifrado) en producción, se niega el acceso; no se "sigue sin verificar".
9. **Mínimo privilegio.** Rol de base sin superusuario para la app, tokens con alcance y caducidad cortos, super-admin separado de dueño de negocio.
10. **Todo webhook y callback se autentica.** Firma HMAC sobre el cuerpo crudo + idempotencia (no procesar dos veces el mismo evento).
11. **Registrar sin filtrar.** Auditoría de acciones sensibles (quién, qué, cuándo, desde dónde) sin contraseñas, tokens, documentos ni cuerpos completos con datos personales.
12. **Probar el ataque, no solo el camino feliz.** Cada regla de acceso tiene su prueba negativa: otro negocio, otro rol, sin token, token vencido, campo de más, valor fuera de rango.

## Modo Construir: qué cargar según la tarea

Lee solo la referencia que toca (no todas):

| Vas a crear o tocar... | Lee |
|---|---|
| Endpoints, auth, sesiones, JWT, roles, multi-tenant, rate limit, webhooks, subida de archivos, integración IA | `references/api.md` |
| Páginas, formularios, Angular, cabeceras HTTP, CSP, cookies, CORS, CSRF, redirecciones, sitio estático | `references/web.md` |
| Tablas, migraciones, roles de Postgres, RLS, cifrado, respaldos, datos personales | `references/base-de-datos.md` |
| `.env`, llaves, CI/CD, dependencias, despliegue, logs, monitoreo | `references/secretos-y-operacion.md` |

Antes de entregar cualquier cambio con superficie nueva (ruta, tabla, formulario, integración), recorre la **lista mínima de entrega**:

- [ ] ¿Quién puede llamarlo? Middleware de auth + rol + verificación del objeto por negocio.
- [ ] ¿Qué entra? Validación con límites y lista blanca; mensajes de error claros sin detalles internos.
- [ ] ¿Qué sale? Solo los campos necesarios (nunca `SELECT *` hacia el cliente con hashes, tokens o datos de otros).
- [ ] ¿Se puede abusar? Rate limit, tamaño máximo, paginación con tope, tiempo máximo de llamadas externas.
- [ ] ¿Deja rastro? Auditoría de la acción sensible; logs sin secretos.
- [ ] ¿Tiene prueba negativa? Al menos: sin token (401), otro rol (403), otro negocio (404), dato inválido (400).
- [ ] ¿Falla cerrado? Sin configuración en producción = rechazo, no "modo abierto".

## Modo Revisar: cómo auditar

1. **Mapear la superficie** antes de opinar: rutas públicas vs protegidas (`grep -rn "router\.\(get\|post\|put\|patch\|delete\)"`), webhooks, subida de archivos, panel admin, jobs, integraciones. Corre `scripts/revision-rapida.sh <repo>` para una primera pasada de patrones de riesgo; sus resultados son **pistas, no hallazgos** hasta leer el código.
2. **Seguir el dato**: de la petición al SQL y de vuelta a la pantalla. Ahí aparecen IDOR, inyección, XSS y fugas.
3. **Verificar con evidencia**: leer el código exacto y, si se puede, reproducir con una prueba (curl contra local o una prueba automatizada con base desechable). Nunca atacar producción ni sistemas de terceros.
4. **Clasificar** cada hallazgo (ver `references/revision.md`): Crítica / Alta / Media / Baja / Informativa, con escenario de explotación concreto, archivo:línea, arreglo propuesto y prueba que lo demuestra.
5. **Arreglar en ramas pequeñas** (una por tema), cada una con su prueba negativa, y volver a correr las suites.
6. **Informe honesto**: qué se revisó, qué no, qué quedó como riesgo aceptado y qué decide el dueño del producto. Reconocer lo que está bien hecho también (evita "arreglar" lo que no está roto).

Formato del informe y escala de severidad: `references/revision.md`.

## Errores que esta skill debe evitar

- Proponer "seguridad" que rompe el producto (bloquear CORS del propio dominio, CSP que tumba el sitio): probar en local/staging antes.
- Agregar dependencias pesadas para algo que la plataforma ya trae (`crypto`, `helmet`, validadores existentes).
- Silenciar un error de seguridad para que pase una prueba.
- Pedir al usuario que pegue secretos en el chat. Si aparece uno, recomendar rotarlo.
- Marcar como vulnerabilidad algo teórico sin camino de explotación en este código (márcalo Informativo).
