-- CampusPass starter schema. Apply in a new Supabase project only after review.
-- Payment secrets never belong in this database schema or browser environment.
create extension if not exists pgcrypto;

create type public.app_role as enum ('student', 'admin');
create type public.booking_status as enum ('pending', 'confirmed', 'cancelled', 'expired');
create type public.ticket_status as enum ('issued', 'redeemed', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  student_id text,
  department text,
  role public.app_role not null default 'student',
  created_at timestamptz not null default now(),
  constraint profile_role_student_id_check check (
    (role = 'student' and student_id ~ '^2453[0-9]{8}$') or
    (role = 'admin' and student_id is null)
  )
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_type text not null,
  starts_at timestamptz not null,
  venue text not null,
  price_paise integer not null default 0 check (price_paise >= 0),
  published boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.seats (
  event_id uuid not null references public.events(id) on delete cascade,
  label text not null,
  primary key (event_id, label)
);

-- Temporary seat claims. The primary key makes a seat claim atomic across users.
create table public.seat_holds (
  event_id uuid not null,
  seat_label text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (event_id, seat_label),
  foreign key (event_id, seat_label) references public.seats(event_id, label) on delete cascade
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete restrict,
  status public.booking_status not null default 'pending',
  amount_paise integer not null check (amount_paise >= 0),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  created_at timestamptz not null default now()
);

create table public.booking_seats (
  event_id uuid not null,
  seat_label text not null,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  primary key (event_id, seat_label),
  unique (event_id, seat_label, booking_id),
  foreign key (event_id, seat_label) references public.seats(event_id, label) on delete restrict
);

-- One credential per attendee/seat. Only a trusted server function should
-- create rows; the bearer token itself is never stored, only its SHA-256 hash.
create table public.event_tickets (
  ticket_id uuid not null unique default gen_random_uuid(),
  event_id uuid not null,
  seat_label text not null,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  attendee_name text not null,
  attendee_student_id text not null check (attendee_student_id ~ '^2453[0-9]{8}$'),
  token_hash bytea not null unique check (octet_length(token_hash) = 32),
  status public.ticket_status not null default 'issued',
  issued_at timestamptz not null default now(),
  checked_in_at timestamptz,
  checked_in_by uuid references auth.users(id) on delete set null,
  primary key (event_id, seat_label),
  foreign key (event_id, seat_label, booking_id)
    references public.booking_seats(event_id, seat_label, booking_id) on delete cascade
);

create table public.payment_records (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete restrict,
  provider text not null,
  provider_order_id text unique,
  provider_payment_id text unique,
  status text not null default 'created' check (status in ('created', 'paid', 'failed', 'refunded')),
  amount_paise integer not null check (amount_paise >= 0),
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create index bookings_user_created_idx on public.bookings(user_id, created_at desc);
create index bookings_event_status_idx on public.bookings(event_id, status, expires_at);
create unique index profiles_student_id_unique on public.profiles (upper(btrim(student_id)));

alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.seats enable row level security;
alter table public.seat_holds enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_seats enable row level security;
alter table public.event_tickets enable row level security;
alter table public.payment_records enable row level security;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

create policy "students read own profile" on public.profiles
for select to authenticated using (id = (select auth.uid()) or (select public.is_admin()));
create policy "students create own profile" on public.profiles
for insert to authenticated with check (id = (select auth.uid()) and role = 'student');
create policy "students update own profile" on public.profiles
for update to authenticated using (id = (select auth.uid()))
with check (id = (select auth.uid()) and role = 'student');
create policy "admins manage profiles" on public.profiles
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy "published events are visible" on public.events
for select to anon, authenticated using (published or (select public.is_admin()));
create policy "admins manage events" on public.events
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "seats for visible events are visible" on public.seats
for select to anon, authenticated using (
  exists (select 1 from public.events e where e.id = seats.event_id and (e.published or (select public.is_admin())))
);
create policy "admins manage seats" on public.seats
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Users can read their own holds only. Do not expose other users' identities.
create policy "students read own active holds" on public.seat_holds
for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
revoke insert, update, delete on public.seat_holds from anon, authenticated;

-- Atomically claim up to six seats for two minutes. Any conflict rolls back all seats.
create or replace function public.hold_seats(p_event_id uuid, p_labels text[])
returns timestamptz
language plpgsql security definer
set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_expiry timestamptz := now() + interval '2 minutes';
  v_count integer;
begin
  if v_user is null then raise exception 'Sign in required'; end if;
  if coalesce(array_length(p_labels, 1), 0) < 1 or array_length(p_labels, 1) > 6 then
    raise exception 'Choose between one and six seats';
  end if;
  if (select count(distinct x) from unnest(p_labels) x) <> array_length(p_labels, 1) then
    raise exception 'Duplicate seats are not allowed';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user and p.role = 'student') then
    raise exception 'Student profile required';
  end if;
  if not exists (select 1 from public.events e where e.id = p_event_id and e.published) then
    raise exception 'Event is unavailable';
  end if;
  delete from public.seat_holds h where h.expires_at <= now();
  if exists (
    select 1 from public.booking_seats bs join public.bookings b on b.id = bs.booking_id
    where bs.event_id = p_event_id and bs.seat_label = any(p_labels)
      and b.status in ('pending', 'confirmed') and b.expires_at > now()
  ) then raise exception 'A selected seat is already booked'; end if;
  -- Keep the student's previous selection for this event in sync with the new selection.
  delete from public.seat_holds h where h.event_id = p_event_id and h.user_id = v_user
    and not (h.seat_label = any(p_labels));
  insert into public.seat_holds(event_id, seat_label, user_id, expires_at)
  select p_event_id, x, v_user, v_expiry from unnest(p_labels) x
  on conflict (event_id, seat_label) do update set user_id = excluded.user_id, expires_at = excluded.expires_at
    where public.seat_holds.user_id = v_user or public.seat_holds.expires_at <= now();
  get diagnostics v_count = row_count;
  if v_count <> array_length(p_labels, 1) then raise exception 'A selected seat is held by another student'; end if;
  return v_expiry;
end;
$$;
revoke all on function public.hold_seats(uuid, text[]) from public, anon;
grant execute on function public.hold_seats(uuid, text[]) to authenticated;

create policy "students read own bookings" on public.bookings
for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "admins manage bookings" on public.bookings
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "students read own booked seats" on public.booking_seats
for select to authenticated using (
  exists (select 1 from public.bookings b where b.id = booking_seats.booking_id and (b.user_id = (select auth.uid()) or (select public.is_admin())))
);
create policy "admins manage booked seats" on public.booking_seats
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy "students read own tickets" on public.event_tickets
for select to authenticated using (
  exists (select 1 from public.bookings b where b.id = event_tickets.booking_id
    and (b.user_id = (select auth.uid()) or (select public.is_admin())))
);
-- The token hash is not readable from the browser, and ticket issuance is
-- server-only. The admin check-in operation below performs a single-use update.
revoke all on public.event_tickets from anon, authenticated;
grant select (ticket_id, event_id, seat_label, booking_id, attendee_name,
  attendee_student_id, status, issued_at, checked_in_at, checked_in_by)
  on public.event_tickets to authenticated;

create or replace function public.redeem_ticket(p_token text)
returns table (ticket_id uuid, event_id uuid, seat_label text,
  attendee_name text, attendee_student_id text, checked_in_at timestamptz)
language plpgsql security definer
set search_path = '' as $$
declare
  v_ticket public.event_tickets%rowtype;
  v_booking public.bookings%rowtype;
begin
  if auth.uid() is null or not (select public.is_admin()) then
    raise exception 'Admin access required';
  end if;
  if p_token is null or length(p_token) < 32 or length(p_token) > 256 then
    raise exception 'Invalid ticket token';
  end if;
  select t.* into v_ticket from public.event_tickets t
    where t.token_hash = public.digest(convert_to(p_token, 'UTF8'), 'sha256')
    for update;
  if not found then raise exception 'Ticket not found'; end if;
  if v_ticket.status <> 'issued' then raise exception 'Ticket already used or cancelled'; end if;
  select b.* into v_booking from public.bookings b where b.id = v_ticket.booking_id;
  if v_booking.status <> 'confirmed' then raise exception 'Booking is not approved'; end if;
  if v_booking.amount_paise > 0 and not exists (
    select 1 from public.payment_records pr
    where pr.booking_id = v_booking.id and pr.status = 'paid'
  ) then raise exception 'Payment is not verified'; end if;
  update public.event_tickets t set status = 'redeemed', checked_in_at = now(), checked_in_by = auth.uid()
    where t.event_id = v_ticket.event_id and t.seat_label = v_ticket.seat_label;
  return query select v_ticket.ticket_id, v_ticket.event_id, v_ticket.seat_label,
    v_ticket.attendee_name, v_ticket.attendee_student_id, now();
end;
$$;
revoke all on function public.redeem_ticket(text) from public, anon;
grant execute on function public.redeem_ticket(text) to authenticated;
create policy "students read own payment status" on public.payment_records
for select to authenticated using (
  exists (select 1 from public.bookings b where b.id = payment_records.booking_id and (b.user_id = (select auth.uid()) or (select public.is_admin())))
);
create policy "admins manage payment records" on public.payment_records
for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Booking creation must use a trusted RPC/edge function that calculates the
-- authoritative price, validates the event and student, and inserts all seats
-- in one transaction. The unique (event_id, seat_label) key prevents two live
-- bookings from claiming the same seat. Do not expose direct client inserts.
revoke insert, update, delete on public.bookings, public.booking_seats, public.payment_records from anon, authenticated;
