// Coach assessment: rubric levels, comments pinned to moments, feedback, goal, private note,
// a flag for clips showing other pupils, and save-as-draft or publish to the family.
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, Switch, Text, TextInput, View } from 'react-native';
import { router, Stack, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../../lib/supabase';
import { useSession } from '../../lib/session';
import { CLIP_SELECT, firstAssessment, type Clip, type Moment, type RubricVersion } from '../../lib/types';
import { radius, space, touch, useTheme } from '../../lib/theme';
import { ClipPlayer, type PlayerApi } from '../../components/ClipPlayer';
import { fmtMs, MomentList } from '../../components/Feedback';
import { Button, Empty, Field, fmtDate, H2, Loading, Notice, P, Pill, Screen } from '../../components/ui';

export default function Assess() {
  const t = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { session, isStaff } = useSession();
  const player = useRef<PlayerApi | null>(null);

  const [clip, setClip] = useState<Clip | null | undefined>(undefined);
  const [rubric, setRubric] = useState<RubricVersion | null>(null);
  const [moments, setMoments] = useState<Moment[]>([]);
  const [noteId, setNoteId] = useState<string | null>(null);

  const [scores, setScores] = useState<Record<string, number>>({});
  const [feedback, setFeedback] = useState('');
  const [strengths, setStrengths] = useState('');
  const [toImprove, setToImprove] = useState('');
  const [nextGoal, setNextGoal] = useState('');
  const [note, setNote] = useState('');
  const [restricted, setRestricted] = useState(false);
  const [reason, setReason] = useState('');
  const [momentText, setMomentText] = useState('');

  const [busy, setBusy] = useState<'draft' | 'publish' | 'hide' | null>(null);
  const [message, setMessage] = useState<{ kind: 'info' | 'warn'; text: string } | null>(null);

  const load = useCallback(async () => {
    const { data } = await supabase.from('clips').select(CLIP_SELECT).eq('id', id).maybeSingle();
    const c = (data as unknown as Clip) ?? null;
    setClip(c);
    if (!c) return;
    const a = firstAssessment(c);
    const rq = a?.rubric_version_id
      ? supabase.from('rubric_versions').select('id, skill_id, version, levels, criteria').eq('id', a.rubric_version_id).maybeSingle()
      : supabase.from('rubric_versions').select('id, skill_id, version, levels, criteria').eq('skill_id', c.skill_id).not('published_at', 'is', null).order('version', { ascending: false }).limit(1).maybeSingle();
    const [r, m, n] = await Promise.all([
      rq,
      supabase.from('clip_moments').select('id, at_ms, body, author_id').eq('clip_id', c.id),
      supabase.from('coach_notes').select('id, body').eq('clip_id', c.id).order('created_at').limit(1),
    ]);
    setRubric((r.data as RubricVersion | null) ?? null);
    setMoments((m.data ?? []) as Moment[]);
    const nn = (n.data ?? [])[0] as { id: string; body: string } | undefined;
    setNoteId(nn?.id ?? null); setNote(nn?.body ?? '');
    setScores(a?.scores ?? {}); setFeedback(a?.feedback ?? ''); setStrengths(a?.strengths ?? '');
    setToImprove(a?.to_improve ?? ''); setNextGoal(a?.next_goal ?? '');
    setRestricted(c.restricted); setReason(c.restricted_reason ?? '');
  }, [id]);
  useEffect(() => { load(); }, [load]);

  if (!isStaff) return <Screen><Empty icon="lock-closed-outline" title="Staff only" body="Only coaches can assess clips." /></Screen>;
  if (clip === undefined) return <Screen><Loading /></Screen>;
  if (!clip || !clip.storage_path) return <Screen><Empty icon="lock-closed-outline" title="Clip unavailable" body="It may have been removed, or your access has changed." /></Screen>;
  const c = clip;
  const existing = firstAssessment(c);
  const published = existing?.status === 'published';

  async function addMoment() {
    const body = momentText.trim();
    if (!body) { setMessage({ kind: 'warn', text: 'Write a short comment first, then pin it.' }); return; }
    const at = Math.round((player.current?.time() ?? 0) * 1000);
    const { data, error } = await supabase.from('clip_moments')
      .insert({ school_id: c.school_id, clip_id: c.id, at_ms: at, body, author_id: session!.user.id })
      .select('id, at_ms, body, author_id').single();
    if (error) { setMessage({ kind: 'warn', text: 'Couldn’t save that comment. Check your connection.' }); return; }
    setMoments((ms) => [...ms, data as Moment]); setMomentText('');
    setMessage({ kind: 'info', text: `Comment pinned at ${fmtMs(at)}.` });
  }

  async function removeMoment(m: Moment) {
    const { error } = await supabase.from('clip_moments').delete().eq('id', m.id);
    if (!error) setMoments((ms) => ms.filter((x) => x.id !== m.id));
  }

  async function save(mode: 'draft' | 'publish' | 'hide') {
    if (!rubric) return;
    setMessage(null);
    if (mode === 'publish') {
      if (restricted) { setMessage({ kind: 'warn', text: 'This clip is flagged because other pupils are visible. Review it and clear the flag before publishing.' }); return; }
      if (!feedback.trim() || !Object.keys(scores).length) { setMessage({ kind: 'warn', text: 'Add overall feedback and at least one rubric level before publishing.' }); return; }
    }
    setBusy(mode);
    try {
      // 1. Flag for other pupils in shot
      if (restricted !== c.restricted || (reason || null) !== (c.restricted_reason ?? null)) {
        const r = await supabase.from('clips').update({ restricted, restricted_reason: restricted ? reason.trim() || 'Other pupils visible' : null }).eq('id', c.id);
        if (r.error) throw r.error;
      }
      // 2. Assessment
      const status = mode === 'publish' ? 'published' : mode === 'hide' ? 'draft' : existing?.status ?? 'draft';
      const fields = {
        scores, feedback: feedback.trim() || null, strengths: strengths.trim() || null,
        to_improve: toImprove.trim() || null, next_goal: nextGoal.trim() || null, status,
      };
      const res = existing
        ? await supabase.from('assessments').update(fields).eq('id', existing.id)
        : await supabase.from('assessments').insert({ ...fields, school_id: c.school_id, clip_id: c.id, rubric_version_id: rubric.id, author_id: session!.user.id });
      if (res.error) throw res.error;
      // 3. Private note (staff only)
      const body = note.trim();
      if (body && noteId) await supabase.from('coach_notes').update({ body }).eq('id', noteId);
      else if (body) await supabase.from('coach_notes').insert({ school_id: c.school_id, clip_id: c.id, body, author_id: session!.user.id });
      else if (noteId) await supabase.from('coach_notes').delete().eq('id', noteId);
      // 4. First publish with a goal -> add it to the pupil's goals
      if (mode === 'publish' && !published && nextGoal.trim()) {
        const g = await supabase.from('goals').select('id').eq('student_id', c.student_id).eq('text', nextGoal.trim()).limit(1);
        if (!g.data?.length) {
          await supabase.from('goals').insert({ school_id: c.school_id, student_id: c.student_id, skill_id: c.skill_id, text: nextGoal.trim(), clip_id: c.id, published: true, created_by: session!.user.id });
        }
      }
      if (mode === 'publish') { router.replace({ pathname: '/clip/[id]', params: { id: c.id, published: '1' } }); return; }
      await load();
      setMessage({ kind: 'info', text: mode === 'hide' ? 'Hidden from the family. It’s a draft again.' : 'Saved. Only staff can see drafts.' });
    } catch (e) {
      const msg = (e as { message?: string }).message ?? '';
      setMessage({ kind: 'warn', text: /flagged/i.test(msg) ? 'This clip is flagged because other pupils are visible. Clear the flag after review, then publish.'
        : /network|fetch/i.test(msg) ? 'Couldn’t save. Check your connection and try again. Nothing was lost on this screen.' : `Couldn’t save: ${msg}` });
    } finally { setBusy(null); }
  }

  return (
    <Screen>
      <Stack.Screen options={{ title: 'Assess clip' }} />
      <View style={{ gap: 4 }}>
        <H2>{c.students?.display_name} · {c.skills?.name}</H2>
        <P muted>Filmed {fmtDate(c.recorded_on)} · uploaded {fmtDate(c.uploaded_at)}{c.drill ? ` · ${c.drill}` : ''}</P>
        {published ? <Pill kind="published" label="Shared with family" /> : <Pill kind="draft" label="Draft · staff only" />}
      </View>

      <ClipPlayer storagePath={c.storage_path!} controller={player} />

      <View style={{ borderWidth: 1, borderColor: restricted ? t.warn : t.line, borderRadius: radius.l, padding: space.m, gap: 8 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.m }}>
          <View style={{ flex: 1 }}>
            <Text style={{ fontWeight: '700', color: t.ink, fontSize: 15 }}>Other pupils are visible</Text>
            <Text style={{ color: t.muted, fontSize: 13.5 }}>Flagged clips can’t be published until reviewed.</Text>
          </View>
          <Switch value={restricted} onValueChange={setRestricted} accessibilityLabel="Other pupils are visible in this clip" />
        </View>
        {restricted ? <Field label="What needs reviewing? (optional)" value={reason} onChangeText={setReason} placeholder="e.g. Two pupils in the background" /> : null}
      </View>

      <H2>Moments</H2>
      <P muted>Pause on a moment, then pin a comment to that time. Families see these once published.</P>
      <MomentList moments={moments} onSeek={(s) => player.current?.seek(s)} onDelete={removeMoment} />
      <View style={{ flexDirection: 'row', gap: 8 }}>
        <TextInput value={momentText} onChangeText={setMomentText} placeholder="e.g. Lovely knee bend here" placeholderTextColor={t.muted}
          accessibilityLabel="Comment for the current moment"
          style={{ flex: 1, borderWidth: 1, borderColor: t.line, borderRadius: radius.m, paddingHorizontal: 12, minHeight: touch, color: t.ink, fontSize: 16 }} />
        <Button label="Pin" icon="pin-outline" kind="secondary" onPress={addMoment} />
      </View>

      <H2>{rubric ? `Rubric · version ${rubric.version}` : 'Rubric'}</H2>
      {!rubric ? <Notice kind="warn">There’s no published rubric for this skill yet. Ask your school admin to add one.</Notice> : (
        <View style={{ gap: space.m }}>
          <P muted>Saved with this version, so the levels keep their meaning even if the rubric changes later.</P>
          {rubric.criteria.map((cr) => {
            const l = scores[cr.key];
            return (
              <View key={cr.key} style={{ borderWidth: 1, borderColor: t.line, borderRadius: radius.l, padding: space.m, gap: 8 }}>
                <Text style={{ fontWeight: '700', color: t.ink, fontSize: 15 }}>{cr.name}</Text>
                <View style={{ flexDirection: 'row', gap: 6 }} accessibilityRole="radiogroup" accessibilityLabel={`${cr.name} level`}>
                  {rubric.levels.map((name, i) => {
                    const on = l === i + 1;
                    return (
                      <Pressable key={name} accessibilityRole="radio" accessibilityState={{ checked: on }} accessibilityLabel={`${name}, level ${i + 1}: ${cr.descriptors[i]}`}
                        onPress={() => setScores((s) => (on ? Object.fromEntries(Object.entries(s).filter(([k]) => k !== cr.key)) : { ...s, [cr.key]: i + 1 }))}
                        style={{ flex: 1, minHeight: 56, borderRadius: radius.m, borderWidth: 1.5, borderColor: on ? t.brand : t.line, backgroundColor: on ? t.brandSoft : t.bg, alignItems: 'center', justifyContent: 'center', padding: 4 }}>
                        <Text style={{ fontWeight: '800', fontSize: 17, color: on ? t.brand : t.ink }}>{i + 1}</Text>
                        <Text style={{ fontSize: 11.5, color: on ? t.brand : t.muted, textAlign: 'center' }} numberOfLines={1}>{name}</Text>
                      </Pressable>
                    );
                  })}
                </View>
                <Text style={{ color: t.muted, fontSize: 14 }}>{l ? cr.descriptors[l - 1] : 'Choose the level that matches what you see. Tap again to clear.'}</Text>
              </View>
            );
          })}
        </View>
      )}

      <H2>Feedback for the family</H2>
      <Field label="Overall feedback" value={feedback} onChangeText={setFeedback} multiline placeholder="What went well today, in encouraging words" style={{ minHeight: 96, textAlignVertical: 'top', paddingTop: 12 }} />
      <Field label="Strengths" value={strengths} onChangeText={setStrengths} />
      <Field label="To work on" value={toImprove} onChangeText={setToImprove} />
      <Field label="Goal for next session" value={nextGoal} onChangeText={setNextGoal} placeholder="One clear thing to practise" hint="Added to the pupil’s goals when you publish." />

      <View style={{ borderWidth: 1.5, borderStyle: 'dashed', borderColor: t.line, borderRadius: radius.l, padding: space.m, gap: 6 }}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
          <Ionicons name="lock-closed-outline" size={16} color={t.ink} />
          <Text style={{ fontWeight: '700', color: t.ink }}>Private coach note</Text>
        </View>
        <TextInput value={note} onChangeText={setNote} multiline placeholder="Only staff can see this" placeholderTextColor={t.muted} accessibilityLabel="Private coach note"
          style={{ minHeight: 72, color: t.ink, fontSize: 16, textAlignVertical: 'top' }} />
        <Text style={{ color: t.muted, fontSize: 13 }}>Never shown to families or pupils.</Text>
      </View>

      {message ? <Notice kind={message.kind}>{message.text}</Notice> : null}
      <View style={{ flexDirection: 'row', gap: space.m }}>
        <Button style={{ flex: 1 }} label="Save draft" kind="secondary" busy={busy === 'draft'} disabled={!!busy || !rubric} onPress={() => save('draft')} />
        <Button style={{ flex: 1 }} label={published ? 'Update for family' : 'Publish to family'} kind="accent" busy={busy === 'publish'} disabled={!!busy || !rubric || restricted} onPress={() => save('publish')} />
      </View>
      {published ? <Button label="Hide from family" kind="danger" busy={busy === 'hide'} disabled={!!busy} onPress={() => save('hide')} /> : null}
    </Screen>
  );
}
