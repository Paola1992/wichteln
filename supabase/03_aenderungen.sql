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
