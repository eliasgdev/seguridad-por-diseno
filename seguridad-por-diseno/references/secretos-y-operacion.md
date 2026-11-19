# Secretos, dependencias, despliegue y monitoreo

## Índice
1. Secretos
2. Dependencias y cadena de suministro
3. CI/CD y repositorio
4. Despliegue y configuración
5. Logs y monitoreo
6. Respuesta a incidentes

---

## 1. Secretos

- Inventario: cada secreto con dueño, dónde vive (Render/Netlify/Neon/gestor), para qué sirve y cómo se rota.
- `.env` en `.gitignore`; `.env.example` con nombres y comentarios, sin valores reales.
- Generar con `openssl rand -base64 48` (o `crypto.randomBytes(48)`); uno distinto por entorno y por propósito (no reutilizar el secreto JWT como llave de cifrado).
- Validar al arrancar que los secretos obligatorios existen en producción y abortar si faltan (fallar cerrado), sin imprimir sus valores.
- Si un secreto llegó a git: **rotarlo primero**, después limpiar el historial (git filter-repo/BFG) y forzar push coordinado. Limpiar el historial sin rotar no sirve: ya pudo copiarse.
- Si un secreto se pegó en un chat, ticket o captura: rotarlo.
- Escanear: `gitleaks detect --source .` o `trufflehog git file://. --only-verified` en local y en CI.

## 2. Dependencias

- `npm ci` con lockfile versionado; revisar diffs del lockfile en los PR.
- `npm audit --omit=dev` en CI (fallar en high/critical de producción); Dependabot/Renovate con PR por actualización.
- Antes de agregar un paquete: ¿la plataforma ya lo hace?, ¿mantenido?, ¿descargas?, ¿nombre exacto (typosquatting)?, ¿scripts `postinstall`?
- Paquetes privados con scope propio (`@miorg/`) y registro configurado, para evitar dependency confusion.
- Imágenes Docker con tag fijo/digest, usuario no root, base mínima.

## 3. CI/CD y repositorio

- Rama principal protegida (cuando el plan lo permita): PR obligatorio, CI verde, sin force-push.
- GitHub Actions: `permissions:` mínimos por workflow (`contents: read`), acciones de terceros fijadas por SHA, nunca `pull_request_target` con checkout del código del PR.
- Secretos de CI solo en los jobs que los usan; nunca `echo` de secretos.
- Suites de seguridad en CI: aislamiento multi-tenant, pruebas negativas de auth, escaneo de secretos y `npm audit`.

## 4. Despliegue y configuración

- `NODE_ENV=production` (activa comportamientos seguros de librerías y nuestras validaciones de fallar-cerrado).
- HTTPS en todo, HSTS, redirección de HTTP a HTTPS.
- Sin endpoints de depuración, seeds ni usuarios demo en producción; `/health` sin datos internos.
- Super-admin: correo dedicado con 2FA, no la cuenta de uso diario de un negocio.
- Planes gratuitos que se suspenden o duermen: no son aceptables para APIs con clientes que pagan (disponibilidad también es seguridad).
- DNS: registros CNAME huérfanos (apuntando a servicios borrados) permiten subdomain takeover; limpiarlos al dar de baja un servicio.

## 5. Logs y monitoreo

- Log estructurado con id de correlación por petición; nivel `info` en producción.
- Nunca registrar: contraseñas, tokens, cabeceras `Authorization`/`Cookie`, cuerpos de webhooks completos, documentos, números completos de identificación. Enmascarar teléfonos y correos si se registran.
- Alertas: picos de 401/403/429, errores 5xx, fallos de verificación de firmas de webhook, logins de super-admin, cambios de rol, exportes masivos.
- Retención de logs definida y acceso restringido.

## 6. Respuesta a incidentes (guion corto)

1. **Contener**: rotar credenciales afectadas, revocar sesiones (`token_version++` masivo), desactivar la ruta o integración comprometida.
2. **Preservar evidencia**: copiar logs y estado antes de limpiar.
3. **Evaluar alcance**: qué datos, qué negocios, desde cuándo (auditoría + logs del proveedor).
4. **Corregir** la causa raíz con prueba que la cubra.
5. **Notificar** a los afectados y, si hay datos personales, a la autoridad cuando la ley lo exija (en Colombia, la SIC; RGPD: 72 h).
6. **Lección aprendida** escrita: qué control faltó y en qué lista de esta skill se agrega.
