-- Supabase Function to create a user profile upon signup (v2 - includes badge ID)
-- This function should be triggered by new user creation in the auth.users table.

-- 1. Create the function.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  user_role text;
  new_badge_id text;
begin
  -- Extract the role from the user metadata provided during signup
  user_role := new.raw_user_meta_data->>
'role'
;

  -- Generate a unique badge ID (simple example using part of UUID)
  -- In production, consider a more robust/random approach if needed
  new_badge_id := substring(new.id::text from 1 for 8);

  -- Insert into public.users table
  insert into public.users (id, email, role)
  values (new.id, new.email, user_role);

  -- Insert into public.profiles table (basic profile with badge ID)
  insert into public.profiles (user_id, public_badge_id)
  values (new.id, new_badge_id);

  -- Initialize trust score (optional, but good practice)
  -- This ensures the user exists in the trust_scores table immediately
  perform public.calculate_trust_score(new.id);

  return new;
end;
$$;

-- 2. Create the trigger to call the function after a new user is inserted into auth.users.
drop trigger if exists on_auth_user_created on auth.users; -- Drop existing trigger if it exists
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Note: Ensure this function is created by a superuser or with appropriate permissions.
-- You need to run this SQL in your Supabase project's SQL Editor.
-- This REPLACES the previous handle_new_user function.

