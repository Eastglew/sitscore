// src/lib/supabase/server.ts
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";

export function createClient() {
  const cookieStore = cookies();

  // Create a server-side client instance of Supabase configured to use cookies
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value, ...options });
          } catch (error) {
            // The `set` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing
            // user sessions.
          }
        },
        remove(name: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value: "", ...options });
          } catch (error) {
            // The `delete` method was called from a Server Component.
            // This can be ignored if you have middleware refreshing
            // user sessions.
          }
        },
      },
    }
  );
}

// Helper function to get user session and profile data together
export async function getUserData() {
  const supabase = createClient();
  try {
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      return { user: null, profile: null, error: userError };
    }

    // Fetch profile data including the role from the public.users table
    const { data: profileData, error: profileError } = await supabase
      .from("users") // Fetching from users table where role is stored
      .select("*, profiles(*)") // Select user data and nested profile data
      .eq("id", user.id)
      .single();

    if (profileError) {
      console.error("Error fetching profile:", profileError);
      return { user, profile: null, error: profileError };
    }

    // Combine user and profile data (assuming profileData contains role)
    const userData = {
      ...user,
      ...profileData, // This should include the role
      profile: profileData?.profiles // Attach the nested profile if it exists
    };

    return { user: userData, profile: userData.profile, error: null };

  } catch (error) {
    console.error("Error getting user data:", error);
    return { user: null, profile: null, error };
  }
}

