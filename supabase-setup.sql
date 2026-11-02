-- ============================================================
--  FTTH Master · configuración de la nube (Supabase, plan gratis)
--  Pega TODO este archivo en Supabase > SQL Editor > Run.
--  Es seguro volver a ejecutarlo: no borra tus datos.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

create sequence if not exists ftth_seq;

-- Tablas. Nadie las lee directamente: solo se accede por las funciones de abajo.
create table if not exists ftth_config (
  id int primary key default 1 check (id = 1),
  owner_hash text not null
);
create table if not exists ftth_registros (
  id text primary key,
  data jsonb,
  upd bigint not null,
  srv bigint not null default nextval('ftth_seq'),
  deleted boolean not null default false
);
create table if not exists ftth_fotos (
  id text primary key,
  registro text not null,
  kind text not null default 'foto',
  name text,
  data text not null,
  upd bigint not null
);
create table if not exists ftth_enlaces (
  hash text primary key,
  nombre text not null,
  editar boolean not null default false,
  fotos boolean not null default false,
  pagos boolean not null default false,
  creado bigint not null,
  revocado boolean not null default false
);
create index if not exists ftth_registros_srv on ftth_registros (srv);
create index if not exists ftth_fotos_registro on ftth_fotos (registro);

alter table ftth_config enable row level security;
alter table ftth_registros enable row level security;
alter table ftth_fotos enable row level security;
alter table ftth_enlaces enable row level security;
revoke all on ftth_config, ftth_registros, ftth_fotos, ftth_enlaces from anon, authenticated;

-- Utilidades -------------------------------------------------
create or replace function ftth_h(c text) returns text
language sql immutable set search_path = public, extensions as $$
  select encode(digest(convert_to(coalesce(c, ''), 'UTF8'), 'sha256'), 'hex')
$$;

-- Primera vez: define el código de administrador (mínimo 10 caracteres).
create or replace function ftth_init(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare h text := ftth_h(p_code);
begin
  if length(coalesce(p_code, '')) < 10 then raise exception 'codigo_corto'; end if;
  if exists (select 1 from ftth_config) then
    if exists (select 1 from ftth_config where owner_hash = h) then
      return jsonb_build_object('ok', true, 'nuevo', false);
    end if;
    raise exception 'ya_configurado';
  end if;
  insert into ftth_config (id, owner_hash) values (1, h);
  return jsonb_build_object('ok', true, 'nuevo', true);
end $$;

-- Devuelve los permisos de un código (administrador o enlace).
create or replace function ftth_auth(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare h text := ftth_h(p_code); r record;
begin
  if exists (select 1 from ftth_config where owner_hash = h) then
    return jsonb_build_object('owner', true, 'editar', true, 'fotos', true, 'pagos', true);
  end if;
  select * into r from ftth_enlaces where hash = h and not revocado;
  if found then
    return jsonb_build_object('owner', false, 'editar', r.editar, 'fotos', r.fotos, 'pagos', r.pagos, 'nombre', r.nombre);
  end if;
  raise exception 'codigo_invalido';
end $$;

-- Descargar cambios (solo los más nuevos que p_since).
create or replace function ftth_pull(p_code text, p_since bigint) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare perm jsonb := ftth_auth(p_code); pagos boolean; res jsonb;
begin
  pagos := (perm ->> 'pagos')::boolean;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'upd', upd, 'srv', srv, 'deleted', deleted,
      'data', case when deleted then null
                   when pagos then data
                   else data - 'pagoFecha' - 'pagoMes' end
    ) order by srv), '[]'::jsonb)
  into res from ftth_registros where srv > coalesce(p_since, 0);
  return res;
end $$;

