# Páginas web seguras (Angular, sitios estáticos, cualquier frontend)

Basado en OWASP Top 10 (2021) A01, A03, A05, A07 y la guía de cabeceras de OWASP.

## Índice
1. XSS y manejo del DOM en Angular
2. Cabeceras HTTP (Netlify / Cloudflare / Express)
3. Content Security Policy
4. Cookies, almacenamiento y tokens en el navegador
5. CORS
6. CSRF
7. Redirecciones, enlaces y `target=_blank`
8. Formularios públicos (contacto, leads, registro)
9. Terceros: analítica, píxeles, widgets
10. Lo que el frontend NO puede proteger

---

## 1. XSS en Angular

Angular escapa por defecto en `{{ }}` y en `[property]`. El riesgo aparece cuando se sale de eso:

- **Prohibido con datos de usuario**: `bypassSecurityTrustHtml/Url/ResourceUrl/Script/Style`. Usarlos solo con contenido propio y constante (ej. un `blob:` que la app misma creó).
- `[innerHTML]` pasa por el sanitizador de Angular, pero cualquier HTML que venga del usuario o de una IA debe tratarse como texto (`{{ }}`) salvo necesidad real; si se necesita formato, usar Markdown con un renderizador que sanee (DOMPurify).
- Nunca `ElementRef.nativeElement.innerHTML = ...`, `document.write`, `eval`, `new Function`, ni `setTimeout('string')`.
- URLs dinámicas en `href`/`src`: validar esquema (`https:`, `mailto:`, `tel:`); bloquear `javascript:` y `data:` (Angular marca `unsafe:` pero no confiar solo en eso cuando se arma el string a mano).
- `white-space: pre-wrap` para mostrar mensajes con saltos de línea en vez de convertirlos a `<br>` con innerHTML.
- SSR/prerender: no meter datos del usuario en `<script>` inline ni en JSON-LD sin escapar `</script>`.

## 2. Cabeceras HTTP mínimas

Para un sitio en Netlify (`netlify.toml`) o Cloudflare (`_headers`):

```toml
[[headers]]
  for = "/*"
  [headers.values]
    Strict-Transport-Security = "max-age=63072000; includeSubDomains; preload"
    X-Content-Type-Options = "nosniff"
    X-Frame-Options = "DENY"            # o frame-ancestors en la CSP
    Referrer-Policy = "strict-origin-when-cross-origin"
    Permissions-Policy = "camera=(), microphone=(), geolocation=(), payment=()"
    Cross-Origin-Opener-Policy = "same-origin"
    Content-Security-Policy = "..."      # ver sección 3
```

- Si la app usa la cámara (escáner de códigos) o el micrófono, habilitarlo solo para `self`: `camera=(self)`.
- En la API Express: `helmet()` ya pone la mayoría; ajustar `crossOriginResourcePolicy` si se sirven imágenes a otros dominios.
- `index.html` y `ngsw.json` sin caché larga (para que las correcciones de seguridad lleguen); assets con hash sí con caché larga.
- `security.txt` en `/.well-known/security.txt` con contacto y fecha de expiración.

## 3. Content Security Policy

Empezar estricta y abrir solo lo necesario, probando en staging con `Content-Security-Policy-Report-Only` primero:

```
default-src 'self';
script-src 'self' https://www.googletagmanager.com;
style-src 'self' 'unsafe-inline';          # Angular inyecta estilos; preferir nonce si se puede
img-src 'self' data: https:;
font-src 'self';
connect-src 'self' https://api.tudominio.com https://*.google-analytics.com;
frame-ancestors 'none';
base-uri 'self';
form-action 'self';
object-src 'none';
upgrade-insecure-requests
```

- Nunca `'unsafe-eval'` en producción. Angular (AOT) no lo necesita.
- Cada tercero (GTM, píxel de Meta, Google Sign-In, Wompi) agrega dominios: listarlos con comentario de por qué.
- `connect-src` debe incluir la URL real de la API; un error ahí rompe el login (probar).

## 4. Cookies y almacenamiento

- Cookies de sesión: `HttpOnly; Secure; SameSite=Lax` (o `Strict`), `Path` mínimo, sin `Domain` amplio salvo necesidad (subdominios).
- `localStorage`/`sessionStorage`: legible por cualquier script de la página. Nunca guardar ahí secretos de larga vida si se puede evitar; si se guarda el access token, que sea corto y la CSP fuerte.
- Al cerrar sesión: limpiar almacenamiento, caché del service worker con datos privados y llamar al endpoint que revoca el refresh token.
- PWA/service worker: no cachear respuestas de la API con datos privados en caché compartida; versionar y limpiar al cambiar de usuario.

## 5. CORS

- Lista blanca exacta de orígenes (`https://app.dominio.com`, subdominios conocidos). Nunca reflejar el `Origin` recibido ni usar `*` con `credentials: true`.
- `localhost` solo en desarrollo (por variable de entorno, no quemado en producción).
- CORS no es autenticación: un `curl` lo ignora. La API se protege con tokens igual.

## 6. CSRF

- Si la autenticación va en cabecera `Authorization: Bearer`, el CSRF clásico no aplica.
- Si va en cookie: `SameSite=Lax/Strict` + token anti-CSRF (doble envío o sincronizado) en métodos que cambian estado, y verificar `Origin`/`Referer`.
- Nunca cambiar estado con `GET`.

## 7. Redirecciones y enlaces

- Parámetros tipo `?next=` / `?returnUrl=`: aceptar solo rutas relativas internas (`/^\/(?!\/)/`) o una lista blanca de dominios. Si no, open redirect (phishing con tu dominio).
- `target="_blank"` siempre con `rel="noopener"` (y `noreferrer` si no quieres pasar el referer).
- Enlaces `wa.me`/`mailto:` con texto prellenado: `encodeURIComponent` y nada de datos personales del usuario en la URL (quedan en historiales y analítica).

## 8. Formularios públicos

- Validación en pantalla = comodidad; la seguridad está en la API (mismos límites).
- Anti-bots sin fricción: campo trampa (honeypot) oculto + tiempo mínimo de llenado + rate limit en la API; Turnstile/hCaptcha si hay abuso real.
- Consentimiento explícito para datos personales (Ley 1581 de 2012 en Colombia / RGPD): casilla no premarcada, enlace a la política, guardar fecha y versión aceptada.
- Mensajes de éxito/error que no revelen si un correo ya existe (en registro: "Si el correo es válido, te llegará un mensaje").

## 9. Terceros

- Cada script de tercero tiene acceso total a la página. Cargar solo tras consentimiento (analítica/publicidad) y desde dominios en la CSP.
- Fijar versiones y, cuando el proveedor lo permita, `integrity` (SRI) + `crossorigin`.
- Píxeles (Meta, Google Ads): no enviar datos personales en claro; si se envían (Conversions API), hashear con SHA-256 normalizado y solo con consentimiento.

## 10. Lo que el frontend NO protege

Ocultar un botón, un guard de rutas, deshabilitar un campo o validar en pantalla **no es seguridad**: todo se puede saltar con DevTools o curl. Cada regla de la UI debe existir también en la API. El código del frontend y las variables de `environment.ts` son públicos: nunca poner ahí llaves privadas (solo llaves públicas pensadas para el navegador, como `pub_` de Wompi o el client id de Google).
