-- Spätere Änderungen (bereits in Supabase angewendet)

-- 1) "Entfernen" ohne DELETE: Personen und Ausschlüsse werden nur inaktiv gesetzt.
--    Alle Funktionen (admin_get, me_get, admin_draw, admin_remove, admin_set_exclusion, admin_add …)
--    berücksichtigen nur Zeilen mit active = true.
alter table public.participants add column if not exists active boolean not null default true;
alter table public.exclusions  add column if not exists active boolean not null default true;

-- 2) Teilnehmer können ihren Namen selbst ändern.
create or replace function public.me_rename(p_token text, p_name text) returns text
language plpgsql security definer set search_path = '' as $$
declare p public.participants; n text := left(trim(coalesce(p_name, '')), 60);
begin
  select * into p from public.participants where token = p_token and active;
  if not found then raise exception 'not_found'; end if;
  if n = '' then raise exception 'name_required'; end if;
  if exists (select 1 from public.participants
              where event_id = p.event_id and id <> p.id and lower(name) = lower(n)) then
    raise exception 'name_taken';
  end if;
  update public.participants set name = n where id = p.id;
  return n;
end $$;

-- 3) Ein Link für alle: Jeder tippt im Familien-Link auf seinen Namen.
--    Ein Name kann nur einmal "beansprucht" werden (claimed_at); die Organisatorin kann ihn
--    mit admin_release wieder freigeben (dabei wird ein neuer persönlicher Link erzeugt).
--    Neue Funktionen: family_list(p_code), family_claim(p_code, p_id), admin_release(p_admin, p_id).
--    me_get setzt claimed_at beim ersten Öffnen eines persönlichen Links.
alter table public.participants add column if not exists claimed_at timestamptz;

-- 4) Falschen Namen selbst wieder freigeben (nur vor der Auslosung)
create or replace function public.me_unclaim(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare p public.participants; e public.events;
begin
  select * into p from public.participants where token = p_token and active;
  if not found then raise exception 'not_found'; end if;
  select * into e from public.events where id = p.event_id;
  if e.drawn_at is not null then raise exception 'already_drawn'; end if;
  update public.participants set claimed_at = null, token = private.tok() where id = p.id;
end $$;
