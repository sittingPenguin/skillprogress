import React from 'react';
import {
  ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
  type PressableProps, type TextInputProps, type ViewStyle,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { radius, space, touch, useTheme } from '../lib/theme';

export type IconName = React.ComponentProps<typeof Ionicons>['name'];

export function Screen({ children, scroll = true, padded = true }: { children: React.ReactNode; scroll?: boolean; padded?: boolean }) {
  const t = useTheme();
  const inner = <View style={[{ maxWidth: 720, width: '100%', alignSelf: 'center' }, padded && { padding: space.l, gap: space.l }]}>{children}</View>;
  return (
    <SafeAreaView edges={['bottom']} style={{ flex: 1, backgroundColor: t.bg }}>
      {scroll ? <ScrollView keyboardShouldPersistTaps="handled">{inner}</ScrollView> : inner}
    </SafeAreaView>
  );
}

export function H1({ children }: { children: React.ReactNode }) {
  const t = useTheme();
  return <Text accessibilityRole="header" style={{ fontSize: 24, fontWeight: '800', color: t.ink }}>{children}</Text>;
}
export function H2({ children }: { children: React.ReactNode }) {
  const t = useTheme();
  return <Text accessibilityRole="header" style={{ fontSize: 18, fontWeight: '700', color: t.ink }}>{children}</Text>;
}
export function P({ children, muted, style }: { children: React.ReactNode; muted?: boolean; style?: object }) {
  const t = useTheme();
  return <Text style={[{ fontSize: 15, lineHeight: 21, color: muted ? t.muted : t.ink }, style]}>{children}</Text>;
}

type BtnKind = 'primary' | 'secondary' | 'accent' | 'danger';
export function Button({ label, kind = 'primary', icon, busy, disabled, style, ...rest }:
  { label: string; kind?: BtnKind; icon?: IconName; busy?: boolean; style?: ViewStyle } & PressableProps) {
  const t = useTheme();
  const bg = { primary: t.ink, secondary: t.surface, accent: t.accent, danger: t.surface }[kind];
  const fg = { primary: t.onInk, secondary: t.ink, accent: '#FFFFFF', danger: t.accent }[kind];
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ disabled: !!disabled || !!busy, busy: !!busy }}
      disabled={disabled || busy}
      style={({ pressed }) => [
        styles.btn,
        { backgroundColor: bg, borderColor: t.line, borderWidth: kind === 'secondary' || kind === 'danger' ? 1 : 0, opacity: disabled ? 0.45 : pressed ? 0.8 : 1 },
        style,
      ]}
      {...rest}
    >
      {busy ? <ActivityIndicator color={fg} /> : icon ? <Ionicons name={icon} size={20} color={fg} /> : null}
      <Text style={{ color: fg, fontWeight: '700', fontSize: 16 }}>{label}</Text>
    </Pressable>
  );
}

export function Field({ label, hint, ...rest }: { label: string; hint?: string } & TextInputProps) {
  const t = useTheme();
  return (
    <View style={{ gap: 6 }}>
      <Text style={{ fontWeight: '600', color: t.ink, fontSize: 15 }}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        placeholderTextColor={t.muted}
        style={{ borderWidth: 1, borderColor: t.line, borderRadius: radius.m, paddingHorizontal: 14, minHeight: touch, fontSize: 16, color: t.ink, backgroundColor: t.bg }}
        {...rest}
      />
      {hint ? <Text style={{ fontSize: 13, color: t.muted }}>{hint}</Text> : null}
    </View>
  );
}

type PillKind = 'published' | 'draft' | 'review' | 'uploading' | 'failed' | 'private' | 'info';
export function Pill({ kind, label }: { kind: PillKind; label: string }) {
  const t = useTheme();
  const map: Record<PillKind, [string, string, IconName]> = {
    published: [t.okSoft, t.ok, 'checkmark'],
    draft: [t.draftSoft, t.draft, 'create-outline'],
    review: [t.warnSoft, t.warn, 'flag-outline'],
    uploading: [t.brandSoft, t.brand, 'cloud-upload-outline'],
    failed: [t.warnSoft, t.warn, 'alert-circle-outline'],
    private: [t.surface, t.muted, 'lock-closed-outline'],
    info: [t.brandSoft, t.brand, 'information-circle-outline'],
  };
  const [bg, fg, ic] = map[kind];
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: bg, borderRadius: radius.pill, paddingHorizontal: 10, paddingVertical: 4, alignSelf: 'flex-start' }}>
      <Ionicons name={ic} size={14} color={fg} />
      <Text style={{ color: fg, fontWeight: '700', fontSize: 12.5 }}>{label}</Text>
    </View>
  );
}

