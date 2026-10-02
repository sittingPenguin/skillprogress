import React from 'react';
import { Redirect } from 'expo-router';
import { useSession } from '../lib/session';
import { isConfigured } from '../lib/supabase';
import { Button, Empty, Loading, Notice, Screen } from '../components/ui';

export default function Index() {
  const { ready, session, memberships, signOut } = useSession();
  if (!isConfigured) {
    return <Screen><Notice kind="warn">This build is missing its server settings (EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_KEY).</Notice></Screen>;
  }
  if (!ready) return <Screen><Loading /></Screen>;
  if (!session) return <Redirect href="/sign-in" />;
  if (memberships.length === 0) {
    return (
      <Screen>
        <Empty icon="lock-closed-outline" title="No access yet" body="Your account isn’t linked to a school. If you’re a parent, use the invitation your school sent you. Staff should ask the school admin." />
        <Button label="Sign out" kind="secondary" onPress={signOut} />
      </Screen>
    );
  }
  return <Redirect href="/home" />;
}
