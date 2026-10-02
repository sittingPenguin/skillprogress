// Pull-to-refresh that works everywhere: the native control on phones and tablets,
// and a touch gesture in the browser (which React Native's RefreshControl doesn't support).
import React, { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Platform, RefreshControl, Text, View, type GestureResponderEvent, type NativeScrollEvent, type NativeSyntheticEvent } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '../lib/theme';

const TRIGGER = 64;
const MAX = 96;

type TouchLike = { pageY?: number; touches?: { pageY: number }[] };
const yOf = (e: GestureResponderEvent) => {
  const n = e.nativeEvent as unknown as TouchLike;
  return n.touches?.[0]?.pageY ?? n.pageY ?? 0;
};

export function usePullToRefresh(onRefresh?: () => Promise<unknown> | void) {
  const t = useTheme();
  const [refreshing, setRefreshing] = useState(false);
  const [pull, setPull] = useState(0);
  const scrollY = useRef(0);
  const startY = useRef<number | null>(null);

  const run = useCallback(async () => {
    if (!onRefresh) return;
    setRefreshing(true);
    try { await onRefresh(); } finally { setRefreshing(false); setPull(0); }
  }, [onRefresh]);

  if (!onRefresh) return { scrollProps: {}, header: null };

  if (Platform.OS !== 'web') {
    return {
      scrollProps: { refreshControl: <RefreshControl refreshing={refreshing} onRefresh={run} tintColor={t.brand} colors={[t.brand]} /> },
      header: null,
    };
  }

  const scrollProps = {
    scrollEventThrottle: 16,
    onScroll: (e: NativeSyntheticEvent<NativeScrollEvent>) => { scrollY.current = e.nativeEvent.contentOffset.y; },
    onTouchStart: (e: GestureResponderEvent) => { startY.current = scrollY.current <= 0 && !refreshing ? yOf(e) : null; },
    onTouchMove: (e: GestureResponderEvent) => {
      if (startY.current == null) return;
      const d = yOf(e) - startY.current;
      setPull(d > 0 ? Math.min(MAX, d * 0.5) : 0);
    },
    onTouchEnd: () => {
      if (startY.current == null) return;
      startY.current = null;
      if (pull >= TRIGGER) run(); else setPull(0);
    },
  };

  const height = refreshing ? 52 : pull;
  const header = height > 0 ? (
    <View accessibilityLiveRegion="polite" style={{ height, alignItems: 'center', justifyContent: 'center', overflow: 'hidden', flexDirection: 'row', gap: 8 }}>
      {refreshing ? <ActivityIndicator color={t.brand} /> : (
        <Ionicons name="arrow-down" size={18} color={t.muted} style={{ transform: [{ rotate: pull >= TRIGGER ? '180deg' : '0deg' }] }} />
      )}
      <Text style={{ color: t.muted, fontSize: 14 }}>{refreshing ? 'Refreshing…' : pull >= TRIGGER ? 'Release to refresh' : 'Pull to refresh'}</Text>
    </View>
  ) : null;

  return { scrollProps, header };
}