const AV_COLOURS = ['#C2410C', '#0E7490', '#7C3AED', '#15803D', '#BE185D', '#1D4ED8', '#A16207', '#0F766E'];
export function Avatar({ name, id, size = 44 }: { name: string; id: string; size?: number }) {
  const initials = name.split(/\s+/).map((w) => w[0] ?? '').join('').slice(0, 2).toUpperCase();
  let h = 0; for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return (
    <View accessible={false} style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: AV_COLOURS[h % AV_COLOURS.length], alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ color: '#fff', fontWeight: '800', fontSize: size * 0.36 }}>{initials}</Text>
    </View>
  );
}

export function Row({ title, subtitle, left, right, onPress, label }:
  { title: string; subtitle?: string; left?: React.ReactNode; right?: React.ReactNode; onPress?: () => void; label?: string }) {
  const t = useTheme();
  return (
    <Pressable
      accessibilityRole={onPress ? 'button' : undefined}
      accessibilityLabel={label ?? [title, subtitle].filter(Boolean).join(', ')}
      onPress={onPress}
      style={({ pressed }) => [{ flexDirection: 'row', alignItems: 'center', gap: space.m, paddingVertical: 10, minHeight: 64, opacity: pressed ? 0.7 : 1 }]}
    >
      {left}
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text style={{ fontSize: 16, fontWeight: '700', color: t.ink }} numberOfLines={1}>{title}</Text>
        {subtitle ? <Text style={{ fontSize: 13.5, color: t.muted }} numberOfLines={2}>{subtitle}</Text> : null}
      </View>
      {right}
    </Pressable>
  );
}

export function Empty({ title, body, icon = 'albums-outline' }: { title: string; body: string; icon?: IconName }) {
  const t = useTheme();
  return (
    <View style={{ alignItems: 'center', padding: space.xl, gap: 6 }}>
      <Ionicons name={icon} size={32} color={t.muted} />
      <Text style={{ fontWeight: '700', fontSize: 17, color: t.ink, textAlign: 'center' }}>{title}</Text>
      <Text style={{ color: t.muted, textAlign: 'center', fontSize: 15 }}>{body}</Text>
    </View>
  );
}

export function Notice({ kind = 'info', children }: { kind?: 'info' | 'warn'; children: React.ReactNode }) {
  const t = useTheme();
  return (
    <View style={{ flexDirection: 'row', gap: 10, padding: 12, borderRadius: radius.m, backgroundColor: kind === 'warn' ? t.warnSoft : t.surface, borderWidth: kind === 'warn' ? 0 : 1, borderColor: t.line }}>
      <Ionicons name={kind === 'warn' ? 'warning-outline' : 'information-circle-outline'} size={20} color={kind === 'warn' ? t.warn : t.muted} />
      <Text style={{ flex: 1, color: t.ink, fontSize: 14.5, lineHeight: 20 }}>{children}</Text>
    </View>
  );
}

export function Loading({ label = 'Loading…' }: { label?: string }) {
  const t = useTheme();
  return (
    <View style={{ padding: space.xl, alignItems: 'center', gap: 8 }} accessibilityLiveRegion="polite">
      <ActivityIndicator color={t.brand} />
      <Text style={{ color: t.muted }}>{label}</Text>
    </View>
  );
}

export function Chip({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  const t = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={{ paddingHorizontal: 14, minHeight: 40, justifyContent: 'center', borderRadius: radius.pill, borderWidth: 1, borderColor: selected ? t.ink : t.line, backgroundColor: selected ? t.ink : t.bg }}
    >
      <Text style={{ color: selected ? t.onInk : t.ink, fontWeight: '600', fontSize: 14 }}>{label}</Text>
    </Pressable>
  );
}

export const fmtDate = (iso: string) =>
  new Date(iso.length === 10 ? `${iso}T12:00:00` : iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });

export const todayISO = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

const styles = StyleSheet.create({
  btn: { minHeight: touch, borderRadius: radius.m, paddingHorizontal: 18, flexDirection: 'row', gap: 8, alignItems: 'center', justifyContent: 'center' },
});
