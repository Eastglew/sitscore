import { createClient } from '@supabase/supabase-js';

// Fetch Supabase URL and Anon Key from environment variables
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

// Basic validation
if (!supabaseUrl) {
  console.error('Error: Missing environment variable NEXT_PUBLIC_SUPABASE_URL');
  // In a real app, you might throw an error or handle this differently
}
if (!supabaseAnonKey) {
  console.error('Error: Missing environment variable NEXT_PUBLIC_SUPABASE_ANON_KEY');
  // In a real app, you might throw an error or handle this differently
}

// Create and export the Supabase client
// We check if the variables exist before creating the client to avoid errors during build/runtime if they are missing.
export const supabase = (supabaseUrl && supabaseAnonKey)
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null;

// Helper function to get the client, potentially throwing an error if not configured
export const getSupabaseClient = () => {
  if (!supabase) {
    throw new Error('Supabase client is not initialized. Check environment variables.');
  }
  return supabase;
};

