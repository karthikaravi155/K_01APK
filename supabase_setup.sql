-- K_01 app + WhatsApp AI Sales Agent _2  ->  run ONCE in the NEW Supabase project (SQL Editor).
-- Safe to re-run. It also fixes tables created by the earlier draft script.

-- 1) profiles: one row per login (the app reads name + role: 'admin' or 'tl' = team lead)
create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  name             text,
  role             text not null default 'tl',
  active           boolean not null default true,
  last_assigned_at timestamptz,
  created_at       timestamptz not null default now()
);
alter table public.profiles add column if not exists name text;
alter table public.profiles add column if not exists active boolean not null default true;
alter table public.profiles add column if not exists last_assigned_at timestamptz;
do $$ begin   -- the earlier draft used full_name
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='profiles' and column_name='full_name') then
    execute 'update public.profiles set name = coalesce(name, full_name)';
  end if;
end $$;
alter table public.profiles drop constraint if exists profiles_role_check;
update public.profiles set role = 'tl' where role not in ('admin','tl');
alter table public.profiles add constraint profiles_role_check check (role in ('admin','tl'));
alter table public.profiles alter column role set default 'tl';

-- 2) leads / messages: columns the app and the workflow need
create table if not exists public.leads (
  phone text primary key, ad_headline text, lead_name text, fund_range text, segment text,
  state text, language text, step text, last_message text, "timestamp" timestamptz,
  created_at timestamptz default now()
);
create table if not exists public.messages (
  id bigserial primary key, phone text, direction text, message text,
  "timestamp" timestamptz, wa_id text, status text, created_at timestamptz default now()
);
alter table public.leads add column if not exists id bigint generated always as identity;  -- the app needs an id
create unique index if not exists leads_id_key    on public.leads (id);
create unique index if not exists leads_phone_key on public.leads (phone);                -- the workflow upserts on phone
alter table public.leads add column if not exists assigned_to uuid references public.profiles(id) on delete set null;
alter table public.messages add column if not exists wa_id text;
alter table public.messages add column if not exists status text;
create index if not exists messages_phone_ts on public.messages (phone, "timestamp");
create index if not exists messages_wa_id    on public.messages (wa_id);
create index if not exists leads_assigned_to on public.leads (assigned_to);

-- 3) helper used by the access rules
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and active);
$$;

-- 4) every new login gets a profile automatically (team lead by default; promote admins below)
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)), 'tl')
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();
insert into public.profiles (id, name, role)            -- logins that already exist
select id, split_part(email, '@', 1), 'tl' from auth.users
on conflict (id) do nothing;

-- 5) ROUND ROBIN: each brand-new lead goes to the team lead who was given a lead longest ago
create or replace function public.assign_lead_round_robin() returns trigger
language plpgsql security definer set search_path = public as $$
declare tl uuid;
begin
  if new.assigned_to is not null then return new; end if;
  -- the workflow saves the lead on every message: only a brand-new phone takes a turn
  if exists (select 1 from public.leads where phone = new.phone) then return new; end if;
  perform pg_advisory_xact_lock(727002);                -- two leads at once cannot get the same person
  select id into tl from public.profiles
   where role = 'tl' and active
   order by last_assigned_at nulls first, name, id limit 1;
  if tl is not null then
    new.assigned_to := tl;
    update public.profiles set last_assigned_at = clock_timestamp() where id = tl;
  end if;
  return new;
end $$;
drop trigger if exists trg_assign_lead on public.leads;
create trigger trg_assign_lead before insert on public.leads
  for each row execute function public.assign_lead_round_robin();

-- 6) ACCESS RULES: admin sees everything, a team lead sees only the leads assigned to them
alter table public.profiles enable row level security;
alter table public.leads    enable row level security;
alter table public.messages enable row level security;

drop policy if exists "read own or admin"      on public.profiles;
drop policy if exists "admin manage profiles"  on public.profiles;
create policy "read own or admin"     on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy "admin manage profiles" on public.profiles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "staff read leads"     on public.leads;
drop policy if exists "leads by assignment"  on public.leads;
create policy "leads by assignment" on public.leads for select to authenticated
  using (public.is_admin() or assigned_to = auth.uid());

drop policy if exists "staff read messages"     on public.messages;
drop policy if exists "messages by assignment"  on public.messages;
create policy "messages by assignment" on public.messages for select to authenticated
  using (public.is_admin() or exists (
    select 1 from public.leads l where l.phone = messages.phone and l.assigned_to = auth.uid()));

-- 7) live updates in the app
do $$ begin alter publication supabase_realtime add table public.leads;    exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; end $$;

-- 8) AFTER you create the logins (Authentication > Users > Add user), set names and roles.
--    Replace the emails, then run:
-- update public.profiles p set name = 'Nandhini', role = 'admin' from auth.users u where u.id = p.id and u.email = 'nandhini@example.com';
-- update public.profiles p set name = 'Farooq',   role = 'tl'    from auth.users u where u.id = p.id and u.email = 'farooq@example.com';
-- update public.profiles p set name = 'Raju',     role = 'tl'    from auth.users u where u.id = p.id and u.email = 'raju@example.com';
--
-- OPTIONAL one-off: spread leads that already exist but have nobody assigned across the active team leads
-- with tls as (select id, row_number() over (order by name, id) - 1 as n, count(*) over () as c
--              from public.profiles where role = 'tl' and active),
--      un  as (select id, row_number() over (order by "timestamp") - 1 as r from public.leads where assigned_to is null)
-- update public.leads l set assigned_to = t.id from un join tls t on t.n = un.r % t.c where l.id = un.id;
