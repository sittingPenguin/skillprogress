import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { FlatList, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../../lib/supabase';
import { useSession } from '../../lib/session';
import { CLIP_SELECT, firstAssessment, type Clip, type Group, type Student } from '../../lib/types';
import { radius, space, useTheme } from '../../lib/theme';
import { Avatar, Chip, Empty, fmtDate, Loading, Notice, P, Pill, Row } from '../../components/ui';

export default function Home() {
  const { isStaff } = useSession();
  return isStaff ? <Pupils /> : <FamilyUpdates />;
}


function Pupils() {
  const t = useTheme();
  const { active } = useSession();
  const [students, setStudents] = useState<Student[] | null>(null);
  const [groups, setGroups] = useState<Group[]>([]);
  const [groupId, setGroupId] = useState<string>('all');
  const [q, setQ] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    if (!active) return;
    setError(null);
    const [s, g] = await Promise.all([
      supabase.from('students').select('id, school_id, display_name, year_group').eq('school_id', active.school_id).is('archived_at', null).order('display_name'),
      supabase.from('groups').select('id, name, kind, group_members(student_id)').eq('school_id', active.school_id).order('name'),
    ]);
    if (s.error) { setError('Couldn’t load pupils. Pull down to try again.'); return; }
    setStudents((s.data ?? []) as Student[]);
    setGroups((g.data ?? []) as unknown as Group[]);
  }, [active]);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const shown = useMemo(() => {
    if (!students) return [];
    const g = groups.find((x) => x.id === groupId);
    const inGroup = g ? new Set(g.group_members.map((m) => m.student_id)) : null;
    const needle = q.trim().toLowerCase();
    return students.filter((s) => (!inGroup || inGroup.has(s.id)) && (!needle || s.display_name.toLowerCase().includes(needle)));
  }, [students, groups, groupId, q]);

  return (
    <FlatList
      style={{ backgroundColor: t.bg }}
      contentContainerStyle={{ padding: space.l, gap: 2, maxWidth: 720, width: '100%', alignSelf: 'center' }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
      ListHeaderComponent={
        <View style={{ gap: space.m, marginBottom: space.s }}>
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
            <Chip label={`Everyone (${students?.length ?? 0})`} selected={groupId === 'all'} onPress={() => setGroupId('all')} />
            {groups.map((g) => <Chip key={g.id} label={`${g.name} (${g.group_members.length})`} selected={groupId === g.id} onPress={() => setGroupId(g.id)} />)}
          </ScrollView>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: t.surface, borderRadius: radius.m, paddingHorizontal: 12 }}>
            <Ionicons name="search" size={18} color={t.muted} />
            <TextInput value={q} onChangeText={setQ} placeholder="Search pupils" placeholderTextColor={t.muted} accessibilityLabel="Search pupils"
              style={{ flex: 1, minHeight: 46, fontSize: 16, color: t.ink }} />
          </View>
          {error ? <Notice kind="warn">{error}</Notice> : null}
        </View>
      }
      data={shown}
      keyExtractor={(s) => s.id}
      renderItem={({ item }) => (
        <Row title={item.display_name} subtitle={item.year_group ?? undefined} left={<Avatar name={item.display_name} id={item.id} />}
          right={<Ionicons name="chevron-forward" size={18} color={t.muted} />}
          onPress={() => router.push({ pathname: '/pupil/[id]', params: { id: item.id } })} />
      )}
      ListEmptyComponent={students === null ? <Loading /> :
        <Empty icon="people-outline" title={q ? 'No pupils match' : 'No pupils yet'} body={q ? 'Try a different name.' : 'Pupils appear here once your school admin adds them to a class you coach.'} />}
    />
  );
}

function FamilyUpdates() {
  const t = useTheme();
  const [clips, setClips] = useState<Clip[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    setError(null);
    const { data, error: e } = await supabase.from('clips').select(CLIP_SELECT).order('recorded_on', { ascending: false }).limit(50);
    if (e) { setError('Couldn’t load updates. Pull down to try again.'); return; }
    setClips((data ?? []) as unknown as Clip[]);
  }, []);
  useEffect(() => { load(); }, [load]);

  return (
    <FlatList
      style={{ backgroundColor: t.bg }}
      contentContainerStyle={{ padding: space.l, gap: space.m, maxWidth: 720, width: '100%', alignSelf: 'center' }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={async () => { setRefreshing(true); await load(); setRefreshing(false); }} />}
      ListHeaderComponent={<View style={{ gap: space.m }}>
        <Notice>Only you and your child’s school can see these updates. They are never public.</Notice>
        {error ? <Notice kind="warn">{error}</Notice> : null}
      </View>}
      data={clips ?? []}
      keyExtractor={(c) => c.id}
      renderItem={({ item }) => {
        const a = firstAssessment(item);
        return (
          <View style={{ borderWidth: 1, borderColor: t.line, borderRadius: radius.l, padding: space.l, gap: 8 }}>
            <Row title={`${item.students?.display_name ?? ''} · ${item.skills?.name ?? ''}`} subtitle={`Filmed ${fmtDate(item.recorded_on)}`}
              left={<Avatar name={item.students?.display_name ?? '?'} id={item.student_id} />}
              onPress={() => router.push({ pathname: '/clip/[id]', params: { id: item.id } })} />
            {a?.feedback ? <P>{a.feedback}</P> : null}
            {a?.next_goal ? <View style={{ flexDirection: 'row', gap: 8, backgroundColor: t.brandSoft, padding: 10, borderRadius: radius.m }}>
              <Ionicons name="flag-outline" size={18} color={t.brand} />
              <Text style={{ color: t.ink, flex: 1 }}><Text style={{ fontWeight: '700', color: t.brand }}>Next session: </Text>{a.next_goal}</Text>
            </View> : null}
            <Pill kind="private" label="Family only" />
          </View>
        );
      }}
      ListEmptyComponent={clips === null ? <Loading /> : <Empty icon="sparkles-outline" title="No updates yet" body="When your child’s coach shares feedback, it appears here." />}
    />
  );
}
