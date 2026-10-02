import React, { useEffect, useState } from 'react';
import { Text, View } from 'react-native';
import { Stack, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../../lib/supabase';
import { useSession } from '../../lib/session';
import { firstAssessment, type Clip } from '../../lib/types';
import { radius, useTheme } from '../../lib/theme';
import { ClipPlayer } from '../../components/ClipPlayer';
import { Empty, fmtDate, H1, Loading, Notice, P, Pill, Screen } from '../../components/ui';

export default function ClipScreen() {
  const t = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { isStaff } = useSession();
  const [clip, setClip] = useState<Clip | null | undefined>(undefined);

  useEffect(() => {
    supabase.from('clips')
      .select('id, student_id, skill_id, recorded_on, uploaded_at, upload_status, storage_path, drill, restricted, skills(name), students(display_name), assessments(id, status, feedback, next_goal, published_at)')
      .eq('id', id).maybeSingle()
      .then(({ data }) => setClip((data as unknown as Clip) ?? null));
  }, [id]);

  if (clip === undefined) return <Screen><Loading /></Screen>;
  if (clip === null || !clip.storage_path) return <Screen><Empty icon="lock-closed-outline" title="Clip unavailable" body="It may not be published yet, or your access has changed." /></Screen>;
  const a = firstAssessment(clip);

  return (
    <Screen>
      <Stack.Screen options={{ title: clip.skills?.name ?? 'Clip' }} />
      <View style={{ gap: 4 }}>
        <H1>{clip.students?.display_name} · {clip.skills?.name}</H1>
        <P muted>Filmed {fmtDate(clip.recorded_on)} · uploaded {fmtDate(clip.uploaded_at)}{clip.drill ? ` · ${clip.drill}` : ''}</P>
      </View>
      {isStaff && clip.restricted ? <Notice kind="warn">Other pupils are visible in this clip. It can’t be shared with the family until it’s reviewed.</Notice> : null}
      <ClipPlayer storagePath={clip.storage_path} />
      {isStaff ? (a?.status === 'published' ? <Pill kind="published" label="Shared with family" /> : <Pill kind="draft" label="Draft · staff only" />) : null}
      {a?.feedback ? <P>{a.feedback}</P> : isStaff ? <P muted>Assessment and feedback arrive in the next app update.</P> : null}
      {a?.next_goal ? (
        <View style={{ flexDirection: 'row', gap: 8, backgroundColor: t.brandSoft, padding: 12, borderRadius: radius.m }}>
          <Ionicons name="flag-outline" size={18} color={t.brand} />
          <Text style={{ color: t.ink, flex: 1, fontSize: 15 }}><Text style={{ fontWeight: '700', color: t.brand }}>Next session: </Text>{a.next_goal}</Text>
        </View>
      ) : null}
    </Screen>
  );
}
