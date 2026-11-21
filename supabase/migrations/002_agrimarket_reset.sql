-- Destructive AgriMarket reset: this removes existing gateway data.
drop function if exists public.claim_outbound_sms(integer) cascade;
drop function if exists public.search_products(text) cascade;
drop function if exists public.place_market_order(text, uuid, numeric) cascade;
drop table if exists public.orders cascade;
drop table if exists public.sessions cascade;
drop table if exists public.incoming_sms cascade;
drop table if exists public.outbound_sms cascade;
drop table if exists public.products cascade;
drop table if exists public.users cascade;

create extension if not exists pg_trgm with schema extensions;

create table public.users (
  phone text primary key,
  name text,
  role text not null default 'buyer'
    check (role in ('farmer', 'buyer')),
  location text,
  created_at timestamptz not null default now()
);

create table public.sessions (
  phone text primary key references public.users(phone) on delete cascade,
  current_menu text not null,
  context_data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  farmer_phone text not null references public.users(phone),
  name text not null,
  quantity_kg numeric(12,2) not null check (quantity_kg > 0),
  price_per_kg numeric(12,2) not null check (price_per_kg > 0),
  status text not null default 'available'
    check (status in ('available', 'sold')),
  created_at timestamptz not null default now()
);

create index products_name_trgm_idx
  on public.products using gin (name gin_trgm_ops);
create index products_available_created_idx
  on public.products (status, created_at);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_phone text not null references public.users(phone),
  product_id uuid not null references public.products(id),
  quantity_kg numeric(12,2) not null check (quantity_kg > 0),
  total_price numeric(14,2) not null check (total_price > 0),
  status text not null default 'pending'
    check (status in ('pending', 'paid')),
  created_at timestamptz not null default now()
);

create table public.incoming_sms (
  id uuid primary key default gen_random_uuid(),
  sender text not null,
  body text not null,
  subscription_id integer,
  session_id uuid not null,
  created_at timestamptz not null default now()
);

create table public.outbound_sms (
  id uuid primary key default gen_random_uuid(),
  phone text not null,
  message text not null,
  status text not null default 'pending',
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  sent_at timestamptz,
  reply_to_subscription_id integer,
  session_id uuid
);

create index outbound_sms_status_created_at_idx
  on public.outbound_sms (status, created_at);
create index orders_buyer_created_idx
  on public.orders (buyer_phone, created_at desc);

create or replace function public.claim_outbound_sms(batch_size integer default 5)
returns setof public.outbound_sms
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update public.outbound_sms sms
  set status = 'processing',
      claimed_at = now(),
      attempts = sms.attempts + 1
  where sms.id in (
    select queued.id
    from public.outbound_sms queued
    where queued.status = 'pending'
       or (queued.status = 'processing'
           and queued.claimed_at < now() - interval '2 minutes')
    order by queued.created_at
    for update skip locked
    limit greatest(batch_size, 1)
  )
  returning sms.*;
end;
$$;

create or replace function public.place_market_order(
  p_buyer_phone text,
  p_product_id uuid,
  p_quantity_kg numeric
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  item public.products%rowtype;
  transaction_total numeric(14,2);
begin
  if p_quantity_kg <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  select *
    into item
    from public.products
   where id = p_product_id
     and status = 'available'
   for update;

  if not found or p_quantity_kg > item.quantity_kg then
    raise exception 'Requested quantity is no longer available';
  end if;

  transaction_total := round(p_quantity_kg * item.price_per_kg, 2);

  insert into public.orders (
    buyer_phone, product_id, quantity_kg, total_price, status
  ) values (
    p_buyer_phone, item.id, p_quantity_kg, transaction_total, 'pending'
  );

  update public.products
     set quantity_kg = item.quantity_kg - p_quantity_kg,
         status = case
           when item.quantity_kg - p_quantity_kg <= 0 then 'sold'
           else 'available'
         end
   where id = item.id;

  return transaction_total;
end;
$$;

create or replace function public.marketplace_metrics()
returns table (
  total_users bigint,
  total_products bigint,
  total_orders bigint,
  total_value numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*) from public.users),
    (select count(*) from public.products),
    (select count(*) from public.orders),
    coalesce((select sum(total_price) from public.orders), 0);
$$;

revoke all on function public.claim_outbound_sms(integer) from public, anon, authenticated;
grant execute on function public.claim_outbound_sms(integer) to service_role;
revoke all on function public.place_market_order(text, uuid, numeric) from public, anon, authenticated;
grant execute on function public.place_market_order(text, uuid, numeric) to service_role;
revoke all on function public.marketplace_metrics() from public, anon, authenticated;
grant execute on function public.marketplace_metrics() to service_role;

alter table public.users enable row level security;
alter table public.sessions enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.incoming_sms enable row level security;
alter table public.outbound_sms enable row level security;

create policy "service role manages users"
  on public.users for all to service_role
  using (true) with check (true);
create policy "service role manages sessions"
  on public.sessions for all to service_role
  using (true) with check (true);
create policy "service role manages products"
  on public.products for all to service_role
  using (true) with check (true);
create policy "service role manages orders"
  on public.orders for all to service_role
  using (true) with check (true);
create policy "service role manages incoming sms"
  on public.incoming_sms for all to service_role
  using (true) with check (true);
create policy "service role manages outbound sms"
  on public.outbound_sms for all to service_role
  using (true) with check (true);
