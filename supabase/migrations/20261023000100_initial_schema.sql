-- AI-Powered Personal Finance & Receipt Tracker
-- Supabase / PostgreSQL migration. Assumes the standard auth schema is enabled.

create extension if not exists pgcrypto;

create type public.transaction_type as enum ('income', 'expense');
create type public.receipt_status as enum ('uploaded', 'processing', 'ready_for_review', 'failed', 'linked');
create type public.receipt_scan_status as enum ('succeeded', 'failed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  currency_code text not null default 'THB' check (currency_code ~ '^[A-Z]{3}$'),
  timezone text not null default 'Asia/Bangkok',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Categories are user-owned, including a user's seeded defaults. This keeps
-- transaction ownership enforceable with ordinary composite foreign keys.
create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 60),
  type public.transaction_type not null,
  color text,
  icon text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  constraint categories_user_id_id_unique unique (user_id, id),
  constraint categories_user_id_id_type_unique unique (user_id, id, type)
);

create unique index categories_user_type_name_unique
  on public.categories (user_id, type, lower(name));

create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp', 'application/pdf')),
  byte_size bigint not null check (byte_size > 0),
  status public.receipt_status not null default 'uploaded',
  uploaded_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint receipts_user_id_id_unique unique (user_id, id)
);

create index receipts_user_uploaded_idx on public.receipts (user_id, uploaded_at desc);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null,
  type public.transaction_type not null,
  amount numeric(14,2) not null check (amount > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  occurred_at timestamptz not null,
  merchant text check (merchant is null or length(merchant) <= 160),
  note text check (note is null or length(note) <= 1000),
  source text not null default 'manual' check (source in ('manual', 'receipt')),
  receipt_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transactions_category_owner_type_fk
    foreign key (user_id, category_id, type)
    references public.categories (user_id, id, type)
    on delete restrict,
  constraint transactions_receipt_owner_fk
    foreign key (user_id, receipt_id)
    references public.receipts (user_id, id)
    on delete set null (receipt_id),
  constraint transactions_user_id_id_unique unique (user_id, id),
  constraint transactions_receipt_unique unique (receipt_id),
  constraint transactions_source_receipt_check check (
    source = 'receipt' or receipt_id is null
  )
);

create index transactions_user_occurred_idx
  on public.transactions (user_id, occurred_at desc);
create index transactions_user_category_occurred_idx
  on public.transactions (user_id, category_id, occurred_at desc);

-- Store month as the first day of that month. Application computes month
-- boundaries in the profile timezone before querying transaction timestamps.
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null,
  category_type public.transaction_type not null default 'expense'
    check (category_type = 'expense'),
  month date not null check (extract(day from month) = 1),
  limit_amount numeric(14,2) not null check (limit_amount > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint budgets_category_owner_type_fk
    foreign key (user_id, category_id, category_type)
    references public.categories (user_id, id, type)
    on delete restrict,
  constraint budgets_user_category_month_unique unique (user_id, category_id, month),
  constraint budgets_user_id_id_unique unique (user_id, id)
);

create index budgets_user_month_idx on public.budgets (user_id, month);

-- Each row is one model/OCR attempt. Keeping attempts separate preserves a
-- retry/audit trail without overwriting earlier extraction results.
create table public.receipt_scans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  receipt_id uuid not null,
  provider text not null default 'gemini' check (length(provider) between 1 and 40),
  model_name text,
  status public.receipt_scan_status not null,
  merchant text,
  extracted_at timestamptz,
  total_amount numeric(14,2) check (total_amount is null or total_amount > 0),
  currency_code text check (currency_code is null or currency_code ~ '^[A-Z]{3}$'),
  suggested_category_id uuid,
  confidence numeric(5,4) check (confidence is null or confidence between 0 and 1),
  raw_result jsonb,
  error_code text,
  created_at timestamptz not null default now(),
  constraint receipt_scans_receipt_owner_fk
    foreign key (user_id, receipt_id)
    references public.receipts (user_id, id)
    on delete cascade,
  constraint receipt_scans_category_owner_fk
    foreign key (user_id, suggested_category_id)
    references public.categories (user_id, id)
    on delete set null (suggested_category_id),
  constraint receipt_scans_success_data_check check (
    status <> 'succeeded' or (total_amount is not null and extracted_at is not null)
  )
);

