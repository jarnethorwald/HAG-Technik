-- HAG Technik: Datenbank-Schema für Supabase
-- Einmal im Supabase-Dashboard unter "SQL Editor" ausführen.
-- Der erste Benutzer, der sich registriert, wird automatisch Admin.

-- ---------- Tabellen ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_lower on public.profiles (lower(username));

create table if not exists public.app_settings (
  key text primary key,
  value text not null
);

create table if not exists public.inventory (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  qty integer not null default 1 check (qty >= 0),
  note text not null default '',
  rental boolean not null default false,
  vendor text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  location text not null default '',
  description text not null default '',
  tech text not null default '',
  catering text not null default '',
  catering_payer text not null default '',
  kind text not null default 'event' check (kind in ('event','prep')),
  parent_id uuid references public.events(id) on delete cascade,
  people_mode text check (people_mode in ('min','max')),
  people_count integer check (people_count > 0),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.event_days (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  date date not null,
  start_time time,
  end_time time,
  unique (event_id, date)
);

create table if not exists public.event_gear (
  event_id uuid not null references public.events(id) on delete cascade,
  item_id uuid not null references public.inventory(id) on delete cascade,
  qty integer not null check (qty > 0),
  primary key (event_id, item_id)
);

create table if not exists public.signups (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('yes','no')),
  car boolean not null default false,
  signed_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table if not exists public.absences (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  date date not null,
  from_time time not null,
  to_time time not null
);

-- ---------- Hilfsfunktionen ----------
create or replace function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

create or replace function public.username_available(p_name text) returns boolean
language sql security definer stable set search_path = public as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(trim(p_name)))
$$;
grant execute on function public.username_available(text) to anon, authenticated;

-- ---------- Zugangs-Passwort für die Registrierung ----------
-- Wer sich registrieren will, braucht das Passwort, das ein Admin festlegt. Nur der erste Benutzer braucht keins.
create or replace function public.check_invite_code(p_code text) returns boolean
language plpgsql security definer stable set search_path = public, extensions as $$
declare v_hash text;
begin
  if not exists (select 1 from public.profiles) then return true; end if;
  select value into v_hash from public.app_settings where key = 'invite_code_hash';
  if v_hash is null then return false; end if;
  return encode(digest(lower(trim(coalesce(p_code, ''))), 'sha256'), 'hex') = v_hash;
end $$;
grant execute on function public.check_invite_code(text) to anon, authenticated;

create or replace function public.set_invite_code(p_code text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Keine Berechtigung'; end if;
  if length(trim(p_code)) < 6 then raise exception 'Das Zugangs-Passwort braucht mindestens 6 Zeichen.'; end if;
  insert into public.app_settings (key, value)
  values ('invite_code_hash', encode(digest(lower(trim(p_code)), 'sha256'), 'hex'))
  on conflict (key) do update set value = excluded.value;
end $$;

-- Profil beim Registrieren anlegen. Wer zuerst kommt, ist Admin. Ohne richtiges Zugangs-Passwort wird nicht registriert.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_name text;
  v_first boolean;
begin
  if not public.check_invite_code(new.raw_user_meta_data->>'invite_code') then
    raise exception 'Zugangs-Passwort falsch';
  end if;
  v_name := trim(coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)));
  select not exists (select 1 from public.profiles) into v_first;
  insert into public.profiles (id, username, is_admin) values (new.id, v_name, v_first);
  begin
    update auth.users set raw_user_meta_data = raw_user_meta_data - 'invite_code' where id = new.id;
  exception when others then null;
  end;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Admin-Code ----------
