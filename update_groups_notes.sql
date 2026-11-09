-- HAG Technik: Notizen, Gruppen und Zielgruppen für Termine
-- Nur nötig, wenn schema.sql schon in einer älteren Fassung ausgeführt wurde.
-- Reihenfolge bei bestehenden Datenbanken: update_orga.sql, update_features.sql, dann diese Datei.
-- Bei einer Neueinrichtung ist alles schon in schema.sql enthalten.

-- ---------- Notizen ----------
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  body text not null check (length(trim(body)) > 0),
  author uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists notes_created_at on public.notes (created_at desc);
alter table public.notes enable row level security;
drop policy if exists "notes lesen" on public.notes;
drop policy if exists "notes schreiben" on public.notes;
drop policy if exists "notes loeschen" on public.notes;
create policy "notes lesen" on public.notes for select to authenticated using (true);
create policy "notes schreiben" on public.notes for insert to authenticated with check (author = auth.uid());
create policy "notes loeschen" on public.notes for delete to authenticated using (author = auth.uid() or public.is_admin());

-- ---------- Gruppen ----------
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  default_target boolean not null default true,
  created_at timestamptz not null default now()
);
create unique index if not exists groups_name_lower on public.groups (lower(name));

create table if not exists public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key (group_id, user_id)
);

-- Zielgruppen eines Termins. Keine Zeile bedeutet: alle sind angesprochen.
create table if not exists public.event_groups (
  event_id uuid not null references public.events(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  primary key (event_id, group_id)
);

create or replace function public.is_addressed(p_event uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select public.is_admin()
      or not exists (select 1 from public.event_groups eg where eg.event_id = p_event)
      or exists (select 1 from public.event_groups eg
                   join public.group_members gm on gm.group_id = eg.group_id
                  where eg.event_id = p_event and gm.user_id = auth.uid())
$$;

alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.event_groups enable row level security;

drop policy if exists "groups lesen" on public.groups;
drop policy if exists "groups admins" on public.groups;
create policy "groups lesen" on public.groups for select to authenticated using (true);
create policy "groups admins" on public.groups for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "group_members lesen" on public.group_members;
drop policy if exists "group_members admins" on public.group_members;
create policy "group_members lesen" on public.group_members for select to authenticated using (true);
create policy "group_members admins" on public.group_members for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "event_groups lesen" on public.event_groups;
drop policy if exists "event_groups schreiben" on public.event_groups;
create policy "event_groups lesen" on public.event_groups for select to authenticated using (true);
create policy "event_groups schreiben" on public.event_groups for all to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and (e.created_by = auth.uid() or public.is_admin())))
  with check (exists (select 1 from public.events e where e.id = event_id and (e.created_by = auth.uid() or public.is_admin())));

-- Zusagen nur für angesprochene Gruppen (Admins immer)
drop policy if exists "signups eigene" on public.signups;
create policy "signups eigene" on public.signups for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.is_addressed(event_id));

do $$
declare t text;
begin
  foreach t in array array['notes','groups','group_members','event_groups'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- Termin speichern, jetzt mit Zielgruppen
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
  delete from public.event_groups where event_id = v_id;
  for g in select value from jsonb_array_elements(coalesce(p->'group_ids', '[]'::jsonb)) loop
    insert into public.event_groups (event_id, group_id) values (v_id, (g #>> '{}')::uuid);
  end loop;
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
