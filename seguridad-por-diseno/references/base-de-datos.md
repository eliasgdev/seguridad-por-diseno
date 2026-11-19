# Bases de datos seguras (PostgreSQL; Neon, Render, Supabase, RDS)

## Índice
1. Conexión y credenciales
2. Roles y mínimo privilegio
3. Aislamiento multi-tenant (app + RLS)
4. Integridad: la base se protege sola
5. Datos sensibles: cifrado, hash y minimización
6. Migraciones seguras
7. Respaldos y recuperación
8. Auditoría
9. Rendimiento como seguridad (DoS)
10. Entornos: producción, staging y pruebas

---

## 1. Conexión

- TLS obligatorio (`sslmode=require`, idealmente `verify-full` con la CA del proveedor).
- La cadena de conexión vive en variables de entorno / gestor de secretos; nunca en el repo, ni en logs, ni en mensajes de error.
- Red: si el proveedor lo permite, restringir por IP o red privada; no exponer el puerto 5432 a internet con usuario `postgres`.
- Pool con límite (`max`) y `idleTimeoutMillis`; con poolers (PgBouncer/Neon pooler) usar la URL "pooled" para la app y la "direct/unpooled" para migraciones.

## 2. Roles y mínimo privilegio

Separar al menos tres roles:

```sql
-- dueño del esquema: solo para migraciones (CI/despliegue), no para la app
CREATE ROLE app_owner LOGIN PASSWORD '...';
-- la app: DML sin DDL
CREATE ROLE app_rw LOGIN PASSWORD '...' NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT USAGE ON SCHEMA public TO app_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_rw;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
-- lectura para reportes/BI
CREATE ROLE app_ro LOGIN PASSWORD '...';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_ro;

-- límites por rol (anti consultas eternas)
ALTER ROLE app_rw SET statement_timeout = '30s';
ALTER ROLE app_rw SET idle_in_transaction_session_timeout = '60s';
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

- Tablas de auditoría: a `app_rw` solo `INSERT` y `SELECT` (sin `UPDATE/DELETE`) para que sea inmutable.
- Si la app hoy corre como dueño (común), documentarlo como riesgo y planear la separación; no cambiarlo en caliente sin probar en staging.

## 3. Multi-tenant

- Cada tabla de negocio lleva `tenant_id NOT NULL REFERENCES tenants(id)` + índice que empiece por `tenant_id`.
- Unicidad por negocio: `UNIQUE (tenant_id, code)`, no `UNIQUE (code)` global (filtra existencia entre negocios).
- FKs compuestas cuando un hijo referencia a un padre del mismo negocio, para que la base impida mezclar negocios:

```sql
ALTER TABLE products ADD CONSTRAINT products_tenant_id_uq UNIQUE (tenant_id, id);
ALTER TABLE order_items ADD CONSTRAINT order_items_product_fk
  FOREIGN KEY (tenant_id, product_id) REFERENCES products (tenant_id, id);
```

- **Row Level Security** como segunda red (la primera es el `WHERE tenant_id` de la app):

```sql
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE products FORCE ROW LEVEL SECURITY;  -- aplica también al dueño de la tabla
CREATE POLICY tenant_isolation ON products
  USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid);