create or replace function public.redeem_admin_code(p_code text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v_hash text;
begin
  if auth.uid() is null then return false; end if;
  select value into v_hash from public.app_settings where key = 'admin_code_hash';
  if v_hash is null then return false; end if;
  if encode(digest(lower(trim(p_code)), 'sha256'), 'hex') = v_hash then
    update public.profiles set is_admin = true where id = auth.uid();
    return true;
  end if;
  return false;
end $$;

create or replace function public.set_admin_code(p_code text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_admin() then raise exception 'Keine Berechtigung'; end if;
  if length(trim(p_code)) < 8 then raise exception 'Der Code braucht mindestens 8 Zeichen.'; end if;
  insert into public.app_settings (key, value)
  values ('admin_code_hash', encode(digest(lower(trim(p_code)), 'sha256'), 'hex'))
  on conflict (key) do update set value = excluded.value;
end $$;

create or replace function public.set_user_admin(p_user uuid, p_admin boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Keine Berechtigung'; end if;
  if not p_admin and not exists (select 1 from public.profiles where is_admin and id <> p_user) then
    raise exception 'Mindestens ein Admin muss bleiben.';
  end if;
  update public.profiles set is_admin = p_admin where id = p_user;
end $$;

-- ---------- Keine Doppelbelegung von Technik ----------
-- Pro Tag darf die Summe aller Termine die vorhandene Menge nicht übersteigen.
create or replace function public.check_gear_conflict(p_event uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select i.name, d.date, i.qty as total, g.qty as mine,
      (select coalesce(sum(g2.qty), 0)
         from public.event_gear g2
         join public.event_days d2 on d2.event_id = g2.event_id
        where g2.item_id = g.item_id and d2.date = d.date and g2.event_id <> p_event) as others
    from public.event_gear g
    join public.inventory i on i.id = g.item_id
    join public.event_days d on d.event_id = g.event_id
    where g.event_id = p_event
  loop
    if r.others + r.mine > r.total then
      raise exception 'Technik belegt: % am % (frei: % von %)',
        r.name, to_char(r.date, 'DD.MM.YYYY'), greatest(r.total - r.others, 0), r.total;
    end if;
  end loop;
end $$;

create or replace function public.trg_check_gear() returns trigger
language plpgsql as $$
begin
  perform public.check_gear_conflict(new.event_id);
  return null;
end $$;

drop trigger if exists event_gear_check on public.event_gear;
create trigger event_gear_check after insert or update on public.event_gear
  for each row execute function public.trg_check_gear();

drop trigger if exists event_days_check on public.event_days;
create trigger event_days_check after insert or update on public.event_days
  for each row execute function public.trg_check_gear();

-- ---------- Termin in einem Schritt speichern ----------
-- Läuft mit den Rechten der aufrufenden Person. Bei einem Fehler wird alles zurückgerollt.
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
    insert into public.events (title, location, description, tech, catering, catering_payer, kind, parent_id, people_mode, people_count, created_by)
    values (p->>'title', coalesce(p->>'location', ''), coalesce(p->>'description', ''),
            coalesce(p->>'tech', ''), coalesce(p->>'catering', ''), coalesce(p->>'catering_payer', ''),
            coalesce(nullif(p->>'kind', ''), 'event'),
            nullif(p->>'parent_id', '')::uuid, nullif(p->>'people_mode', ''),
            nullif(p->>'people_count', '')::integer, auth.uid())
    returning id into v_id;
  else
    update public.events
       set title = p->>'title', location = coalesce(p->>'location', ''),
           description = coalesce(p->>'description', ''), tech = coalesce(p->>'tech', ''),
           catering = coalesce(p->>'catering', ''), catering_payer = coalesce(p->>'catering_payer', ''),
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

-- ---------- Zugriffsrechte (Row Level Security) ----------
alter table public.profiles enable row level security;
alter table public.app_settings enable row level security;
alter table public.inventory enable row level security;
alter table public.events enable row level security;
alter table public.event_days enable row level security;
alter table public.event_gear enable row level security;
alter table public.signups enable row level security;
alter table public.absences enable row level security;

-- app_settings hat absichtlich keine Policy: niemand außer den Funktionen kommt dran.
revoke all on public.app_settings from anon, authenticated;

create policy "profiles lesen" on public.profiles for select to authenticated using (true);

create policy "inventory lesen" on public.inventory for select to authenticated using (true);
create policy "inventory anlegen" on public.inventory for insert to authenticated with check (public.is_admin());
create policy "inventory ändern" on public.inventory for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "inventory löschen" on public.inventory for delete to authenticated using (public.is_admin());

create policy "events lesen" on public.events for select to authenticated using (true);
create policy "events anlegen" on public.events for insert to authenticated with check (created_by = auth.uid());
create policy "events ändern" on public.events for update to authenticated
  using (created_by = auth.uid() or public.is_admin())
  with check (created_by = auth.uid() or public.is_admin());
create policy "events löschen" on public.events for delete to authenticated
  using (created_by = auth.uid() or public.is_admin());

create policy "event_days lesen" on public.event_days for select to authenticated using (true);
create policy "event_days schreiben" on public.event_days for all to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and (e.created_by = auth.uid() or public.is_admin())))
  with check (exists (select 1 from public.events e where e.id = event_id and (e.created_by = auth.uid() or public.is_admin())));

create policy "event_gear lesen" on public.event_gear for select to authenticated using (true);
create policy "event_gear schreiben" on public.event_gear for all to authenticated
  using (exists (select 1 from public.events e where e.id = event_id and (e.created_by = auth.uid() or public.is_admin())))
  with check (exists (select 1 from public.events e where e.id = event_id and (e.created_by = auth.uid() or public.is_admin())));

create policy "signups lesen" on public.signups for select to authenticated using (true);
create policy "signups eigene" on public.signups for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "absences lesen" on public.absences for select to authenticated using (true);
create policy "absences eigene" on public.absences for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- Live-Updates ----------
do $$
declare t text;
begin
  foreach t in array array['inventory','events','event_days','event_gear','signups','absences','profiles'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------- Orga-Bereich (nur Admins) ----------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  note text not null default '',
  due_date date,
  category text not null default 'sonstiges' check (category in ('absprache','technik','uebergabe','sonstiges')),
  contact text not null default '',
  assignee uuid references public.profiles(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
  event_title text not null default '',
  repeat_yearly boolean not null default false,
  done boolean not null default false,
  done_at timestamptz,
  done_by uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.tasks enable row level security;

drop policy if exists "tasks nur admins" on public.tasks;
create policy "tasks nur admins" on public.tasks for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

do $$
begin
  alter publication supabase_realtime add table public.tasks;
exception when duplicate_object then null;
end $$;

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
