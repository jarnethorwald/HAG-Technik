-- HAG Technik: Erweiterung um Miettechnik, Vorbereitungs-Termine und Personenbedarf mit Backup-Liste
-- Nur nötig, wenn schema.sql schon in einer älteren Fassung ausgeführt wurde.
-- Bei einer Neueinrichtung ist das alles schon in schema.sql enthalten.

alter table public.inventory add column if not exists rental boolean not null default false;
alter table public.inventory add column if not exists vendor text not null default '';

alter table public.events add column if not exists kind text not null default 'event' check (kind in ('event','prep'));
alter table public.events add column if not exists parent_id uuid references public.events(id) on delete cascade;
alter table public.events add column if not exists people_mode text check (people_mode in ('min','max'));
alter table public.events add column if not exists people_count integer check (people_count > 0);

alter table public.signups add column if not exists signed_at timestamptz not null default now();

create or replace function public.save_event(p jsonb) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  v_id uuid;
  v_rows integer;
  d jsonb;
  g jsonb;
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet'; end if;
  v_id := nullif(p->>'id', '')::uuid;
  if v_id is null then
    insert into public.events (title, location, description, tech, kind, parent_id, people_mode, people_count, created_by)
    values (p->>'title', coalesce(p->>'location', ''), coalesce(p->>'description', ''),
            coalesce(p->>'tech', ''), coalesce(nullif(p->>'kind', ''), 'event'),
            nullif(p->>'parent_id', '')::uuid, nullif(p->>'people_mode', ''),
            nullif(p->>'people_count', '')::integer, auth.uid())
    returning id into v_id;
  else
    update public.events
       set title = p->>'title', location = coalesce(p->>'location', ''),
           description = coalesce(p->>'description', ''), tech = coalesce(p->>'tech', ''),
           kind = coalesce(nullif(p->>'kind', ''), 'event'), parent_id = nullif(p->>'parent_id', '')::uuid,
           people_mode = nullif(p->>'people_mode', ''), people_count = nullif(p->>'people_count', '')::integer,
           updated_at = now()
     where id = v_id;
    get diagnostics v_rows = row_count;
    if v_rows = 0 then raise exception 'Keine Berechtigung für diesen Termin'; end if;
    delete from public.event_gear where event_id = v_id;
    delete from public.event_days where event_id = v_id;
  end if;
  for d in select value from jsonb_array_elements(coalesce(p->'days', '[]'::jsonb)) loop
    insert into public.event_days (event_id, date, start_time, end_time)
    values (v_id, (d->>'date')::date, nullif(d->>'start', '')::time, nullif(d->>'end', '')::time);
  end loop;
  for g in select value from jsonb_array_elements(coalesce(p->'gear', '[]'::jsonb)) loop
    insert into public.event_gear (event_id, item_id, qty)
    values (v_id, (g->>'item_id')::uuid, (g->>'qty')::integer);
  end loop;
  return v_id;
end $$;
