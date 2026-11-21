create extension if not exists pg_trgm with schema extensions;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  price numeric(10,2) not null default 0,
  quantity int not null default 0,
  sku text unique,
  created_by text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists products_name_trgm_idx
  on public.products using gin (name gin_trgm_ops);

create table if not exists public.incoming_sms (
  id uuid primary key default gen_random_uuid(),
  sender text not null,
  body text not null,
  subscription_id int,
  created_at timestamptz default now()
);

create table if not exists public.outbound_sms (
  id uuid primary key default gen_random_uuid(),
  phone text not null,
  message text not null,
  status text not null default 'pending',
  attempts int default 0,
  last_error text,
  created_at timestamptz default now(),
  claimed_at timestamptz,
  sent_at timestamptz,
  reply_to_subscription_id int,
  kind text default 'command_reply'
);

create index if not exists outbound_sms_status_created_at_idx
  on public.outbound_sms (status, created_at);

create or replace function public.search_products(q text)
returns setof public.products
language sql
stable
as $$
  select *
  from public.products
  where name ilike '%' || q || '%'
     or description ilike '%' || q || '%'
     or sku ilike '%' || q || '%'
  order by similarity(name, q) desc
  limit 5
$$;

create or replace function public.claim_outbound_sms(batch_size int default 5)
returns setof public.outbound_sms
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  update public.outbound_sms
  set status = 'processing',
      claimed_at = now(),
      attempts = attempts + 1
  where id in (
    select sms.id
    from public.outbound_sms sms
    where sms.status = 'pending'
       or (sms.status = 'processing'
           and sms.claimed_at < now() - interval '2 minutes')
    order by sms.created_at
    for update skip locked
    limit greatest(batch_size, 1)
  )
  returning *;
end;
$$;

alter table public.products enable row level security;
alter table public.incoming_sms enable row level security;
alter table public.outbound_sms enable row level security;

create policy "public can select products"
  on public.products
  for select
  to public
  using (true);

create policy "service role can insert products"
  on public.products
  for insert
  to service_role
  with check (true);

create policy "service role can manage incoming sms"
  on public.incoming_sms
  for all
  to service_role
  using (true)
  with check (true);

create policy "service role can manage outbound sms"
  on public.outbound_sms
  for all
  to service_role
  using (true)
  with check (true);

insert into public.products (name, description, price, quantity, sku)
values
  ('Test Widget', 'Sample test widget', 1.00, 5, 'TEST-001'),
  ('Rice 25kg', '25 kilogram bag of rice', 45.00, 20, 'RICE-25'),
  ('Sugar 5kg', '5 kilogram bag of sugar', 12.50, 30, 'SUGAR-5')
on conflict (sku) do nothing;
