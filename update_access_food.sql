-- HAG Technik: Zugangs-Passwort für die Registrierung, Verpflegung bei Terminen und Themen bei Orga-Aufgaben
-- Nur nötig, wenn schema.sql schon in einer älteren Fassung ausgeführt wurde.
-- Reihenfolge bei bestehenden Datenbanken: update_orga, update_features, update_groups_notes, dann diese Datei.
-- Danach legt ein Admin in der App unter Konto das Zugangs-Passwort fest. Bis dahin kann sich niemand Neues registrieren.

alter table public.events add column if not exists catering text not null default '';
alter table public.events add column if not exists catering_payer text not null default '';
-- Thema/Event-Name bei Orga-Aufgaben, bleibt auch nach dem Löschen des Termins erhalten (für „bisherige“ Male)
alter table public.tasks add column if not exists event_title text not null default '';
update public.tasks t set event_title = e.title from public.events e where t.event_id = e.id and t.event_title = '';

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


-- Termin speichern, jetzt mit Verpflegung
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
