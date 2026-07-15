-- ============================================================================
-- FAUNA BATTLER AI - Supabase / PostgreSQL schema
-- ============================================================================
-- Run this in the Supabase SQL editor (or via `supabase db` migrations).
-- It creates the two core tables, enables Row Level Security (RLS), and adds
-- owner-scoped policies so each authenticated player can only read/write their
-- own rows through the public (anon) API.
--
-- NOTE: The Python backend connects with the SERVICE ROLE key and therefore
-- bypasses RLS. These policies protect the *client-side* (anon key) access path.
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
    created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- cards: many rows per player (one per captured card)
-- ---------------------------------------------------------------------------
create table if not exists public.cards (
    id          bigint generated always as identity primary key,
    user_id     uuid not null references auth.users (id) on delete cascade,
    name        text not null,
    rarity      text not null check (rarity in ('Common', 'Uncommon', 'Rare', 'Legendary')),
    hp          integer not null,
    attack      integer not null,
    speed       integer not null,
    defense     integer not null,
    lore        text,
    created_at  timestamptz not null default now()
);

-- Fast lookups of a player's collection.
create index if not exists cards_user_id_idx on public.cards (user_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.cards enable row level security;

-- profiles policies: a user may see and modify only their own profile row.
-- (An UPDATE also requires a SELECT policy in Postgres RLS, which we provide.)
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

-- cards policies: a user may see and add only their own cards.
drop policy if exists "cards_select_own" on public.cards;
create policy "cards_select_own"
    on public.cards for select
    using (auth.uid() = user_id);

drop policy if exists "cards_insert_own" on public.cards;
create policy "cards_insert_own"
    on public.cards for insert
    with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Auto-create a profile row when a new auth user signs up (optional helper).
-- The username falls back to the email local-part; the app can rename later.
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
