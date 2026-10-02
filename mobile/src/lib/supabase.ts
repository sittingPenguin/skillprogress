// Supabase client. The publishable key is designed to ship in apps: the database's
// row-level security decides what each signed-in person can see.
import 'react-native-url-polyfill/auto';
import { AppState, Platform } from 'react-native';
import { createClient } from '@supabase/supabase-js';
import { secureSessionStorage } from './secureStorage';

export const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL ?? '';
export const SUPABASE_KEY = process.env.EXPO_PUBLIC_SUPABASE_KEY ?? '';
export const isConfigured = SUPABASE_URL.startsWith('https://') && SUPABASE_KEY.length > 20;

export const supabase = createClient(SUPABASE_URL || 'https://not-configured.invalid', SUPABASE_KEY || 'missing', {
  auth: {
    storage: secureSessionStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: Platform.OS === 'web',
  },
});

// Refresh tokens only while the app is in the foreground.
if (Platform.OS !== 'web') {
  AppState.addEventListener('change', (state) => {
    if (state === 'active') supabase.auth.startAutoRefresh();
    else supabase.auth.stopAutoRefresh();
  });
}

export const VIDEO_BUCKET = 'clips';
export const VIDEO_LINK_SECONDS = 300;
