-- T15 Weplay Auction House database setup for Supabase.
-- Run the complete file in Supabase Dashboard > SQL Editor.
-- This script is designed for a new project. Review before rerunning on an existing database.

create extension if not exists pgcrypto;

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 90),
  description text not null check (char_length(description) between 5 and 3000),
  category text not null check (category in ('Electronics','Gaming','Fashion','Collectibles','Digital Goods','Services','Home & Living','Other')),
  price numeric(12,2) not null check (price >= 0),
  discord_username text not null check (char_length(discord_username) between 2 and 80),
  location text check (location is null or char_length(location) <= 100),
  image_url text,
  status text not null default 'active' check (status in ('active','sold','hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists listings_status_created_at_idx on public.listings (status, created_at desc);
create index if not exists listings_category_idx on public.listings (category);
create index if not exists listings_user_id_idx on public.listings (user_id);

alter table public.listings enable row level security;

-- Public can read active listings only. The UI's search is client-side for the first version.
drop policy if exists "Anyone can read active listings" on public.listings;
create policy "Anyone can read active listings" on public.listings
  for select to anon, authenticated using (status = 'active' or (auth.uid() = user_id));

drop policy if exists "Authenticated users can create their own listings" on public.listings;
create policy "Authenticated users can create their own listings" on public.listings
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "Owners can update their own listings" on public.listings;
create policy "Owners can update their own listings" on public.listings
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Owners can delete their own listings" on public.listings;
create policy "Owners can delete their own listings" on public.listings
  for delete to authenticated using (auth.uid() = user_id);

-- Public image bucket: images are visible to anyone who can view a listing.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-images', 'listing-images', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Anyone may view images in the public listing bucket.
drop policy if exists "Public can view listing images" on storage.objects;
create policy "Public can view listing images" on storage.objects
  for select to anon, authenticated using (bucket_id = 'listing-images');

-- A signed-in user may upload only under their own auth UID folder.
drop policy if exists "Users upload listing images to own folder" on storage.objects;
create policy "Users upload listing images to own folder" on storage.objects
  for insert to authenticated with check (bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users update listing images in own folder" on storage.objects;
create policy "Users update listing images in own folder" on storage.objects
  for update to authenticated using (bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users delete listing images in own folder" on storage.objects;
create policy "Users delete listing images in own folder" on storage.objects
  for delete to authenticated using (bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- Note: listing removal does not automatically delete its uploaded image object.
-- For production, add a trusted server-side cleanup job/Edge Function if image cleanup is required.
