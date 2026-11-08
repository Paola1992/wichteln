-- Wichteln: Datenbank-Schema (Supabase / Postgres)
-- Zugriff erfolgt ausschließlich über die SECURITY-DEFINER-Funktionen.
-- Die Tabellen haben RLS ohne Policies, sind also direkt nicht lesbar.
-- Gleiches "team" (z.B. ein Paar oder 'Kolumbien') => diese Personen ziehen sich nicht gegenseitig.

create extension if not exists pgcrypto with schema extensions;

create table public.events (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  budget text,
  gift_date date,
  admin_token text not null unique,
  join_code text not null unique,
  drawn_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.participants (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  name text not null,
  token text not null unique,
  wish text not null default '',
  lang text not null default 'de',
  team text,  -- gleiche Gruppe (z.B. 'Kolumbien') => ziehen sich nicht gegenseitig
  receiver_id uuid references public.participants(id) on delete set null,
  seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (event_id, name)
);
create index on public.participants(event_id);
create index on public.participants(receiver_id);

create table public.exclusions (
  event_id uuid not null references public.events(id) on delete cascade,
  giver_id uuid not null references public.participants(id) on delete cascade,
  receiver_id uuid not null references public.participants(id) on delete cascade,
  primary key (giver_id, receiver_id),
  check (giver_id <> receiver_id)
);
create index on public.exclusions(event_id);
create index on public.exclusions(receiver_id);

alter table public.events enable row level security;
alter table public.participants enable row level security;
alter table public.exclusions enable row level security;

-- Hilfsfunktionen im Schema "private" (nicht über die API erreichbar)
create schema if not exists private;

create or replace function private.tok() returns text
language sql volatile set search_path = '' as $$
  select translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=', '-_')
$$;

create or replace function private.event_by_admin(p_admin text) returns public.events
language plpgsql set search_path = '' as $$
declare e public.events;
begin
  select * into e from public.events where admin_token = p_admin;
  if not found then raise exception 'not_found'; end if;
  return e;
end $$;

-- ===== Organisatorin (alles außer der Zuteilung) =====
create or replace function public.admin_get(p_admin text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e public.events := private.event_by_admin(p_admin);
begin
  return jsonb_build_object(
    'event', jsonb_build_object('name', e.name, 'budget', e.budget, 'gift_date', e.gift_date,
                                'join_code', e.join_code, 'drawn', e.drawn_at is not null),
    'participants', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'name', p.name, 'token', p.token, 'lang', p.lang, 'team', p.team,
        'has_wish', p.wish <> '', 'seen', p.seen_at is not null) order by lower(p.name))
      from public.participants p where p.event_id = e.id), '[]'::jsonb),
    'exclusions', coalesce((select jsonb_agg(jsonb_build_object('giver', x.giver_id, 'receiver', x.receiver_id))
      from public.exclusions x where x.event_id = e.id), '[]'::jsonb));
end $$;

create or replace function public.admin_update_event(p_admin text, p_name text, p_budget text, p_date date)
returns void language plpgsql security definer set search_path = '' as $$
declare e public.events := private.event_by_admin(p_admin);
begin
  update public.events set name = coalesce(nullif(trim(p_name), ''), name),
         budget = nullif(trim(p_budget), ''), gift_date = p_date
   where id = e.id;
end $$;

create or replace function public.admin_add(p_admin text, p_name text, p_lang text, p_team text)
returns text language plpgsql security definer set search_path = '' as $$
declare e public.events := private.event_by_admin(p_admin); t text := private.tok();
begin
  if e.drawn_at is not null then raise exception 'already_drawn'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name_required'; end if;
  if exists (select 1 from public.participants where event_id = e.id and lower(name) = lower(trim(p_name))) then
    raise exception 'name_taken';
  end if;
  insert into public.participants(event_id, name, token, lang, team)
  values (e.id, left(trim(p_name), 60), t, coalesce(nullif(p_lang, ''), 'de'), nullif(trim(p_team), ''));
  return t;
end $$;

create or replace function public.admin_set_participant(p_admin text, p_id uuid, p_lang text, p_team text)
returns void language plpgsql security definer set search_path = '' as $$
declare e public.events := private.event_by_admin(p_admin);
begin
  if e.drawn_at is not null then raise exception 'already_drawn'; end if;
  update public.participants set lang = coalesce(nullif(p_lang, ''), lang), team = nullif(trim(p_team), '')
   where id = p_id and event_id = e.id;
end $$;

