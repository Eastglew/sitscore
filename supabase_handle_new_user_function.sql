-- Supabase Function to create a user profile upon signup
-- This function should be triggered by new user creation in the auth.users table.

-- 1. Create the function.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  user_role text;
begin
  -- Extract the role from the user metadata provided during signup
  -- Adjust the path (
'raw_user_meta_data', 'role'
) if you store the role differently
  user_role := new.raw_user_meta_data->>
'role
';

  -- Insert into public.users table
  insert into public.users (id, email, role)
  values (new.id, new.email, user_role);

  -- Insert into public.profiles table (basic profile)
  insert into public.profiles (user_id)
  values (new.id);

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

