import React, { useEffect, useState } from 'react';
import { Redirect, Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useSession } from '../../lib/session';
import { uploadQueue, type QueuedUpload } from '../../lib/uploads';
import { useTheme } from '../../lib/theme';

export default function TabsLayout() {
  const t = useTheme();
  const { ready, session, active, isStaff } = useSession();
  const [pending, setPending] = useState(0);
  useEffect(() => uploadQueue.subscribe((items: QueuedUpload[]) => setPending(items.filter((i) => i.status !== 'done').length)), []);

  if (ready && (!session || !active)) return <Redirect href="/" />;
  const icon = (name: React.ComponentProps<typeof Ionicons>['name']) =>
    ({ color, size }: { color: string; size: number }) => <Ionicons name={name} color={color} size={size} />;

  return (
    <Tabs screenOptions={{
      tabBarActiveTintColor: t.ink, tabBarInactiveTintColor: t.muted,
      tabBarStyle: { backgroundColor: t.bg, borderTopColor: t.line },
      headerStyle: { backgroundColor: t.bg }, headerTintColor: t.ink,
      tabBarLabelStyle: { fontSize: 12, fontWeight: '600' },
    }}>
      <Tabs.Screen name="home" options={{ title: isStaff ? 'Pupils' : 'Updates', tabBarIcon: icon(isStaff ? 'people-outline' : 'home-outline') }} />
      <Tabs.Screen name="new" options={{ title: 'New clip', href: isStaff ? undefined : null, tabBarIcon: icon('add-circle-outline') }} />
      <Tabs.Screen name="uploads" options={{ title: 'Uploads', href: isStaff ? undefined : null, tabBarIcon: icon('cloud-upload-outline'), tabBarBadge: pending || undefined }} />
      <Tabs.Screen name="account" options={{ title: 'Account', tabBarIcon: icon('person-circle-outline') }} />
    </Tabs>
  );
}