-- en la app, por transacción:  SELECT set_config('app.tenant_id', $1, true);
```

  Con pooler en modo transacción, usar `set_config(..., true)` (local a la transacción), nunca `SET` de sesión. Activar RLS en una base existente se hace tabla por tabla, con el barrido de aislamiento corriendo.
- Procesos de plataforma (super-admin, jobs) usan un rol con `BYPASSRLS` separado y auditado.

## 4. Integridad: la base se protege sola

La API valida, pero la base es la última línea (scripts, jobs, bugs):

- `NOT NULL` por defecto; `CHECK` con los mismos límites de la API (largo, rango, listas cerradas); `VARCHAR(n)` con `n` real.
- Estados como lista cerrada: `CHECK (status IN ('open','closed'))` o tipo `ENUM`/tabla de catálogo.
- Dinero en `NUMERIC(14,2)` (nunca `float`); cantidades no negativas con `CHECK (qty >= 0)`.
- Índices únicos parciales para reglas de negocio (`UNIQUE (channel, phone) WHERE status = 'open'`).
- Idempotencia: columna `client_ref`/`event_id` con índice único para operaciones que el cliente o un proveedor pueden repetir.

## 5. Datos sensibles

Clasificar cada columna: pública / interna / personal / sensible / secreto.

| Tipo | Cómo guardarlo |
|---|---|
| Contraseñas | Hash lento (bcrypt/argon2id). Nunca recuperable. |
| Tokens de un solo uso (reset, invitación, API keys) | Guardar `sha256(token)`, mostrar el token una sola vez. |
| Secretos de integración del cliente (certificados .p12, claves DIAN, tokens de terceros) | Cifrado de aplicación AES-256-GCM con llave en variable de entorno (KMS si hay), IV aleatorio por registro, llave rotable con versión. |
| Datos personales (cédula, teléfono, dirección) | Minimizar: guardar solo lo que se usa. Enmascarar en listados. Acceso auditado. |
| Datos de salud o financieros | Además: acceso por rol específico, retención definida. |

- Nunca guardar números completos de tarjeta (PCI): que los maneje la pasarela.
- Exportes y respaldos heredan la sensibilidad: cifrados y con acceso restringido.
- Derecho de supresión (Ley 1581 / RGPD): saber borrar o anonimizar a una persona en todas las tablas.

## 6. Migraciones seguras

- Idempotentes (`IF NOT EXISTS`, `DROP CONSTRAINT IF EXISTS` + `ADD`), en transacción, versionadas en git.
- Ensayar en una rama/copia (Neon branch o snapshot) con datos parecidos a producción; snapshot antes de aplicar en producción.
- Cambios que bloquean (agregar `NOT NULL` con default calculado, índices grandes): `CREATE INDEX CONCURRENTLY`, patrón expand → migrate → contract.
- Nunca `DROP` de columnas/tablas en el mismo despliegue que deja de usarlas; primero dejar de usarlas, luego borrar.
- Al agregar un valor a un `CHECK` de lista cerrada, actualizar el CHECK en la misma migración (si no, el arranque o los inserts fallan).

## 7. Respaldos

- Automáticos diarios + PITR si el proveedor lo ofrece; retención acorde al negocio (≥ 7 días, ideal 30).
- **Probar la restauración** periódicamente (un respaldo que nunca se restauró no es un respaldo).
- Copia fuera del proveedor principal (pg_dump cifrado a otro almacenamiento) para el escenario "se cayó/suspendió la cuenta".
- Documentar RPO/RTO: cuánto dato se puede perder y en cuánto se vuelve.

## 8. Auditoría

- Tabla `audit_logs` inmutable: `tenant_id, user_id, action, entity, entity_id, ip, user_agent, details (sin secretos), created_at`.
- Registrar: login (éxito/fallo), cambios de rol/permisos, cambios de precio, anulaciones, descuentos, exportes, acceso de super-admin a datos de un negocio, cambios de configuración fiscal o de pagos.
- `pgaudit` o los logs del proveedor para acciones directas en la base (consola SQL).

## 9. Rendimiento como seguridad

- Índices en toda columna usada en `WHERE` de rutas públicas o frecuentes; un `seq scan` en una tabla grande es un DoS barato.
- `LIMIT` siempre en listados; keyset pagination para tablas grandes.
- `statement_timeout` por rol; consultas de reportes en réplica de lectura si existe.

## 10. Entornos

- Producción, staging y pruebas en bases (o ramas) distintas, con credenciales distintas.
- Las suites destructivas verifican el nombre de la base antes de correr (ej. solo si termina en `_test` o `_iso`) para no borrar producción por error.
- Datos de producción en staging: anonimizados.
- Las credenciales de producción no viven en el portátil de desarrollo si no hace falta.
