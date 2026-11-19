# Revisión de seguridad: severidad, verificación e informe

## Escala de severidad

Combina **impacto** (qué se pierde) y **facilidad** (quién puede hacerlo y con qué):

| Severidad | Ejemplos |
|---|---|
| **Crítica** | Leer o modificar datos de otro negocio sin credenciales especiales (IDOR masivo); inyección SQL; ejecutar código en el servidor; tomar cuenta de super-admin; secreto de producción público; webhook de pagos que activa planes sin firma. |
| **Alta** | IDOR que requiere estar logueado en cualquier negocio; escalada de rol dentro del negocio; XSS almacenado en una pantalla que ven otros; bypass de 2FA; reset de contraseña predecible; sin rate limit en login. |
| **Media** | XSS reflejado con interacción; CSRF en acciones no críticas; enumeración de usuarios; falta de revocación de sesiones; datos personales de más en una respuesta; CORS demasiado amplio con credenciales. |
| **Baja** | Cabeceras de seguridad faltantes sin explotación directa; mensajes de error con detalles internos; versiones expuestas. |
| **Informativa** | Endurecimiento recomendado, defensa en profundidad, riesgo teórico sin camino de explotación en este código. |

Bajar un nivel si la explotación necesita condiciones poco realistas; subir uno si afecta a todos los negocios a la vez o a dinero/facturación.

## Verificar antes de reportar

Un hallazgo entra al informe solo si:

1. Se leyó el código exacto (archivo:línea) y se siguió el dato de punta a punta.
2. Se descartaron protecciones en otra capa (middleware global, CHECK de la base, validación previa, proxy).
3. Se puede describir el escenario: "un usuario con rol X del negocio A hace la petición Y y obtiene Z".
4. Idealmente, hay una prueba que lo reproduce (y que pasará cuando se corrija).

Si algo no se pudo verificar, va como **Plausible** y se dice qué faltó para confirmarlo.

## Formato de cada hallazgo

```
### [SEV] Título corto en lenguaje claro
- Dónde: ruta/archivo.js:123 (endpoint POST /api/...)
- Qué pasa: una frase.
- Cómo se explota: pasos concretos (quién, qué petición, qué obtiene).
- Impacto: qué datos/dinero/negocios.
- Arreglo: el cambio mínimo y correcto (con fragmento de código si ayuda).
- Prueba: el caso negativo que lo cubre.
- Estado: Confirmado | Plausible
```

## Estructura del informe

1. **Resumen ejecutivo** (5 líneas, sin jerga): estado general, lo más urgente, qué está bien hecho.
2. **Alcance**: repos, ramas/commits, qué se revisó y qué no (y por qué).
3. **Hallazgos** ordenados por severidad.
4. **Lo que está bien** (para no tocarlo).
5. **Plan**: ramas/PR propuestos, uno por tema, en orden de prioridad.
6. **Decisiones del dueño**: riesgos que requieren su elección (aceptar, mitigar, transferir).

## Atajos de revisión por tipo de cambio (para revisar un PR)

- **Ruta nueva** → auth + rol + objeto por negocio + validación + DTO de salida + prueba negativa.
- **Tabla nueva** → `tenant_id` + FK + índices + CHECK + qué columnas son sensibles.
- **Integración nueva** → firma/verificación del callback, idempotencia, timeouts, secreto en env, qué datos se envían al tercero.
- **Pantalla nueva** → sin `bypassSecurityTrust`/`innerHTML` con datos externos; reglas de la UI repetidas en la API; enlaces externos con `rel="noopener"`.
- **Cambio de dependencias** → audit, changelog de mayores, scripts de instalación.
- **Cambio de infraestructura** → secretos, CORS, cabeceras, CSP, DNS, quién tiene acceso.
