import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Linking, Platform, ScrollView, View } from 'react-native';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';
import { supabase } from '../../lib/supabase';
import { useSession } from '../../lib/session';
import { clipDraft, type DraftVideo } from '../../lib/clipDraft';
import { uploadQueue } from '../../lib/uploads';
import { uploadFromBrowser } from '../../lib/webUpload';
import type { Skill, Student } from '../../lib/types';
import { space } from '../../lib/theme';
import { Button, Chip, Field, H2, Loading, Notice, P, Screen, todayISO } from '../../components/ui';

const MAX_SECONDS = 60;

export default function NewClip() {
  const { active } = useSession();
  const params = useLocalSearchParams<{ student?: string }>();
  const [students, setStudents] = useState<Student[] | null>(null);
  const [skills, setSkills] = useState<Skill[]>([]);
  const [studentId, setStudentId] = useState<string | null>(null);
  const [skillId, setSkillId] = useState<string | null>(null);
  const [date, setDate] = useState(todayISO());
  const [drill, setDrill] = useState('');
  const [q, setQ] = useState('');
  const [video, setVideo] = useState<DraftVideo | null>(clipDraft.get());
  const [problem, setProblem] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  // Browser uploads keep one upload id across retries, so a retry never creates a second clip.
  const [webUploadId, setWebUploadId] = useState<string | undefined>(undefined);

  useEffect(() => clipDraft.subscribe(() => setVideo(clipDraft.get())), []);
  useEffect(() => { if (params.student) setStudentId(params.student); }, [params.student]);

  useFocusEffect(useCallback(() => {
    if (!active) return;
    supabase.from('students').select('id, school_id, display_name, year_group').eq('school_id', active.school_id).is('archived_at', null).order('display_name')
      .then(({ data }) => setStudents((data ?? []) as Student[]));
    supabase.from('skills').select('id, name, recording_tip, sports(name)').eq('school_id', active.school_id).order('name')
      .then(({ data }) => {
        const rows = (data ?? []) as unknown as Skill[];
        setSkills(rows);
        setSkillId((cur) => cur ?? rows[0]?.id ?? null);
      });
  }, [active]));

  const student = students?.find((s) => s.id === studentId) ?? null;
  const skill = skills.find((s) => s.id === skillId) ?? null;
  const matches = useMemo(() => (students ?? []).filter((s) => !q || s.display_name.toLowerCase().includes(q.toLowerCase())).slice(0, 12), [students, q]);
  const validDate = /^\d{4}-\d{2}-\d{2}$/.test(date) && date <= todayISO();

  async function pickFromLibrary() {
    setProblem(null);
    if (Platform.OS === 'web') {
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['videos'], allowsEditing: false });
      if (res.canceled || !res.assets[0]) return;
      const a = res.assets[0];
      const size = a.fileSize ?? a.file?.size ?? 0;
      if (size > 50 * 1024 * 1024) { setProblem(`That video is ${Math.round(size / 1048576)} MB, over the 50 MB limit. Film a shorter clip: 20–30 seconds is plenty for one skill.`); return; }
      clipDraft.set({ uri: a.uri, durationMs: a.duration ?? null, source: 'library', file: a.file ?? undefined, mimeType: a.mimeType ?? undefined });
      setWebUploadId(undefined);
      return;
    }
    const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) {
      setProblem(perm.canAskAgain ? 'SkillProgress needs access to your videos to upload a clip.' : 'Video access is turned off for SkillProgress. Turn it on in Settings, or record the clip in the app instead.');
      return;
    }
    const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['videos'], videoMaxDuration: MAX_SECONDS, allowsEditing: false });
    if (res.canceled || !res.assets[0]) return;
    const a = res.assets[0];
    if (a.duration && a.duration > MAX_SECONDS * 1000) { setProblem(`That clip is longer than ${MAX_SECONDS} seconds. Trim it in Photos first, or record a shorter one.`); return; }
    clipDraft.set({ uri: a.uri, durationMs: a.duration ?? null, source: 'library', file: a.file ?? undefined, mimeType: a.mimeType ?? undefined });
    setWebUploadId(undefined);
  }

  async function upload() {
    if (!student || !skill || !video) return;
    setBusy(true);
    setProblem(null);
    if (Platform.OS === 'web') {
      try {
        const blob = video.file ?? (await (await fetch(video.uri)).blob());
        const res = await uploadFromBrowser({
          file: blob, mimeType: video.mimeType ?? blob.type, studentId: student.id, skillId: skill.id,
          recordedOn: date, drill: drill.trim() || null, durationMs: video.durationMs, uploadId: webUploadId,
        });
        clipDraft.set(null); setDrill(''); setStudentId(null); setDate(todayISO()); setWebUploadId(undefined);
        router.push({ pathname: '/assess/[id]', params: { id: res.clipId } });
      } catch (e) {
        const id = (e as { uploadId?: string }).uploadId;
        if (id) setWebUploadId(id);
        setProblem('The upload didn’t finish. Check your connection and tap Upload clip again. It won’t create a duplicate.');
      } finally { setBusy(false); }
      return;
    }
    try {
      await uploadQueue.add({
        sourceUri: video.uri, durationMs: video.durationMs, studentId: student.id, studentName: student.display_name,
        skillId: skill.id, skillName: skill.name, recordedOn: date, drill: drill.trim() || null,
      });
      clipDraft.set(null); setDrill(''); setStudentId(null); setDate(todayISO());
      router.push('/uploads');
    } catch {
      setProblem('Couldn’t save the clip on this device. Check there is free storage and try again.');
    } finally { setBusy(false); }
  }

  if (!students) return <Screen><Loading /></Screen>;

  return (
    <Screen>
      <H2>1. Pupil</H2>
      {student ? (
        <View style={{ flexDirection: 'row', gap: space.s, alignItems: 'center', flexWrap: 'wrap' }}>
          <Chip label={student.display_name} selected onPress={() => setStudentId(null)} />
          <P muted>Tap to change</P>
        </View>
      ) : (
        <View style={{ gap: space.s }}>
          <Field label="Find a pupil" value={q} onChangeText={setQ} placeholder="Start typing a name" />
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
            {matches.map((s) => <Chip key={s.id} label={s.display_name} selected={false} onPress={() => { setStudentId(s.id); setQ(''); }} />)}
          </View>
        </View>
      )}

      <H2>2. Skill</H2>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
        {skills.map((s) => <Chip key={s.id} label={s.name} selected={s.id === skillId} onPress={() => setSkillId(s.id)} />)}
      </ScrollView>
      {skill?.recording_tip ? <Notice>Filming tip: {skill.recording_tip}. Matching angles make comparisons fair.</Notice> : null}

      <H2>3. Details</H2>
      <Field label="Filmed on" value={date} onChangeText={setDate} placeholder="YYYY-MM-DD" hint={validDate ? 'Kept separately from the upload date.' : 'Use YYYY-MM-DD, not in the future.'} />
      <Field label="Drill (optional)" value={drill} onChangeText={setDrill} placeholder="e.g. 5 shots from the top of the circle" maxLength={120} />

      <H2>4. Video</H2>
      {video ? (
        <View style={{ gap: space.s }}>
          <Notice>{video.source === 'camera' ? 'Clip recorded' : 'Clip chosen from your library'}{video.durationMs ? ` (${Math.round(video.durationMs / 1000)} s)` : ''}. It stays on this device until it has uploaded.</Notice>
          <Button label="Replace video" kind="secondary" onPress={() => clipDraft.set(null)} />
        </View>
      ) : (
        Platform.OS === 'web' ? (
          <View style={{ gap: space.s }}>
            <Button label="Film or choose a video" icon="videocam" onPress={pickFromLibrary} />
            <P muted>On an iPhone, tap “Take Video” to film straight away. Keep clips to 20–30 seconds.</P>
          </View>
        ) : (
          <View style={{ flexDirection: 'row', gap: space.m }}>
            <Button style={{ flex: 1 }} label="Record" icon="videocam" onPress={() => router.push('/record')} />
            <Button style={{ flex: 1 }} label="Choose" icon="images-outline" kind="secondary" onPress={pickFromLibrary} />
          </View>
        )
      )}
      {problem ? (
        <View style={{ gap: space.s }}>
          <Notice kind="warn">{problem}</Notice>
          {/Settings/.test(problem) ? <Button label="Open Settings" kind="secondary" onPress={() => Linking.openSettings()} /> : null}
        </View>
      ) : null}

      <Button label="Upload clip" icon="cloud-upload-outline" kind="accent" busy={busy} disabled={!student || !skill || !video || !validDate} onPress={upload} />
      <P muted>{Platform.OS === 'web' ? 'Keep this page open until the upload finishes. You’ll go straight to the assessment.' : 'Uploads continue in the background of the app and pick up where they left off if the Wi-Fi drops.'}</P>
    </Screen>
  );
}
