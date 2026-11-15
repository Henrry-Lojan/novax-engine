# Novax Engine · demo de los dos tiempos

| Archivo | Qué es |
|---|---|
| `supabase.sql` | La base de datos: tablas, cálculos y 20 rubros de ejemplo de 1213, 1421, 1461 y 1810. |
| `index.html` | Tablero: tarjetas con una frase que explica cada número, gráficos, el estado por obra y los atrasos externos. Se filtra por proyecto. |
| `plan.html` | Plan y ejecución, como la hoja del Excel: lo planificado y lo ejecutado en la misma fila. Tiempo 1: se entrega el plan y queda bloqueado, pero se sigue viendo. Tiempo 2: a las 2 semanas se anota lo ejecutado en esa misma tabla y sale el PPC. |
| `config.js` | Los dos datos de tu Supabase. **Es el único archivo que se edita.** |
| `app.js`, `estilo.css` | Lo que comparten las tres páginas. No se tocan. |

## 1. Supabase (la base de datos)

1. Entra a supabase.com → **New project**. Nombre: `novax-engine`. Región: *South America (São Paulo)*. Guarda la
   contraseña.
2. Menú izquierdo → **SQL Editor** → **New query**. Pega todo `supabase.sql` → **Run**. Tiene que decir *Success*.
3. **Project Settings → API Keys**. Copia la **Project URL** y la clave **publishable** (o *anon public*) y pégalas en
   `config.js`, entre las comillas.

## 2. GitHub Pages (la página web)

1. github.com → **New repository** → nombre `novax-engine`, **Public** → Create.
2. **uploading an existing file** → arrastra los 7 archivos → **Commit changes**.
3. **Settings → Pages** → *Branch*: `main`, carpeta `/ (root)` → **Save**.
4. En 1 o 2 minutos queda en `https://henrry-lojan.github.io/novax-engine/`.

Si después cambias `config.js`, súbelo otra vez con *Add file → Upload files*: reemplaza al anterior.

## 3. Cómo mostrarla

1. **Tablero:** los datos de ejemplo ya muestran las cuatro lecturas: 1213 éxito, 1461 causa externa, 1421 y 1810
   evitable.
2. **Plan y ejecución · Tiempo 1:** elige 1213 → **Nuevo plan**, deja el lunes 16-nov, pon cantidades en 2 o 3
   rubros y marca si están listos → **Enviar plan**. El plan queda **bloqueado** con un candado, sigue a la vista y sale
   la calidad del plan con sus 6 criterios.
3. **Tiempo 2:** en ese mismo plan, anota lo ejecutado. El cumplimiento de cada fila se pinta mientras escribes. Si
   uno no llega, elige la causa y los días → **Cerrar plan**. Sale el PPC y qué significa.
4. Vuelve al **Tablero**: ya está actualizado, sin copiar nada.

Para volver a los datos de ejemplo, corre otra vez `supabase.sql` en el SQL Editor.

## Cómo calcula

- **Nota del plan (0 a 100):** promedio de 6 criterios. Tres los revisa el sistema solo:
  - entrega a tiempo: hasta el viernes antes del lunes de inicio;
  - cronograma: el rubro cae en esas 2 semanas;
  - cantidad realista: no pasa de 10 días de rendimiento.

  Los otros tres los responde el supervisor: secuencia, recursos y anticipación. 80 o más es buen plan; de 65 a 79,
  revisar; menos de 65, rehacer.
- **PPC:** rubros cumplidos (ejecutado ≥ planificado) ÷ rubros del plan.
- **Cumplimiento de cantidades:** lo ejecutado en dólares (precio unitario), sin pasar de lo planificado, ÷ lo
  planificado.
- **Fallas evitables:** rubros no cumplidos por material, cuadrilla o equipo ÷ rubros del plan.
- **Atraso externo:** días por clima, LUG o diseño, con la lista para sustentar las SDC.

## Ojo

La clave *publishable* va visible en la página: así funciona Supabase y no es un secreto. La página solo puede leer y
entregar o cerrar planes; no puede borrar ni cambiar lo ya cerrado. Pero cualquiera con el enlace puede cargar planes,
así que úsala con datos de ejemplo. Para datos reales, el siguiente paso es poner usuario y contraseña (Supabase Auth).
