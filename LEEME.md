# FTTH Master Móvil – guía de instalación

## 1. Publicar en GitHub Pages (gratis)
1. Crea una cuenta en github.com y un repositorio público nuevo (ej. `ftth`).
2. Sube TODOS los archivos de esta carpeta (menos este LEEME si quieres).
3. Settings → Pages → Source: *Deploy from a branch* → `main` / root → Save.
4. Tu app queda en `https://TUUSUARIO.github.io/ftth/`.

## 2. Instalar en el celular
Abre esa dirección en Chrome → menú ⋮ → **Instalar app** / *Agregar a pantalla de inicio*. Funciona sin internet.
(Opcional: para generar un .apk usa pwabuilder.com con tu dirección.)

## 3. Nube con fotos (Supabase, plan gratis)
1. Cuenta gratis en supabase.com → *New project*.
2. **SQL Editor** → pega todo `supabase-setup.sql` → Run (se puede repetir sin problema).
3. **Project Settings → API**: copia *Project URL* y la clave pública (*anon* o *publishable*). NUNCA uses `service_role` ni la clave secreta.
4. En la app: menú ☰ → **Nube y enlaces** → pega URL, clave y un **código de administrador largo**. Anótalo: es tu llave maestra y no se recupera.
5. Activa *Sincronizar automáticamente*. En tu otro celular repite el paso 4 con los mismos datos.

## 4. Compartir con permisos
En **Nube y enlaces → Compartir con un enlace**: escribe la dirección pública de la app, un nombre y elige permisos:
- Puede agregar y editar
- Puede ver fotos y PDF
- Puede ver pagos y ganancias

Envía el enlace. Puedes **revocarlo** cuando quieras. El enlace contiene un código secreto: compártelo solo con quien confíes.

## Límites a tener en cuenta
- Plan gratis de Supabase: 500 MB de base de datos y se **pausa tras 1 semana sin uso** (se reactiva desde su panel). Las fotos se reducen a 1280 px para ahorrar espacio.
- Los avisos de instalaciones programadas aparecen dentro de la app (no son notificaciones del sistema).
- Haz igualmente un respaldo ZIP de vez en cuando (la app te lo recuerda cada 7 días).
