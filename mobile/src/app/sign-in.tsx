import React, { useState } from 'react';
import { KeyboardAvoidingView, Platform, Text, View } from 'react-native';
import { router } from 'expo-router';
import { supabase } from '../lib/supabase';
import { useTheme } from '../lib/theme';
import { Button, Field, Notice, P, Screen } from '../components/ui';

export default function SignIn() {
  const t = useTheme();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true); setError(null);
    const { error: e } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (e) {
      setError(/invalid/i.test(e.message)
        ? 'That email and password don’t match. Check them and try again.'
        : /network|fetch/i.test(e.message) ? 'Can’t reach SkillProgress. Check your connection and try again.' : e.message);
      return;
    }
    router.replace('/');
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: t.bg }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <Screen>
        <View style={{ gap: 6, marginTop: 48 }}>
          <Text accessibilityRole="header" style={{ fontSize: 32, fontWeight: '800', color: t.ink, letterSpacing: -0.5 }}>
            Skill<Text style={{ color: t.accent }}>Progress</Text>
          </Text>
          <P muted>Private coaching feedback for your school. Nothing here is public.</P>
        </View>
        <Field label="Email" value={email} onChangeText={setEmail} autoCapitalize="none" autoComplete="email" keyboardType="email-address" textContentType="username" />
        <Field label="Password" value={password} onChangeText={setPassword} secureTextEntry autoComplete="password" textContentType="password" onSubmitEditing={submit} />
        {error ? <Notice kind="warn">{error}</Notice> : null}
        <Button label="Sign in" onPress={submit} busy={busy} disabled={!email || !password} />
        <P muted>Forgotten your password, or need an account? Ask your school’s SkillProgress admin.</P>
      </Screen>
    </KeyboardAvoidingView>
  );
}
