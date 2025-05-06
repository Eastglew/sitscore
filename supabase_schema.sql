-- SitScore.com Supabase/PostgreSQL Schema (v2 - with Subscription Fields)

-- Enable UUID extension if not already enabled
-- create extension if not exists "uuid-ossp";

-- 1. Users Table (Public view of auth users + role)
-- Stores basic user info and role, linked to auth.users
create table if not exists public.users (
  id uuid not null primary key, -- Matches auth.users.id
  email text, -- Can be fetched from auth.users
  role text, -- e.g., 'Pet Sitter', 'Dog Walker', 'Both', 'Agency Admin'
  -- Stripe Subscription Fields
  subscription_id text, -- Stripe Subscription ID (sub_...)
  subscription_status text, -- e.g., 'active', 'trialing', 'past_due', 'canceled', 'incomplete'
  current_period_end timestamp with time zone, -- End date of the current billing cycle
  subscribed_price_id text, -- Stripe Price ID (price_...) of the active subscription

  constraint users_id_fkey foreign key (id) references auth.users (id) on delete cascade
);
-- Enable Row Level Security (RLS)
alter table public.users enable row level security;
-- Policies for users table:
-- Allow users to read their own user record
create policy "Allow individual user read access" on public.users for select
  using (auth.uid() = id);
-- Allow backend service roles (e.g., for triggers, admin tasks) to bypass RLS
-- create policy "Allow service_role access" on public.users for all
-- using (auth.role() = 'service_role'); -- Adjust role name as needed

-- 2. Profiles Table
-- Stores public profile information, linked to users table
create table if not exists public.profiles (
  user_id uuid not null primary key,
  name text,
  location text, -- e.g., "City, State"
  bio text,
  profile_image_url text,
  public_badge_id text unique, -- Unique, shareable ID for public profile URL
  stripe_customer_id text unique, -- Stripe Customer ID (cus_...)
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,

  constraint profiles_user_id_fkey foreign key (user_id) references public.users (id) on delete cascade
);
-- Enable RLS
alter table public.profiles enable row level security;
-- Policies for profiles table:
-- Allow users to read any profile (for public profiles)
create policy "Allow public read access" on public.profiles for select
  using (true);
-- Allow users to update their own profile
create policy "Allow individual user update access" on public.profiles for update
  using (auth.uid() = user_id);
-- Allow service roles access
-- create policy "Allow service_role access" on public.profiles for all
-- using (auth.role() = 'service_role');

-- 3. Documents Table
-- Stores information about uploaded verification documents
create table if not exists public.documents (
  id uuid default gen_random_uuid() primary key,
  user_id uuid not null,
  document_type text not null, -- e.g., 'ID', 'CPR', 'Insurance'
  file_url text not null, -- URL to the file in Supabase Storage
  uploaded_at timestamp with time zone default timezone('utc'::text, now()) not null,
  verification_status text default 'Pending'::text, -- 'Pending', 'Verified', 'Rejected'
  verified_at timestamp with time zone,
  verified_by uuid, -- User ID of the admin who verified/rejected
  rejection_reason text, -- Optional reason if status is 'Rejected'
  uploaded_by_agency_id uuid, -- Optional: Track if uploaded by agency admin

  constraint documents_user_id_fkey foreign key (user_id) references public.users (id) on delete cascade,
  -- constraint documents_verified_by_fkey foreign key (verified_by) references auth.users (id),
  -- constraint documents_agency_id_fkey foreign key (uploaded_by_agency_id) references public.agencies (id),
  constraint documents_user_id_document_type_key unique (user_id, document_type) -- Ensure only one doc of each type per user
);
-- Enable RLS
alter table public.documents enable row level security;
-- Policies for documents table:
-- Allow users to read their own documents
create policy "Allow individual user read access" on public.documents for select
  using (auth.uid() = user_id);
-- Allow users to insert their own documents
create policy "Allow individual user insert access" on public.documents for insert
  with check (auth.uid() = user_id);
-- Allow users to update their own documents (e.g., re-upload)
create policy "Allow individual user update access" on public.documents for update
  using (auth.uid() = user_id);
-- Allow agency admins to manage documents for their members (Requires agency membership logic)
-- create policy "Allow agency admin access" on public.documents for all
-- using ( is_agency_admin(auth.uid()) and is_member_of_agency(user_id, get_user_agency_id(auth.uid())) );
-- Allow service roles access
-- create policy "Allow service_role access" on public.documents for all
-- using (auth.role() = 'service_role');

-- 4. Trust Scores Table
-- Stores the calculated trust score and tier for each user
create table if not exists public.trust_scores (
  user_id uuid not null primary key,
  score integer default 0 not null,
  tier text, -- e.g., 'Bronze', 'Silver', 'Gold'
  score_breakdown jsonb, -- Store components of the score (e.g., {"id_verified": 20, "cpr_verified": 15, ...})
  last_calculated_at timestamp with time zone default timezone('utc'::text, now()) not null,

  constraint trust_scores_user_id_fkey foreign key (user_id) references public.users (id) on delete cascade
);
-- Enable RLS
alter table public.trust_scores enable row level security;
-- Policies for trust_scores table:
-- Allow users to read any trust score (for public profiles/lookup)
create policy "Allow public read access" on public.trust_scores for select
  using (true);
