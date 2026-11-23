# Arquitectura de DesarrolloModular

## Aplicación y módulos

DesarrolloModular es un monolito modular. Un proceso Node.js con Express expone la API REST. El Core ofrece autenticación, usuarios, empresas, roles, configuración, activación de módulos y acceso compartido a PostgreSQL mediante `pg`. Inventario define sus propias reglas de categorías, productos, existencias y movimientos. Las reglas del catálogo y del stock se mantienen dentro de Inventario.

Flutter consume el [contrato OpenAPI](api/openapi.yaml) mediante HTTP y JSON. En producción la conexión usa HTTPS. Express recibe y valida la solicitud, aplica la autorización, ejecuta la operación y devuelve la respuesta. El backend es el único componente de la aplicación que accede a PostgreSQL.

## Instalación y empresas

Cada cliente tiene su propia instalación del backend y su propia base PostgreSQL. Una empresa es un negocio registrado dentro de esa instalación. El MVP empieza con una empresa por instalación y conserva el aislamiento por `business_id` para admitir más empresas.

El esquema T02 usa UUID y separa cinco tablas. `businesses` y `users` pertenecen al Core. `categories`, `products` y `stock_movements` pertenecen a Inventario. Las llaves compuestas impiden mezclar categorías, productos y autores de distintos negocios. [Esquema y reglas de T02](../backend/database/README.md).

## Identidad y permisos

| Rol | Alcance inicial |
| --- | --- |
| `PLATFORM_ADMIN` | Administra empresas, cuentas de empresa y activación de módulos dentro de su instalación. Su `business_id` es nulo. |
| `ADMIN` | Consulta su empresa, administra sus empleados y catálogo, registra movimientos y consulta historial. Puede registrar ajustes. |
| `EMPLOYEE` | Consulta categorías y productos activos de su empresa y registra entradas y salidas. |

El servidor verifica el JWT y comprueba que la cuenta y, cuando corresponda, su empresa sigan activas. Después valida el rol y compara la empresa solicitada con la empresa autorizada antes de consultar o escribir datos. Las consultas de Inventario incluyen ese ámbito. La API deriva el autor de cada movimiento de la sesión. La llave de movimientos requiere un autor de la misma empresa, por lo que las cuentas `PLATFORM_ADMIN` quedan fuera de las operaciones de Inventario.

Las rutas de empresa comparten un control de ámbito. Para usuarios de empresa, el identificador que llega al repositorio procede de la sesión y debe coincidir con el UUID solicitado. Las escrituras administrativas vuelven a comprobar el rol, la empresa y el estado de la cuenta dentro de la misma transacción que modifica datos. [Aislamiento multiempresa de B05](tasks/backend/B05.md).

Las contraseñas llegan por HTTPS y se almacenan como hashes. Los perfiles omiten el hash. B03 incorpora la inicialización segura del primer administrador y define la política de contraseñas y vigencia del JWT. El despliegue usa una cuenta PostgreSQL con los permisos necesarios para su función y consultas parametrizadas.

## Activación y desactivación

Los módulos se distribuyen dentro de la aplicación. El Core controla el estado de cada módulo por empresa. Express comprueba ese estado en todas las operaciones de Inventario y Flutter puede consultarlo para decidir qué funciones mostrar. Desactivar Inventario bloquea sus operaciones para esa empresa y conserva el catálogo, el stock y el historial. B06 definirá la persistencia con una migración versionada.

## Catálogo, stock e historial

Un producto comienza con existencia cero. Una entrada registra la existencia inicial. Los cambios de existencias pasan por el mismo flujo de movimientos. Una salida recibe una cantidad positiva y una razón. El servidor calcula el delta negativo. Un ajuste recibe la existencia física contada y una justificación. El servidor calcula la diferencia respecto de la existencia actual.

La operación de stock bloquea el producto con `SELECT ... FOR UPDATE` dentro de una transacción. La actualización del stock y la escritura del historial se confirman juntas. El servidor valida la unidad, el rango y el saldo disponible antes de confirmar. El historial registra usuario, fecha, saldo anterior, delta y saldo posterior, y permanece inmutable.

PostgreSQL usa `NUMERIC(12,2)` para precios y `NUMERIC(14,3)` para cantidades. La API intercambia ambos como cadenas decimales para conservar precisión. Piezas y cajas admiten cantidades enteras. Kilogramos, metros y litros admiten hasta tres decimales.

## Separación del código

Las rutas delimitan la interfaz HTTP. La lógica de negocio y el acceso a datos se separan cuando tienen responsabilidades distintas, como en la autorización y los movimientos transaccionales. El proceso de Express, el pool de PostgreSQL y el Core se comparten dentro de la instalación. La implementación inicial se limita a los flujos de Core e Inventario acordados para el MVP.