create or replace function public.admin_remove(p_admin text, p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare e public.events := private.event_by_admin(p_admin);
begin
  if e.drawn_at is not null then raise exception 'already_drawn'; end if;
  delete from public.participants where id = p_id and event_id = e.id;
end $$;

-- Ausschluss gilt immer in beide Richtungen
create or replace function public.admin_set_exclusion(p_admin text, p_a uuid, p_b uuid, p_on boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare e public.events := private.event_by_admin(p_admin);
begin
  if e.drawn_at is not null then raise exception 'already_drawn'; end if;
  if p_on then
    insert into public.exclusions(event_id, giver_id, receiver_id)
    select e.id, g, r from (values (p_a, p_b), (p_b, p_a)) v(g, r)
     where p_a <> p_b
       and exists (select 1 from public.participants where id = p_a and event_id = e.id)
       and exists (select 1 from public.participants where id = p_b and event_id = e.id)
    on conflict do nothing;
  else
    delete from public.exclusions where event_id = e.id
       and ((giver_id = p_a and receiver_id = p_b) or (giver_id = p_b and receiver_id = p_a));
  end if;
end $$;

-- Auslosung auf dem Server: niemand – auch die Organisatorin nicht – sieht die Zuteilung.
create or replace function public.admin_draw(p_admin text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  e public.events := private.event_by_admin(p_admin);
  ids uuid[]; teams text[]; perm uuid[]; used uuid[]; pick uuid;
  n int; attempt int; i int; ok boolean;
begin
  perform 1 from public.events where id = e.id for update;
  if e.drawn_at is not null then raise exception 'already_drawn'; end if;
  select array_agg(id order by id), array_agg(coalesce(lower(trim(team)), '') order by id)
    into ids, teams from public.participants where event_id = e.id;
  n := coalesce(array_length(ids, 1), 0);
  if n < 3 then raise exception 'too_few'; end if;

  for attempt in 1..3000 loop
    used := '{}'; perm := '{}'; ok := true;
    for i in 1..n loop
      select ids[j] into pick from generate_series(1, n) j
       where j <> i
         and not (ids[j] = any(used))
         and not (teams[i] <> '' and teams[i] = teams[j])
         and not exists (select 1 from public.exclusions x where x.giver_id = ids[i] and x.receiver_id = ids[j])
       order by random() limit 1;
      if pick is null then ok := false; exit; end if;
      perm := perm || pick; used := used || pick;
    end loop;
    if ok then
      for i in 1..n loop
        update public.participants set receiver_id = perm[i], seen_at = null where id = ids[i];
      end loop;
      update public.events set drawn_at = now() where id = e.id;
      return;
    end if;
  end loop;
  raise exception 'impossible';
end $$;

create or replace function public.admin_reset_draw(p_admin text) returns void
language plpgsql security definer set search_path = '' as $$
declare e public.events := private.event_by_admin(p_admin);
begin
  update public.participants set receiver_id = null, seen_at = null where event_id = e.id;
  update public.events set drawn_at = null where id = e.id;
end $$;

-- ===== Selbst anmelden über den Familien-Link =====
create or replace function public.join_info(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e public.events;
begin
  select * into e from public.events where join_code = p_code;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('name', e.name, 'budget', e.budget, 'gift_date', e.gift_date, 'drawn', e.drawn_at is not null);
end $$;

create or replace function public.join_event(p_code text, p_name text, p_lang text, p_wish text)
returns text language plpgsql security definer set search_path = '' as $$
declare e public.events; t text := private.tok();
begin
  select * into e from public.events where join_code = p_code;
  if not found then raise exception 'not_found'; end if;
  if e.drawn_at is not null then raise exception 'already_drawn'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name_required'; end if;
  if exists (select 1 from public.participants where event_id = e.id and lower(name) = lower(trim(p_name))) then
    raise exception 'name_taken';
  end if;
  insert into public.participants(event_id, name, token, lang, wish)
  values (e.id, left(trim(p_name), 60), t, coalesce(nullif(p_lang, ''), 'de'), left(coalesce(p_wish, ''), 1000));
  return t;
end $$;

-- ===== Persönliche Seite =====
create or replace function public.me_get(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p public.participants; e public.events; r public.participants;
begin
  select * into p from public.participants where token = p_token;
  if not found then raise exception 'not_found'; end if;
  select * into e from public.events where id = p.event_id;
  if p.receiver_id is not null then
    select * into r from public.participants where id = p.receiver_id;
  end if;
  return jsonb_build_object(
    'name', p.name, 'wish', p.wish, 'lang', p.lang,
    'event', jsonb_build_object('name', e.name, 'budget', e.budget, 'gift_date', e.gift_date, 'drawn', e.drawn_at is not null),
    'count', (select count(*) from public.participants where event_id = e.id),
    'receiver', case when r.id is null then null else jsonb_build_object('name', r.name, 'wish', r.wish) end);
end $$;

create or replace function public.me_update(p_token text, p_wish text, p_lang text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.participants set wish = left(coalesce(p_wish, wish), 1000), lang = coalesce(nullif(p_lang, ''), lang)
   where token = p_token;
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.me_seen(p_token text) returns void
language sql security definer set search_path = '' as $$
  update public.participants set seen_at = coalesce(seen_at, now()) where token = p_token and receiver_id is not null;
$$;
