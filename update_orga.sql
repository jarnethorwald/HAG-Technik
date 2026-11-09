-- HAG Technik: Orga-Bereich (Aufgaben mit Fristen, nur für Admins)
-- Wenn schema.sql schon ausgeführt wurde, genügt es, nur diese Datei im SQL Editor auszuführen.
-- (Ist schema.sql noch nicht gelaufen, ist dieser Teil dort bereits am Ende enthalten.)

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  note text not null default '',
  due_date date,
  category text not null default 'sonstiges' check (category in ('absprache','technik','uebergabe','sonstiges')),
  contact text not null default '',
  assignee uuid references public.profiles(id) on delete set null,
  event_id uuid references public.events(id) on delete set null,
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
