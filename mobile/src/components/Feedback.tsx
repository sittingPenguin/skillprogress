// Shows rubric levels as filled boxes plus words, so meaning never relies on colour alone.
import React from 'react';
import { Pressable, Text, View } from 'react-native';
import type { Moment, RubricVersion } from '../lib/types';
import { radius, useTheme } from '../lib/theme';

export function LevelList({ rubric, scores }: { rubric: RubricVersion; scores: Record<string, number> }) {
  const t = useTheme();
  const rows = rubric.criteria.filter((c) => scores[c.key]);
  if (!rows.length) return null;
  return (
    <View style={{ gap: 8 }}>
      {rows.map((c) => {
        const l = scores[c.key];
        return (
          <View key={c.key} accessible accessibilityLabel={`${c.name}: ${rubric.levels[l - 1]}, level ${l} of ${rubric.levels.length}. ${c.descriptors[l - 1] ?? ''}`}
            style={{ borderWidth: 1, borderColor: t.line, borderRadius: radius.m, padding: 10, gap: 4 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <Text style={{ fontWeight: '700', color: t.ink, fontSize: 15 }}>{c.name}</Text>
              <View style={{ flexDirection: 'row', gap: 3 }}>
                {rubric.levels.map((_, i) => (
                  <View key={i} style={{ width: 10, height: 10, borderRadius: 2, borderWidth: 1.5, borderColor: t.brand, backgroundColor: i < l ? t.brand : 'transparent' }} />
                ))}
              </View>
              <Text style={{ color: t.brand, fontWeight: '700', fontSize: 14 }}>{rubric.levels[l - 1]} ({l}/{rubric.levels.length})</Text>
            </View>
            <Text style={{ color: t.muted, fontSize: 14 }}>{c.descriptors[l - 1]}</Text>
          </View>
        );
      })}
    </View>
  );
}

export const fmtMs = (ms: number) => {
  const s = ms / 1000, m = Math.floor(s / 60);
  return `${m}:${(s - m * 60).toFixed(1).padStart(4, '0')}`;
};

export function MomentList({ moments, onSeek, onDelete }: { moments: Moment[]; onSeek?: (sec: number) => void; onDelete?: (m: Moment) => void }) {
  const t = useTheme();
  if (!moments.length) return null;
  return (
    <View style={{ gap: 2 }}>
      {[...moments].sort((a, b) => a.at_ms - b.at_ms).map((m) => (
        <View key={m.id} style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
          <Pressable accessibilityRole="button" accessibilityLabel={`At ${fmtMs(m.at_ms)}: ${m.body}. Jump to this moment.`}
            onPress={() => onSeek?.(m.at_ms / 1000)} style={{ flex: 1, flexDirection: 'row', gap: 10, paddingVertical: 10, minHeight: 44 }}>
            <Text style={{ color: t.accent, fontWeight: '700', fontVariant: ['tabular-nums'] }}>{fmtMs(m.at_ms)}</Text>
            <Text style={{ color: t.ink, flex: 1, fontSize: 15 }}>{m.body}</Text>
          </Pressable>
          {onDelete ? (
            <Pressable accessibilityRole="button" accessibilityLabel={`Remove comment at ${fmtMs(m.at_ms)}`} onPress={() => onDelete(m)}
              style={{ minWidth: 44, minHeight: 44, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={{ color: t.muted, fontSize: 13 }}>Remove</Text>
            </Pressable>
          ) : null}
        </View>
      ))}
    </View>
  );
}
