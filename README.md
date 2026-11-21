# Seguridad por diseño

Skill para **Claude Code** con normas de ciberseguridad para **crear y revisar** páginas web, APIs y bases de datos seguras desde el primer commit. Se basa en OWASP Top 10, OWASP API Security Top 10 y ASVS, explicados en español y llevados a código concreto.

Está pensada para Node.js/Express + Angular + PostgreSQL (desplegados en Render, Netlify, Neon o Cloudflare), pero las reglas sirven para cualquier stack.

## Origen

Estas normas salieron de auditorías y endurecimiento de seguridad que hice sobre sistemas propios y de clientes alojados en repositorios privados (APIs multi-negocio, webhooks, paneles de administración y bases PostgreSQL). Cada regla responde a un hallazgo real o a algo que hubo que corregir.

## Qué hace

Tiene dos modos:

- **Construir.** Mientras Claude programa un endpoint, un login, un webhook, una tabla o un formulario, aplica las normas sin que se las pidas: autorización por objeto, validación con límites, consultas parametrizadas, firma de webhooks, secretos fuera del código y pruebas negativas.
- **Revisar.** Audita un repositorio. Mapea la superficie de ataque, sigue el dato desde la petición hasta el SQL y de vuelta a la pantalla, verifica cada hallazgo con evidencia y entrega un informe por severidad con el arreglo y la prueba de cada uno.

## Contenido

```
seguridad-por-diseno/
├── SKILL.md                         # 12 principios, cuándo leer cada guía, lista mínima de entrega
├── references/
│   ├── api.md                       # auth, JWT, roles, multi-tenant (IDOR/BOLA), validación, rate limit,
│   │                                # webhooks, archivos, SSRF, funciones con IA, pruebas negativas
│   ├── web.md                       # XSS en Angular, cabeceras, CSP, cookies, CORS, CSRF, formularios, terceros
│   ├── base-de-datos.md             # roles de Postgres, RLS, CHECK, cifrado, migraciones, respaldos, auditoría
│   ├── secretos-y-operacion.md      # secretos, dependencias, CI/CD, despliegue, logs, incidentes
│   └── revision.md                  # escala de severidad, cómo verificar, formato del informe
└── scripts/
    └── revision-rapida.sh           # primera pasada de patrones de riesgo (solo lee, no ejecuta nada)
```

## Instalación

Para todos tus proyectos:

```bash
git clone https://github.com/eliasgdev/seguridad-por-diseno.git
mkdir -p ~/.claude/skills
cp -r seguridad-por-diseno/seguridad-por-diseno ~/.claude/skills/
```

Para un solo proyecto, cópiala en `.claude/skills/` dentro del repositorio.

Claude Code la carga sola cuando la tarea toca seguridad. También puedes pedirla directamente: "revisa la seguridad de esta API con la skill seguridad-por-diseno".

## Revisión rápida sin Claude

```bash
bash seguridad-por-diseno/scripts/revision-rapida.sh /ruta/a/tu/repo
```

El script busca patrones de riesgo: secretos en el código, SQL concatenado, `UPDATE` sin el filtro del negocio, `bypassSecurityTrust`, `innerHTML`, CORS abierto, TLS desactivado, `jwt.verify` sin algoritmo fijo y webhooks. **Cada resultado es una pista para revisar a mano, no una vulnerabilidad confirmada.**

## Aviso

Esta skill ayuda a escribir y revisar código más seguro, pero no reemplaza una auditoría profesional ni una prueba de penetración autorizada. Úsala solo sobre sistemas propios o con permiso explícito.

## Licencia

MIT

---

<a href="https://avirexis.com/?utm_source=github&utm_medium=readme&utm_campaign=seguridad-por-diseno"><picture><source media="(prefers-color-scheme: dark)" srcset="https://avirexis.com/avx-logo-nav-white.png"><img src="https://avirexis.com/avx-logo-nav.png" alt="Avirexis" height="22"></picture></a>

Hecho por [Avirexis](https://avirexis.com/?utm_source=github&utm_medium=readme&utm_campaign=seguridad-por-diseno), software de gestión para negocios hecho en Colombia.
