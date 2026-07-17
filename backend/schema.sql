-- ============================================================================
-- FAUNA - Supabase / PostgreSQL schema (pure collection game)
-- ============================================================================
-- Run this in the Supabase SQL editor (or via `supabase db` migrations).
--
-- Tables:
--   profiles           one row per player
--   user_cards         one row per captured species (no combat stats)
--   species_reference  shared, cached iNaturalist reference per species name
--
-- NOTE: The Python backend connects with the SERVICE ROLE key and therefore
-- bypasses RLS. The policies below protect the *client-side* (anon key) path.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- profiles: one row per player
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
    user_id       uuid primary key references auth.users (id) on delete cascade,
    username      text unique not null,
    player_rank   integer not null default 1,
    gold          integer not null default 100,
    wild_essence  integer not null default 50,
    xp            integer not null default 0,
    level         integer not null default 1,
    created_at    timestamptz not null default now()
);

-- Backfill for existing deployments (safe to re-run).
alter table public.profiles add column if not exists xp integer not null default 0;
alter table public.profiles add column if not exists level integer not null default 1;

-- ---------------------------------------------------------------------------
-- user_cards: many rows per player (one per captured species)
-- ---------------------------------------------------------------------------
create table if not exists public.user_cards (
    card_id             uuid primary key default gen_random_uuid(),
    user_id             uuid not null references public.profiles (user_id) on delete cascade,
    name                text not null,
    scientific_name     text,
    taxon_id            bigint,
    normalized_name     text,
    rarity              text not null check (rarity in ('Common', 'Uncommon', 'Rare', 'Legendary')),
    reference_photo_url text,
    category            text,
    wiki_url            text,
    lore                text,
    captured_at         timestamptz,
    capture_lat         double precision,
    capture_lng         double precision,
    created_at          timestamptz not null default now()
);

-- Backfill for existing deployments (safe to re-run).
alter table public.user_cards add column if not exists taxon_id bigint;
alter table public.user_cards add column if not exists normalized_name text;

create index if not exists user_cards_user_id_idx on public.user_cards (user_id);
create index if not exists user_cards_taxon_id_idx on public.user_cards (taxon_id);
create index if not exists user_cards_normalized_name_idx on public.user_cards (normalized_name);

-- ---------------------------------------------------------------------------
-- species_reference: shared reference data, cached once per species name so
-- every player sees the identical photo + category for e.g. "Red Fox".
-- ---------------------------------------------------------------------------
create table if not exists public.species_reference (
    species_name    text primary key,
    photo_url       text,
    category        text,
    wiki_url        text,
    taxon_id        bigint,
    scientific_name text,
    cached_at       timestamptz not null default now()
);

-- Backfill for existing deployments (safe to re-run).
alter table public.species_reference add column if not exists taxon_id bigint;
alter table public.species_reference add column if not exists scientific_name text;

-- ---------------------------------------------------------------------------
-- species_catalog: the fixed master "dex" list. Populated once from
-- iNaturalist by backend/seed_catalog.py; identical for every player.
-- ---------------------------------------------------------------------------
create table if not exists public.species_catalog (
    taxon_id            bigint primary key,
    dex_number          integer not null,
    name                text not null,
    scientific_name     text,
    category            text not null default 'Wildlife',
    rarity              text not null default 'Common'
                          check (rarity in ('Common', 'Uncommon', 'Rare', 'Legendary')),
    reference_photo_url text,
    created_at          timestamptz not null default now()
);

create index if not exists species_catalog_dex_number_idx
    on public.species_catalog (dex_number);

-- ---------------------------------------------------------------------------
-- friendships: minimal friend graph (pending / accepted).
-- One row per directed request; acceptance flips status on that same row.
-- ---------------------------------------------------------------------------
create table if not exists public.friendships (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references public.profiles (user_id) on delete cascade,
    friend_id  uuid not null references public.profiles (user_id) on delete cascade,
    status     text not null default 'pending' check (status in ('pending', 'accepted')),
    created_at timestamptz not null default now(),
    unique (user_id, friend_id)
);

create index if not exists friendships_user_id_idx on public.friendships (user_id);
create index if not exists friendships_friend_id_idx on public.friendships (friend_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.user_cards enable row level security;
alter table public.species_reference enable row level security;
alter table public.friendships enable row level security;
alter table public.species_catalog enable row level security;

-- profiles: a user may see and modify only their own profile row.
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own"
    on public.profiles for select
    using (auth.uid() = user_id);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
    on public.profiles for insert
    with check (auth.uid() = user_id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
    on public.profiles for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- user_cards: a user may see and add only their own cards.
drop policy if exists "user_cards_select_own" on public.user_cards;
create policy "user_cards_select_own"
    on public.user_cards for select
    using (auth.uid() = user_id);

drop policy if exists "user_cards_insert_own" on public.user_cards;
create policy "user_cards_insert_own"
    on public.user_cards for insert
    with check (auth.uid() = user_id);

-- species_reference: shared read for everyone; writes go through the backend
-- (service role), so no client insert/update policy is granted.
drop policy if exists "species_reference_select_all" on public.species_reference;
create policy "species_reference_select_all"
    on public.species_reference for select
    using (true);

-- species_catalog: shared read for everyone; writes go through the backend
-- (service role / seed script), so no client insert/update policy is granted.
drop policy if exists "species_catalog_select_all" on public.species_catalog;
create policy "species_catalog_select_all"
    on public.species_catalog for select
    using (true);

-- friendships: a user may see rows where they are either side; writes go
-- through the backend (service role), so no client insert/update policy.
drop policy if exists "friendships_select_involved" on public.friendships;
create policy "friendships_select_involved"
    on public.friendships for select
    using (auth.uid() = user_id or auth.uid() = friend_id);

-- profiles: allow authenticated users to look each other up (friend search /
-- read-only friend profiles). Only non-sensitive columns are exposed by the API.
drop policy if exists "profiles_select_all" on public.profiles;
create policy "profiles_select_all"
    on public.profiles for select
    using (auth.role() = 'authenticated');

-- ---------------------------------------------------------------------------
-- Auto-create a profile row when a new auth user signs up (optional helper).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (user_id, username)
    values (
        new.id,
        coalesce(split_part(new.email, '@', 1), 'player_' || substr(new.id::text, 1, 8))
    )
    on conflict (user_id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