create index receipt_scans_receipt_created_idx on public.receipt_scans (receipt_id, created_at desc);

create function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger transactions_set_updated_at before update on public.transactions
for each row execute function public.set_updated_at();
create trigger budgets_set_updated_at before update on public.budgets
for each row execute function public.set_updated_at();

-- Create a profile and starter categories when a Supabase Auth user is created.
create function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', new.raw_user_meta_data ->> 'full_name'));

  insert into public.categories (user_id, name, type, color, icon) values
    (new.id, 'อาหาร', 'expense', '#E58B58', 'utensils'),
    (new.id, 'เดินทาง', 'expense', '#6B91C7', 'bus'),
    (new.id, 'ที่อยู่อาศัย', 'expense', '#8C78B8', 'home'),
    (new.id, 'ของใช้', 'expense', '#65A88B', 'shopping-bag'),
    (new.id, 'สุขภาพ', 'expense', '#D16F75', 'heart-pulse'),
    (new.id, 'บันเทิง', 'expense', '#D2A94F', 'clapperboard'),
    (new.id, 'อื่น ๆ', 'expense', '#87919B', 'circle-ellipsis'),
    (new.id, 'เงินเดือน', 'income', '#65A88B', 'briefcase'),
    (new.id, 'รายได้อื่น', 'income', '#6B91C7', 'wallet');

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS: all user-owned records are isolated by auth.uid().
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.receipts enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets enable row level security;
alter table public.receipt_scans enable row level security;

create policy "profiles_select_own" on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "profiles_insert_own" on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy "profiles_update_own" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "categories_select_own" on public.categories for select to authenticated using (user_id = (select auth.uid()));
create policy "categories_insert_own" on public.categories for insert to authenticated with check (user_id = (select auth.uid()));
create policy "categories_update_own" on public.categories for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "categories_delete_own" on public.categories for delete to authenticated using (user_id = (select auth.uid()));

create policy "receipts_select_own" on public.receipts for select to authenticated using (user_id = (select auth.uid()));
create policy "receipts_insert_own" on public.receipts for insert to authenticated with check (user_id = (select auth.uid()));
create policy "receipts_update_own" on public.receipts for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "receipts_delete_own" on public.receipts for delete to authenticated using (user_id = (select auth.uid()));

create policy "transactions_select_own" on public.transactions for select to authenticated using (user_id = (select auth.uid()));
create policy "transactions_insert_own" on public.transactions for insert to authenticated with check (user_id = (select auth.uid()));
create policy "transactions_update_own" on public.transactions for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "transactions_delete_own" on public.transactions for delete to authenticated using (user_id = (select auth.uid()));

create policy "budgets_select_own" on public.budgets for select to authenticated using (user_id = (select auth.uid()));
create policy "budgets_insert_own" on public.budgets for insert to authenticated with check (user_id = (select auth.uid()));
create policy "budgets_update_own" on public.budgets for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "budgets_delete_own" on public.budgets for delete to authenticated using (user_id = (select auth.uid()));

create policy "receipt_scans_select_own" on public.receipt_scans for select to authenticated using (user_id = (select auth.uid()));
create policy "receipt_scans_insert_own" on public.receipt_scans for insert to authenticated with check (user_id = (select auth.uid()));
create policy "receipt_scans_delete_own" on public.receipt_scans for delete to authenticated using (user_id = (select auth.uid()));

-- Storage setup (run once in Supabase SQL editor or add to deployment config).
-- Create a PRIVATE bucket named `receipts`; then apply these policies to storage.objects:
--
-- create policy "receipt_objects_select_own" on storage.objects for select to authenticated
--   using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- create policy "receipt_objects_insert_own" on storage.objects for insert to authenticated
--   with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- create policy "receipt_objects_update_own" on storage.objects for update to authenticated
--   using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text)
--   with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- create policy "receipt_objects_delete_own" on storage.objects for delete to authenticated
--   using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
-- Store objects under {auth.uid()}/{receipt_uuid}/{filename}; validate MIME/size server-side.