-- Subir cambios (solo administrador o enlaces con permiso de editar).
create or replace function ftth_push(p_code text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare perm jsonb := ftth_auth(p_code); r jsonb; old record; nd jsonb; n int := 0; pagos boolean;
begin
  if not (perm ->> 'editar')::boolean then raise exception 'sin_permiso'; end if;
  pagos := (perm ->> 'pagos')::boolean;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select * into old from ftth_registros where id = r ->> 'id';
    if found and old.upd >= (r ->> 'upd')::bigint then continue; end if;
    if coalesce((r ->> 'deleted')::boolean, false) then
      insert into ftth_registros (id, data, upd, deleted) values (r ->> 'id', null, (r ->> 'upd')::bigint, true)
        on conflict (id) do update set data = null, deleted = true, upd = excluded.upd, srv = nextval('ftth_seq');
      delete from ftth_fotos where registro = r ->> 'id';
    else
      nd := r -> 'data';
      if not pagos then
        nd := nd - 'pagoFecha' - 'pagoMes';
        if found and old.data is not null then
          nd := nd || jsonb_strip_nulls(jsonb_build_object('pagoFecha', old.data -> 'pagoFecha', 'pagoMes', old.data -> 'pagoMes'));
        end if;
      end if;
      insert into ftth_registros (id, data, upd, deleted) values (r ->> 'id', nd, (r ->> 'upd')::bigint, false)
        on conflict (id) do update set data = excluded.data, deleted = false, upd = excluded.upd, srv = nextval('ftth_seq');
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'n', n);
end $$;

-- Fotos y PDF ------------------------------------------------
create or replace function ftth_foto_put(p_code text, p_id text, p_registro text, p_kind text, p_name text, p_data text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare perm jsonb := ftth_auth(p_code);
begin
  if not (perm ->> 'editar')::boolean then raise exception 'sin_permiso'; end if;
  insert into ftth_fotos (id, registro, kind, name, data, upd)
    values (p_id, p_registro, coalesce(p_kind, 'foto'), p_name, p_data, (extract(epoch from now()) * 1000)::bigint)
    on conflict (id) do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function ftth_foto_get(p_code text, p_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare perm jsonb := ftth_auth(p_code); r record;
begin
  if not (perm ->> 'fotos')::boolean then raise exception 'sin_permiso'; end if;
  select * into r from ftth_fotos where id = p_id;
  if not found then return null; end if;
  return jsonb_build_object('id', r.id, 'kind', r.kind, 'name', r.name, 'data', r.data);
end $$;

-- Enlaces (solo administrador) -------------------------------
create or replace function ftth_link_create(p_owner text, p_nombre text, p_code text, p_editar boolean, p_fotos boolean, p_pagos boolean) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare perm jsonb := ftth_auth(p_owner);
begin
  if not (perm ->> 'owner')::boolean then raise exception 'sin_permiso'; end if;
  if length(coalesce(p_code, '')) < 16 then raise exception 'codigo_corto'; end if;
  insert into ftth_enlaces (hash, nombre, editar, fotos, pagos, creado)
    values (ftth_h(p_code), coalesce(nullif(p_nombre, ''), 'Enlace'), coalesce(p_editar, false), coalesce(p_fotos, false), coalesce(p_pagos, false), (extract(epoch from now()) * 1000)::bigint);
  return jsonb_build_object('ok', true);
end $$;

create or replace function ftth_link_list(p_owner text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare perm jsonb := ftth_auth(p_owner); res jsonb;
begin
  if not (perm ->> 'owner')::boolean then raise exception 'sin_permiso'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('hash', hash, 'nombre', nombre, 'editar', editar, 'fotos', fotos, 'pagos', pagos, 'creado', creado, 'revocado', revocado) order by creado desc), '[]'::jsonb)
    into res from ftth_enlaces;
  return res;
end $$;

create or replace function ftth_link_revoke(p_owner text, p_hash text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare perm jsonb := ftth_auth(p_owner);
begin
  if not (perm ->> 'owner')::boolean then raise exception 'sin_permiso'; end if;
  update ftth_enlaces set revocado = true where hash = p_hash;
  return jsonb_build_object('ok', true);
end $$;

grant execute on function ftth_init(text), ftth_auth(text), ftth_pull(text, bigint), ftth_push(text, jsonb),
  ftth_foto_put(text, text, text, text, text, text), ftth_foto_get(text, text),
  ftth_link_create(text, text, text, boolean, boolean, boolean), ftth_link_list(text), ftth_link_revoke(text, text)
  to anon, authenticated;