-- Allow service roles access (needed for trigger functions to update scores)
create policy "Allow service_role update access" on public.trust_scores for update
  using (auth.role() = 'service_role');
-- Allow service roles insert access
create policy "Allow service_role insert access" on public.trust_scores for insert
  with check (auth.role() = 'service_role');

-- 5. Reviews Table
-- Stores reviews left by pet owners (assuming owners are external or have a separate login)
create table if not exists public.reviews (
  id uuid default gen_random_uuid() primary key,
  user_id uuid not null, -- The sitter/walker being reviewed
  reviewer_name text, -- Name of the pet owner
  reviewer_email text, -- Optional: Email of the pet owner
  rating integer, -- e.g., 1-5 stars
  review_text text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  sentiment_score integer, -- Calculated by trigger (-1, 0, 1)

  constraint reviews_user_id_fkey foreign key (user_id) references public.users (id) on delete cascade,
  constraint reviews_rating_check check ((rating >= 1) and (rating <= 5))
);
-- Enable RLS
alter table public.reviews enable row level security;
-- Policies for reviews table:
-- Allow public read access to reviews
create policy "Allow public read access" on public.reviews for select
  using (true);
-- Allow authenticated users to insert reviews (adjust based on who can leave reviews)
create policy "Allow authenticated users insert access" on public.reviews for insert
  with check (auth.role() = 'authenticated');
-- Allow service roles access
-- create policy "Allow service_role access" on public.reviews for all
-- using (auth.role() = 'service_role');

-- 6. Agencies Table
-- Stores information about agencies/teams
create table if not exists public.agencies (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  owner_user_id uuid not null, -- The user who created/owns the agency
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  -- Add other agency-specific settings if needed

  constraint agencies_owner_user_id_fkey foreign key (owner_user_id) references public.users (id)
);
-- Enable RLS
alter table public.agencies enable row level security;
-- Policies for agencies table:
-- Allow agency owners/admins to read their agency details
create policy "Allow owner read access" on public.agencies for select
  using (auth.uid() = owner_user_id); -- Add check for agency admins later
-- Allow agency owners to update their agency details
create policy "Allow owner update access" on public.agencies for update
  using (auth.uid() = owner_user_id);
-- Allow users to create agencies (maybe restrict based on subscription?)
create policy "Allow authenticated users insert access" on public.agencies for insert
  with check (auth.role() = 'authenticated');
-- Allow service roles access
-- create policy "Allow service_role access" on public.agencies for all
-- using (auth.role() = 'service_role');

-- 7. Agency Members Table (Join Table)
-- Links users to agencies
create table if not exists public.agency_members (
  agency_id uuid not null,
  user_id uuid not null,
  member_role text default 'Member'::text, -- e.g., 'Member', 'Admin'
  joined_at timestamp with time zone default timezone('utc'::text, now()) not null,

  primary key (agency_id, user_id),
  constraint agency_members_agency_id_fkey foreign key (agency_id) references public.agencies (id) on delete cascade,
  constraint agency_members_user_id_fkey foreign key (user_id) references public.users (id) on delete cascade
);
-- Enable RLS
alter table public.agency_members enable row level security;
-- Policies for agency_members table:
-- Allow members to see their own membership
create policy "Allow member read access" on public.agency_members for select
  using (auth.uid() = user_id);
-- Allow agency admins/owners to see all members of their agency
create policy "Allow agency admin read access" on public.agency_members for select
  using ( agency_id = (select agency_id from public.agency_members where user_id = auth.uid() and member_role = 'Admin') -- Placeholder logic
          or agency_id = (select id from public.agencies where owner_user_id = auth.uid()) );
-- Allow agency admins/owners to add/remove members
create policy "Allow agency admin manage access" on public.agency_members for all
  using ( agency_id = (select agency_id from public.agency_members where user_id = auth.uid() and member_role = 'Admin') -- Placeholder logic
          or agency_id = (select id from public.agencies where owner_user_id = auth.uid()) );
-- Allow service roles access
-- create policy "Allow service_role access" on public.agency_members for all
-- using (auth.role() = 'service_role');


-- Indexes (Optional but recommended for performance)
create index if not exists idx_profiles_public_badge_id on public.profiles(public_badge_id);
create index if not exists idx_documents_user_id on public.documents(user_id);
create index if not exists idx_reviews_user_id on public.reviews(user_id);
create index if not exists idx_agencies_owner_user_id on public.agencies(owner_user_id);
create index if not exists idx_agency_members_user_id on public.agency_members(user_id);
create index if not exists idx_users_subscription_status on public.users(subscription_status);

-- Note: RLS policies are examples and need refinement based on exact access control requirements,
-- especially for agency admin roles. Helper functions (e.g., is_agency_admin) might be needed.
-- Remember to apply this schema in your Supabase project's SQL Editor.

