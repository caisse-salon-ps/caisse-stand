-- =====================================================================
--  Caisse du stand : schéma Supabase
--  À coller dans Supabase > SQL Editor > New query > Run.
--  Peut être relancé sans danger (il ne supprime aucune donnée).
-- =====================================================================

-- ---------- 1. Tables ------------------------------------------------
-- Chaque table stocke des documents JSON (id + data), ce qui évite toute
-- migration quand l'appli évolue. updated_at est posé par le serveur.

create table if not exists public.products (id text primary key, data jsonb not null, updated_at timestamptz not null default clock_timestamp());
create table if not exists public.sales    (id text primary key, data jsonb not null, updated_at timestamptz not null default clock_timestamp());
create table if not exists public.voids    (id text primary key, data jsonb not null, updated_at timestamptz not null default clock_timestamp());
create table if not exists public.moves    (id text primary key, data jsonb not null, updated_at timestamptz not null default clock_timestamp());
create table if not exists public.config   (id text primary key, data jsonb not null, updated_at timestamptz not null default clock_timestamp());

-- Sauvegardes quotidiennes (une ligne par jour, 30 jours conservés).
create table if not exists public.snapshots (
  day      date primary key,
  taken_at timestamptz not null default now(),
  data     jsonb not null
);

create index if not exists products_updated_idx on public.products (updated_at);
create index if not exists sales_updated_idx    on public.sales    (updated_at);
create index if not exists voids_updated_idx    on public.voids    (updated_at);
create index if not exists moves_updated_idx    on public.moves    (updated_at);
create index if not exists config_updated_idx   on public.config   (updated_at);

-- ---------- 2. Horodatage serveur -----------------------------------
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['products', 'sales', 'voids', 'moves', 'config'] loop
    execute format('drop trigger if exists touch on public.%I', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_updated_at()', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
alter table public.snapshots enable row level security;

-- ---------- 3. Rôles ------------------------------------------------
-- gestionnaire : app_metadata.role = 'manager' (voir le mode d'emploi)
-- vendeur      : tout autre utilisateur connecté
create or replace function public.is_manager() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'manager'
$$;

-- ---------- 4. Droits d'accès (aucun accès sans connexion) ----------
revoke all on public.products, public.sales, public.voids, public.moves, public.config, public.snapshots from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.products, public.sales, public.voids, public.moves, public.config to authenticated;
grant insert, update on public.products, public.config, public.voids to authenticated;
grant insert on public.sales, public.moves to authenticated;

do $$
declare t text;
begin
  foreach t in array array['products', 'sales', 'voids', 'moves', 'config'] loop
    execute format('drop policy if exists "lecture" on public.%I', t);
    execute format('create policy "lecture" on public.%I for select to authenticated using (true)', t);
  end loop;
end $$;

-- Catalogue et réglages : gestionnaire seulement.
drop policy if exists "gestionnaire_ajout" on public.products;
drop policy if exists "gestionnaire_modif" on public.products;
create policy "gestionnaire_ajout" on public.products for insert to authenticated with check (public.is_manager());
create policy "gestionnaire_modif" on public.products for update to authenticated using (public.is_manager()) with check (public.is_manager());

drop policy if exists "gestionnaire_ajout" on public.config;
drop policy if exists "gestionnaire_modif" on public.config;
create policy "gestionnaire_ajout" on public.config for insert to authenticated with check (public.is_manager());
create policy "gestionnaire_modif" on public.config for update to authenticated using (public.is_manager()) with check (public.is_manager());

-- Ventes et mouvements de stock : ajout seulement (jamais modifiés ni supprimés).
drop policy if exists "ajout" on public.sales;
drop policy if exists "ajout" on public.moves;
create policy "ajout" on public.sales for insert to authenticated with check (true);
create policy "ajout" on public.moves for insert to authenticated with check (true);

-- Annulations : tout utilisateur connecté peut annuler / rétablir une vente.
drop policy if exists "ajout" on public.voids;
drop policy if exists "modif" on public.voids;
create policy "ajout" on public.voids for insert to authenticated with check (true);
create policy "modif" on public.voids for update to authenticated using (true) with check (true);

-- ---------- 5. Synchronisation incrémentale -------------------------
-- Appelée toutes les quelques secondes par chaque appareil : ne renvoie que
-- ce qui a changé depuis p_since. Réservée aux utilisateurs connectés.
create or replace function public.sync_delta(p_since timestamptz default '1970-01-01')
returns jsonb
language sql as $$
  select jsonb_build_object(
    'now',      clock_timestamp(),
    'products', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from public.products where updated_at > p_since), '[]'::jsonb),
    'sales',    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from public.sales    where updated_at > p_since), '[]'::jsonb),
    'voids',    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from public.voids    where updated_at > p_since), '[]'::jsonb),
    'moves',    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from public.moves    where updated_at > p_since), '[]'::jsonb),
    'config',   coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from public.config   where updated_at > p_since), '[]'::jsonb)
  )
