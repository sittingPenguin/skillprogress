import React, { useEffect } from 'react';
import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { Platform } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { SessionProvider } from '../lib/session';
import { uploadQueue } from '../lib/uploads';
import { useTheme } from '../lib/theme';

export default function RootLayout() {
  const t = useTheme();
  useEffect(() => { if (Platform.OS !== 'web') uploadQueue.init(); }, []);
  return (
    <SafeAreaProvider>
      <SessionProvider>
        <StatusBar style="auto" />
        <Stack screenOptions={{ headerTintColor: t.ink, headerStyle: { backgroundColor: t.bg }, contentStyle: { backgroundColor: t.bg }, headerBackButtonDisplayMode: 'minimal' }}>
          <Stack.Screen name="index" options={{ headerShown: false }} />
          <Stack.Screen name="sign-in" options={{ headerShown: false }} />
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="pupil/[id]" options={{ title: 'Pupil' }} />
          <Stack.Screen name="clip/[id]" options={{ title: 'Clip' }} />
          <Stack.Screen name="assess/[id]" options={{ title: 'Assess clip' }} />
          <Stack.Screen name="record" options={{ headerShown: false, presentation: 'fullScreenModal' }} />
        </Stack>
      </SessionProvider>
    </SafeAreaProvider>
  );
}
