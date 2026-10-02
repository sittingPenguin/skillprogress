import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Text, View } from 'react-native';
import { router, Stack, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../../lib/supabase';
import { useSession } from '../../lib/session';
import { CLIP_SELECT, firstAssessment, type Clip, type Moment, type RubricVersion } from '../../lib/types';
import { radius, space, useTheme } from '../../lib/theme';
import { ClipPlayer, type PlayerApi } from '../../components/ClipPlayer';
import { LevelList, MomentList } from '../../components/Feedback';
import { Button, Empty, fmtDate, H1, H2, Loading, Notice, P, Pill, Screen } from '../../components/ui';

export default function ClipScreen() {
  const t = useTheme();
  const { id, published } = useLocalSearchParams<{ id: string; published?: string }>();
  const { isStaff } = useSession();
  const player = useRef<PlayerApi | null>(null);
  const [clip, setClip] = useState<Clip | null | undefined>(undefined);
  const [rubric, setRubric] = useState<RubricVersion | null>(null);
  const [moments, setMoments] = useState<Moment[]>([]);

  const load = useCallback(async () => {
    {
      const { data } = await supabase.from('clips').select(CLIP_SELECT).eq('id', id).maybeSingle();
      const c = (data as unknown as Clip) ?? null;
      setClip(c);
      const a = c ? firstAssessment(c) : null;
      if (!c) return;
      const [r, m] = await Promise.all([
        a?.rubric_version_id ? supabase.from('rubric_versions').select('id, skill_id, version, levels, criteria').eq('id', a.rubric_version_id).maybeSingle() : Promise.resolve({ data: null }),
        supabase.from('clip_moments').select('id, at_ms, body, author_id').eq('clip_id', c.id),
      ]);
      setRubric((r.data as RubricVersion | null) ?? null);
      setMoments((m.data ?? []) as Moment[]);
    }
  }, [id]);
  useEffect(() => { load(); }, [load]);

  if (clip === undefined) return <Screen><Loading /></Screen>;
  if (clip === null || !clip.storage_path) return <Screen><Empty icon="lock-closed-outline" title="Clip unavailable" body="It may not be published yet, or your access has changed." /></Screen>;
  const a = firstAssessment(clip);
  const isPublished = a?.status === 'published';

  return (
    <Screen onRefresh={load}>
      <Stack.Screen options={{ title: clip.skills?.name ?? 'Clip' }} />
      {published ? <Notice>Published. {clip.students?.display_name}’s family can now see this feedback.</Notice> : null}
      <View style={{ gap: 4 }}>
        <H1>{clip.students?.display_name} · {clip.skills?.name}</H1>
        <P muted>Filmed {fmtDate(clip.recorded_on)}{clip.drill ? ` · ${clip.drill}` : ''}</P>
        {isStaff ? (clip.restricted ? <Pill kind="review" label="Needs review" /> : isPublished ? <Pill kind="published" label="Shared with family" /> : <Pill kind="draft" label="Draft · staff only" />) : null}
      </View>
      {isStaff && clip.restricted ? <Notice kind="warn">Other pupils are visible in this clip. It can’t be shared with the family until it’s reviewed.</Notice> : null}
      <ClipPlayer storagePath={clip.storage_path} controller={player} />
      {isStaff ? <Button label={a ? 'Edit assessment' : 'Assess this clip'} icon="create-outline" onPress={() => router.push({ pathname: '/assess/[id]', params: { id: clip.id } })} /> : null}

      <Button label="Compare with another session" icon="git-compare-outline" kind="secondary"
        onPress={() => router.push({ pathname: '/compare/[student]', params: { student: clip.student_id, skill: clip.skill_id } })} />
      {a?.feedback ? <View style={{ gap: 6 }}><H2>Coach feedback</H2><P>{a.feedback}</P></View> : !isStaff ? null : <P muted>Not assessed yet.</P>}
      {a?.strengths || a?.to_improve ? (
        <View style={{ flexDirection: 'row', gap: space.m, flexWrap: 'wrap' }}>
          {a.strengths ? <Box title="Going well" body={a.strengths} /> : null}
          {a.to_improve ? <Box title="Working on" body={a.to_improve} /> : null}
        </View>
      ) : null}
      {moments.length ? <View style={{ gap: 4 }}><H2>Moments</H2><P muted>Tap a time to jump to it.</P><MomentList moments={moments} onSeek={(s) => player.current?.seek(s)} /></View> : null}
      {rubric && a?.scores && Object.keys(a.scores).length ? (
        <View style={{ gap: 8 }}>
          <H2>Skill check</H2>
          <LevelList rubric={rubric} scores={a.scores} />
          <P muted>Rubric version {rubric.version}. Levels describe this session, not a ranking against other pupils.</P>
        </View>
      ) : null}
      {a?.next_goal ? (
        <View style={{ flexDirection: 'row', gap: 8, backgroundColor: t.brandSoft, padding: 12, borderRadius: radius.m }}>
          <Ionicons name="flag-outline" size={18} color={t.brand} />
          <Text style={{ color: t.ink, flex: 1, fontSize: 15 }}><Text style={{ fontWeight: '700', color: t.brand }}>Practise next: </Text>{a.next_goal}</Text>
        </View>
      ) : null}
    </Screen>
  );
}

function Box({ title, body }: { title: string; body: string }) {
  const t = useTheme();
  return (
    <View style={{ flexGrow: 1, flexBasis: 220, borderWidth: 1, borderColor: t.line, borderRadius: radius.m, padding: 12, gap: 4 }}>
      <Text style={{ fontWeight: '700', color: t.muted, fontSize: 12.5, letterSpacing: 0.5, textTransform: 'uppercase' }}>{title}</Text>
      <Text style={{ color: t.ink, fontSize: 15 }}>{body}</Text>
    </View>
  );
}