$$;
revoke all on function public.sync_delta(timestamptz) from public, anon;
grant execute on function public.sync_delta(timestamptz) to authenticated;

-- ---------- 6. Maintenance quotidienne (appelée par GitHub Actions) --
-- Écrit et lit dans la base (ce qui évite la mise en pause d'un projet
-- gratuit), crée la sauvegarde du jour et efface celles de plus de 30 jours.
-- Ne renvoie que des compteurs : aucune donnée n'est exposée.
create or replace function public.maintenance() returns jsonb
language plpgsql security definer set search_path = public as $$
declare snap jsonb;
begin
  snap := jsonb_build_object(
    'products', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from products), '[]'::jsonb),
    'sales',    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from sales),    '[]'::jsonb),
    'voids',    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from voids),    '[]'::jsonb),
    'moves',    coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from moves),    '[]'::jsonb),
    'config',   coalesce((select jsonb_agg(jsonb_build_object('id', id, 'data', data)) from config),   '[]'::jsonb)
  );
  insert into snapshots (day, taken_at, data) values (current_date, now(), snap)
    on conflict (day) do update set taken_at = excluded.taken_at, data = excluded.data;
  delete from snapshots where day < current_date - 30;
  return jsonb_build_object(
    'ok', true,
    'day', current_date,
    'products', (select count(*) from products),
    'sales', (select count(*) from sales),
    'snapshots', (select count(*) from snapshots)
  );
end $$;
revoke all on function public.maintenance() from public;
grant execute on function public.maintenance() to anon, authenticated;

-- ---------- 7. Restauration d'une sauvegarde (SQL Editor uniquement) --
-- Exemple :  select public.restore_snapshot('2026-02-26');
create or replace function public.restore_snapshot(p_day date) returns jsonb
language plpgsql as $$
declare s jsonb;
begin
  select data into s from public.snapshots where day = p_day;
  if s is null then
    raise exception 'Aucune sauvegarde pour le %', p_day;
  end if;
  insert into public.products (id, data) select x.id, x.data from jsonb_to_recordset(s -> 'products') as x(id text, data jsonb)
    on conflict (id) do update set data = excluded.data;
  insert into public.sales (id, data) select x.id, x.data from jsonb_to_recordset(s -> 'sales') as x(id text, data jsonb)
    on conflict (id) do update set data = excluded.data;
  insert into public.voids (id, data) select x.id, x.data from jsonb_to_recordset(s -> 'voids') as x(id text, data jsonb)
    on conflict (id) do update set data = excluded.data;
  insert into public.moves (id, data) select x.id, x.data from jsonb_to_recordset(s -> 'moves') as x(id text, data jsonb)
    on conflict (id) do update set data = excluded.data;
  insert into public.config (id, data) select x.id, x.data from jsonb_to_recordset(s -> 'config') as x(id text, data jsonb)
    on conflict (id) do update set data = excluded.data;
  return jsonb_build_object('ok', true, 'restored', p_day);
end $$;
revoke all on function public.restore_snapshot(date) from public, anon, authenticated;

-- ---------- 8. Vue pratique pour la régie / Excel -------------------
-- Table Editor > v_ventes_lignes > Export CSV.
create or replace view public.v_ventes_lignes with (security_invoker = true) as
select s.id as vente,
       to_timestamp((s.data ->> 'ts')::bigint / 1000.0) as date_heure,
       s.data ->> 'dev' as appareil,
       l ->> 'name' as produit,
       (l ->> 'qty')::int as quantite,
       (l ->> 'unit')::numeric / 100 as prix_unitaire_eur,
       ((l ->> 'qty')::int * (l ->> 'unit')::numeric) / 100 as total_ligne_eur,
       s.data ->> 'pay' as paiement,
       case when coalesce((v.data ->> 'active')::boolean, v.id is not null) then 'Annulée' else 'Valide' end as statut,
       coalesce((s.data ->> 'epoch')::int, 1) as epoque,
       (coalesce((s.data ->> 'epoch')::int, 1) = coalesce((select (c.data ->> 'epoch')::int from public.config c where c.id = 'main'), 1)) as epoque_courante
from public.sales s
cross join lateral jsonb_array_elements(s.data -> 'lines') l
left join public.voids v on v.id = s.id;
grant select on public.v_ventes_lignes to authenticated;

-- ---------- 9. Réglages initiaux ------------------------------------
insert into public.config (id, data)
values ('main', '{"epoch": 1, "eventName": "Stand Province Sud"}'::jsonb)
on conflict (id) do nothing;
