// Compare two clips of the same pupil and skill. Each clip has its own controls and slow motion.
// The clips rarely start at the same point in the movement, so the coach (or parent) marks the
// same moment in each — an alignment point — and "Play together" lines them up from there.
// Levels are compared only when both clips were assessed with the same rubric version.
import React, { useCallback, useMemo, useRef, useState } from 'react';
import { ScrollView, Text, useWindowDimensions, View } from 'react-native';
import { Stack, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../../lib/supabase';
import { CLIP_SELECT, firstAssessment, type Clip, type RubricVersion, type Skill } from '../../lib/types';
import { radius, space, useTheme } from '../../lib/theme';
import { ClipPlayer, type PlayerApi } from '../../components/ClipPlayer';
import { fmtMs, LevelList } from '../../components/Feedback';
import { Button, Chip, Empty, fmtDate, H2, Loading, Notice, P, Screen } from '../../components/ui';

export default function Compare() {
  const t = useTheme();
  const { student, skill: skillParam } = useLocalSearchParams<{ student: string; skill?: string }>();
  const { width } = useWindowDimensions();
  const wide = width >= 700;

  const [clips, setClips] = useState<Clip[] | null>(null);
  const [skills, setSkills] = useState<Skill[]>([]);
  const [rubrics, setRubrics] = useState<Record<string, RubricVersion>>({});
  const [skillId, setSkillId] = useState<string | null>(skillParam ?? null);
  const [aId, setAId] = useState<string | null>(null);
  const [bId, setBId] = useState<string | null>(null);
  const [align, setAlign] = useState<{ a: number | null; b: number | null }>({ a: null, b: null });
  const pa = useRef<PlayerApi | null>(null);
  const pb = useRef<PlayerApi | null>(null);

  const load = useCallback(async () => {
    const { data } = await supabase.from('clips').select(CLIP_SELECT).eq('student_id', student)
      .eq('upload_status', 'ready').is('deleted_at', null).order('recorded_on');
    const rows = ((data ?? []) as unknown as Clip[]).filter((c) => c.storage_path);
    setClips(rows);
    const skillIds = [...new Set(rows.map((c) => c.skill_id))];
    if (skillIds.length) {
      const s = await supabase.from('skills').select('id, name, recording_tip, sports(name)').in('id', skillIds);
      setSkills((s.data ?? []) as unknown as Skill[]);
    }
    const rvIds = [...new Set(rows.map((c) => firstAssessment(c)?.rubric_version_id).filter(Boolean))] as string[];
    if (rvIds.length) {
      const r = await supabase.from('rubric_versions').select('id, skill_id, version, levels, criteria').in('id', rvIds);
      setRubrics(Object.fromEntries(((r.data ?? []) as RubricVersion[]).map((x) => [x.id, x])));
    }
  }, [student]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  // Clips for the chosen skill, oldest first. Default: the two furthest apart in time.
  const skillClips = useMemo(() => {
    if (!clips) return [];
    const sid = skillId ?? clips[clips.length - 1]?.skill_id ?? null;
    return clips.filter((c) => c.skill_id === sid);
  }, [clips, skillId]);
  const a = skillClips.find((c) => c.id === aId) ?? skillClips[0] ?? null;
  const b = skillClips.find((c) => c.id === bId && c.id !== a?.id) ?? skillClips.filter((c) => c.id !== a?.id).slice(-1)[0] ?? null;

  const pick = (which: 'a' | 'b', id: string) => {
    if (which === 'a') setAId(id); else setBId(id);
    setAlign((x) => ({ ...x, [which]: null }));
  };
  const setPoint = (which: 'a' | 'b') => {
    const p = which === 'a' ? pa.current : pb.current;
    if (p) { p.pause(); setAlign((x) => ({ ...x, [which]: p.time() })); }
  };
  const playTogether = (rate: number) => {
    if (align.a == null || align.b == null) return;
    const lead = Math.min(1, align.a, align.b); // start a moment before the marked point
    pa.current?.seek(align.a - lead); pb.current?.seek(align.b - lead);
    pa.current?.play(rate); pb.current?.play(rate);
  };

  if (clips === null) return <Screen><Loading /></Screen>;
  const name = clips[0]?.students?.display_name ?? 'Pupil';
  const skillName = skills.find((s) => s.id === (skillId ?? a?.skill_id))?.name ?? a?.skills?.name ?? '';

  const column = (which: 'a' | 'b', c: Clip) => {
    const as = firstAssessment(c);
    const rv = as?.rubric_version_id ? rubrics[as.rubric_version_id] : undefined;
    const point = align[which];
    return (
      <View key={which} style={{ flex: 1, minWidth: 0, gap: space.s, borderWidth: wide ? 1 : 0, borderColor: t.line, borderRadius: radius.l, padding: wide ? space.m : 0 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <View style={{ width: 28, height: 28, borderRadius: 8, backgroundColor: t.ink, alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ color: t.onInk, fontWeight: '800' }}>{which.toUpperCase()}</Text>
          </View>
          <Text style={{ fontWeight: '800', fontSize: 17, color: t.ink }}>{fmtDate(c.recorded_on)}</Text>
        </View>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6 }}>
          {skillClips.map((x) => <Chip key={x.id} label={fmtDate(x.recorded_on)} selected={x.id === c.id} onPress={() => pick(which, x.id)} />)}
        </ScrollView>
        <ClipPlayer key={c.id} storagePath={c.storage_path!} controller={which === 'a' ? pa : pb} aspect={wide ? 4 / 5 : 1} />
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <Button label="Set alignment point" icon="git-commit-outline" kind="secondary" onPress={() => setPoint(which)} />
          <Text style={{ color: point == null ? t.muted : t.brand, fontWeight: '600' }}>{point == null ? 'Not set' : `Aligned at ${fmtMs(Math.round(point * 1000))}`}</Text>
        </View>
        {rv && as?.scores ? <LevelList rubric={rv} scores={as.scores} /> : <P muted>{as ? '' : 'Not assessed yet.'}</P>}
        {as?.feedback ? <P><Text style={{ fontWeight: '700' }}>Coach: </Text>{as.feedback}</P> : null}
        {c.drill ? <P muted>Drill: {c.drill}</P> : null}
      </View>
    );
  };

  return (
    <Screen onRefresh={load}>
      <Stack.Screen options={{ title: `Compare · ${name}` }} />
      {skills.length > 1 ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
          {skills.map((s) => <Chip key={s.id} label={s.name} selected={s.id === (skillId ?? a?.skill_id)} onPress={() => { setSkillId(s.id); setAId(null); setBId(null); setAlign({ a: null, b: null }); }} />)}
        </ScrollView>
      ) : null}

      {!a || !b ? (
        <Empty icon="git-compare-outline" title="Two clips needed" body={`${name} needs at least two ${skillName ? skillName.toLowerCase() : ''} clips from different sessions to compare.`} />
      ) : (
        <>
          <View style={{ flexDirection: wide ? 'row' : 'column', gap: space.l }}>
            {column('a', a)}
            {column('b', b)}
          </View>

          <View style={{ backgroundColor: t.surface, borderRadius: radius.l, padding: space.m, gap: space.s, borderWidth: 1, borderColor: t.line }}>
            <Text style={{ fontWeight: '700', color: t.ink, fontSize: 15 }}>Play together</Text>
            <P muted>
              {align.a == null || align.b == null
                ? 'The clips don’t start at the same point. Pause each one at the same moment, such as the ball leaving the hands, and tap “Set alignment point” on both.'
                : `Lined up: A at ${fmtMs(Math.round(align.a * 1000))}, B at ${fmtMs(Math.round(align.b * 1000))}. Both reach that moment together.`}
            </P>
            <View style={{ flexDirection: 'row', gap: space.s, flexWrap: 'wrap' }}>
              <Button style={{ flexGrow: 1 }} label="Play both" icon="play" disabled={align.a == null || align.b == null} onPress={() => playTogether(1)} />
              <Button style={{ flexGrow: 1 }} label="Both at 0.25×" kind="secondary" disabled={align.a == null || align.b == null} onPress={() => playTogether(0.25)} />
              <Button style={{ flexGrow: 1 }} label="Pause both" kind="secondary" onPress={() => { pa.current?.pause(); pb.current?.pause(); }} />
            </View>
          </View>

          <Changes a={a} b={b} rubrics={rubrics} />
          <P muted>Tip: filming the same drill from the same angle each time makes comparisons fair.</P>
        </>
      )}
    </Screen>
  );
}

function Changes({ a, b, rubrics }: { a: Clip; b: Clip; rubrics: Record<string, RubricVersion> }) {
  const t = useTheme();
  const [older, newer] = a.recorded_on <= b.recorded_on ? [a, b] : [b, a];
  const ao = firstAssessment(older), an = firstAssessment(newer);
  if (!ao?.rubric_version_id || !an?.rubric_version_id) {
    return <Notice>Changes appear here once both clips have been assessed.</Notice>;
  }
  if (ao.rubric_version_id !== an.rubric_version_id) {
    const v1 = rubrics[ao.rubric_version_id]?.version, v2 = rubrics[an.rubric_version_id]?.version;
    return <Notice>These clips were assessed with different rubric versions{v1 && v2 ? ` (v${v1} and v${v2})` : ''}, so their levels can’t be compared directly. Watch the clips and read the feedback instead.</Notice>;
  }
  const rv = rubrics[ao.rubric_version_id];
  if (!rv) return null;
  return (
    <View style={{ gap: space.s }}>
      <H2>What changed</H2>
      <P muted>From {fmtDate(older.recorded_on)} to {fmtDate(newer.recorded_on)}, same rubric (version {rv.version}).</P>
      {rv.criteria.map((cr) => {
        const x = ao.scores?.[cr.key], y = an.scores?.[cr.key];
        let label = 'Not assessed in both', icon: React.ComponentProps<typeof Ionicons>['name'] = 'remove', colour = t.muted;
        if (x && y) {
          const d = y - x;
          label = d > 0 ? `Up ${d} level${d > 1 ? 's' : ''}` : d < 0 ? `Down ${-d} level${d < -1 ? 's' : ''}` : 'Same level';
          icon = d > 0 ? 'arrow-up' : d < 0 ? 'arrow-down' : 'remove';
          colour = d > 0 ? t.ok : d < 0 ? t.warn : t.muted;
        }
        return (
          <View key={cr.key} accessible accessibilityLabel={`${cr.name}: ${x ? rv.levels[x - 1] : 'not assessed'} to ${y ? rv.levels[y - 1] : 'not assessed'}. ${label}.`}
            style={{ flexDirection: 'row', alignItems: 'center', gap: space.m, paddingVertical: 10, borderBottomWidth: 1, borderColor: t.line }}>
            <Text style={{ flex: 1, fontWeight: '600', color: t.ink, fontSize: 15 }}>{cr.name}</Text>
            <Text style={{ color: t.muted, fontSize: 14 }}>{x ? rv.levels[x - 1] : '–'} → {y ? rv.levels[y - 1] : '–'}</Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4, minWidth: 110, justifyContent: 'flex-end' }}>
              <Ionicons name={icon} size={16} color={colour} />
              <Text style={{ color: colour, fontWeight: '700', fontSize: 14 }}>{label}</Text>
            </View>
          </View>
        );
      })}
      <P muted>Each area is shown on its own. They’re never added up into one score.</P>
    </View>
  );
}
