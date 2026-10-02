import React, { useCallback, useState } from 'react';
import { Text, View } from 'react-native';
import { router, Stack, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { supabase } from '../../lib/supabase';
import { useSession } from '../../lib/session';
import { CLIP_SELECT, firstAssessment, type Clip, type Goal, type GoalStatus, type Student } from '../../lib/types';
import { space, useTheme } from '../../lib/theme';
import { Avatar, Button, Empty, fmtDate, H1, H2, Loading, Notice, P, Pill, Row, Screen, todayISO } from '../../components/ui';

export default function PupilProfile() {
  const t = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { isStaff } = useSession();
  const [pupil, setPupil] = useState<Student | null>(null);
  const [clips, setClips] = useState<Clip[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [goals, setGoals] = useState<Goal[]>([]);

  const load = useCallback(async () => {
    const [p, c, g] = await Promise.all([
      supabase.from('students').select('id, school_id, display_name, year_group').eq('id', id).maybeSingle(),
      supabase.from('clips').select(CLIP_SELECT).eq('student_id', id).is('deleted_at', null).order('recorded_on', { ascending: false }),
      supabase.from('goals').select('id, student_id, skill_id, text, status, notes, clip_id, published, set_on, closed_on, skills(name)').eq('student_id', id).order('set_on', { ascending: false }),
    ]);
    setGoals(((g.data ?? []) as unknown as Goal[]));
    if (p.error || c.error) setError('Couldn’t load this pupil. Check your connection.');
    setPupil((p.data as Student | null) ?? null);
    setClips((c.data ?? []) as unknown as Clip[]);
  }, [id]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  if (!pupil && clips === null) return <Screen><Loading /></Screen>;
  if (!pupil) return <Screen><Empty icon="lock-closed-outline" title="Pupil unavailable" body="This pupil isn’t in your classes, or your access has changed." /></Screen>;

  return (
    <Screen onRefresh={load}>
      <Stack.Screen options={{ title: pupil.display_name }} />
      <View style={{ flexDirection: 'row', gap: space.l, alignItems: 'center' }}>
        <Avatar name={pupil.display_name} id={pupil.id} size={72} />
        <View style={{ flex: 1, gap: 2 }}>
          <H1>{pupil.display_name}</H1>
          <P muted>{[pupil.year_group, `${clips?.length ?? 0} clips`].filter(Boolean).join(' · ')}</P>
        </View>
      </View>
      {isStaff ? <Button label="New clip for this pupil" icon="videocam-outline" onPress={() => router.push({ pathname: '/new', params: { student: pupil.id } })} /> : null}
      {(clips ?? []).filter((c) => c.upload_status === 'ready').length >= 2
        ? <Button label="Compare clips" icon="git-compare-outline" kind={isStaff ? 'secondary' : 'primary'} onPress={() => router.push({ pathname: '/compare/[student]', params: { student: pupil.id } })} />
        : null}
      {error ? <Notice kind="warn">{error}</Notice> : null}
      <H2>Goals</H2>
      {goals.length === 0 ? <P muted>{isStaff ? 'Goals appear here when you publish feedback with a goal.' : 'Goals appear here when the coach sets one.'}</P> : null}
      {goals.map((g) => <GoalRow key={g.id} goal={g} canEdit={isStaff} onChange={load} />)}

      <H2>Clips</H2>
      {clips && clips.length === 0 ? <Empty icon="videocam-outline" title="No clips yet" body={isStaff ? 'Record the first clip to start this pupil’s timeline.' : 'Clips appear once the coach publishes them.'} /> : null}
      {(clips ?? []).map((c) => {
        const a = firstAssessment(c);
        const status = c.upload_status !== 'ready' ? <Pill kind={c.upload_status === 'failed' ? 'failed' : 'uploading'} label={c.upload_status === 'failed' ? 'Upload failed' : 'Uploading'} />
          : c.restricted ? <Pill kind="review" label="Needs review" />
          : a?.status === 'published' ? <Pill kind="published" label="Shared with family" />
          : <Pill kind="draft" label={a ? 'Draft · staff only' : 'Not assessed yet'} />;
        return (
          <View key={c.id} style={{ borderBottomWidth: 1, borderColor: t.line, paddingBottom: 6, gap: 4 }}>
            <Row title={c.skills?.name ?? 'Clip'} subtitle={`Filmed ${fmtDate(c.recorded_on)}${c.drill ? ` · ${c.drill}` : ''}`}
              onPress={c.upload_status === 'ready' ? () => router.push({ pathname: '/clip/[id]', params: { id: c.id } }) : undefined} />
            {status}
          </View>
        );
      })}
    </Screen>
  );
}

const GOAL_LABEL: Record<GoalStatus, string> = { in_progress: 'In progress', achieved: 'Achieved', replaced: 'Replaced' };

function GoalRow({ goal, canEdit, onChange }: { goal: Goal; canEdit: boolean; onChange: () => void }) {
  const t = useTheme();
  const [busy, setBusy] = useState(false);
  async function setStatus(status: GoalStatus) {
    setBusy(true);
    await supabase.from('goals').update({ status, closed_on: status === 'in_progress' ? null : todayISO() }).eq('id', goal.id);
    setBusy(false); onChange();
  }
  return (
    <View style={{ borderWidth: 1, borderColor: t.line, borderRadius: 14, padding: 12, gap: 6, opacity: goal.status === 'replaced' ? 0.7 : 1 }}>
      <Text style={{ color: t.ink, fontWeight: '700', fontSize: 15 }}>{goal.text}</Text>
      <Text style={{ color: t.muted, fontSize: 13.5 }}>
        {[goal.skills?.name, `set ${fmtDate(goal.set_on)}`, goal.closed_on ? `${goal.status === 'achieved' ? 'achieved' : 'closed'} ${fmtDate(goal.closed_on)}` : null].filter(Boolean).join(' · ')}
      </Text>
      <Pill kind={goal.status === 'achieved' ? 'published' : goal.status === 'replaced' ? 'private' : 'info'} label={GOAL_LABEL[goal.status]} />
      {canEdit ? (
        <View style={{ flexDirection: 'row', gap: 8, flexWrap: 'wrap' }}>
          {goal.status !== 'achieved' ? <Button label="Mark achieved" kind="secondary" disabled={busy} onPress={() => setStatus('achieved')} /> : null}
          {goal.status === 'in_progress' ? <Button label="Replace" kind="secondary" disabled={busy} onPress={() => setStatus('replaced')} /> : null}
          {goal.status !== 'in_progress' ? <Button label="Reopen" kind="secondary" disabled={busy} onPress={() => setStatus('in_progress')} /> : null}
        </View>
      ) : null}
    </View>
  );
}
