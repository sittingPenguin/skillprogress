import React, { useCallback, useState } from 'react';
import { View } from 'react-native';
import { router, Stack, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { supabase } from '../../lib/supabase';
import { useSession } from '../../lib/session';
import { firstAssessment, type Clip, type Student } from '../../lib/types';
import { space, useTheme } from '../../lib/theme';
import { Avatar, Button, Empty, fmtDate, H1, H2, Loading, Notice, P, Pill, Row, Screen } from '../../components/ui';

export default function PupilProfile() {
  const t = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { isStaff } = useSession();
  const [pupil, setPupil] = useState<Student | null>(null);
  const [clips, setClips] = useState<Clip[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [p, c] = await Promise.all([
      supabase.from('students').select('id, school_id, display_name, year_group').eq('id', id).maybeSingle(),
      supabase.from('clips').select('id, student_id, skill_id, recorded_on, uploaded_at, upload_status, storage_path, drill, restricted, skills(name), students(display_name), assessments(id, status, feedback, next_goal, published_at)')
        .eq('student_id', id).is('deleted_at', null).order('recorded_on', { ascending: false }),
    ]);
    if (p.error || c.error) setError('Couldn’t load this pupil. Check your connection.');
    setPupil((p.data as Student | null) ?? null);
    setClips((c.data ?? []) as unknown as Clip[]);
  }, [id]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  if (!pupil && clips === null) return <Screen><Loading /></Screen>;
  if (!pupil) return <Screen><Empty icon="lock-closed-outline" title="Pupil unavailable" body="This pupil isn’t in your classes, or your access has changed." /></Screen>;

  return (
    <Screen>
      <Stack.Screen options={{ title: pupil.display_name }} />
      <View style={{ flexDirection: 'row', gap: space.l, alignItems: 'center' }}>
        <Avatar name={pupil.display_name} id={pupil.id} size={72} />
        <View style={{ flex: 1, gap: 2 }}>
          <H1>{pupil.display_name}</H1>
          <P muted>{[pupil.year_group, `${clips?.length ?? 0} clips`].filter(Boolean).join(' · ')}</P>
        </View>
      </View>
      {isStaff ? <Button label="New clip for this pupil" icon="videocam-outline" onPress={() => router.push({ pathname: '/new', params: { student: pupil.id } })} /> : null}
      {error ? <Notice kind="warn">{error}</Notice> : null}
      <H2>Clips</H2>
      {clips && clips.length === 0 ? <Empty icon="videocam-outline" title="No clips yet" body={isStaff ? 'Record the first clip to start this pupil’s timeline.' : 'Clips appear once the coach publishes them.'} /> : null}
      {(clips ?? []).map((c) => {
        const a = firstAssessment(c);
        const status = c.upload_status !== 'ready' ? <Pill kind={c.upload_status === 'failed' ? 'failed' : 'uploading'} label={c.upload_status === 'failed' ? 'Upload failed' : 'Uploading'} />
          : c.restricted ? <Pill kind="review" label="Needs review" />
          : a?.status === 'published' ? <Pill kind="published" label="Shared with family" />
          : <Pill kind="draft" label="Not assessed yet" />;
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
