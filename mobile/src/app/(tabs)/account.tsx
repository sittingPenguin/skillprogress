import React, { useState } from 'react';
import { View } from 'react-native';
import { router } from 'expo-router';
import { useSession } from '../../lib/session';
import { uploadQueue } from '../../lib/uploads';
import { space } from '../../lib/theme';
import { Button, Chip, H2, Notice, P, Screen } from '../../components/ui';

const ROLE_LABEL = { admin: 'School admin', coach: 'Coach', guardian: 'Parent or carer', student: 'Pupil' } as const;

export default function Account() {
  const { session, active, memberships, setActive, signOut } = useSession();
  const [confirm, setConfirm] = useState(false);
  const waiting = uploadQueue.list().filter((i) => i.status !== 'done').length;

  return (
    <Screen>
      <View style={{ gap: 4 }}>
        <H2>{active?.display_name}</H2>
        <P muted>{session?.user.email}</P>
        <P muted>{active ? `${ROLE_LABEL[active.role]} at ${active.schools?.name ?? 'your school'}` : ''}</P>
      </View>
      {memberships.length > 1 ? (
        <View style={{ gap: space.s }}>
          <P>Switch view</P>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
            {memberships.map((m) => <Chip key={m.id} label={`${ROLE_LABEL[m.role]} · ${m.schools?.name ?? ''}`} selected={m.id === active?.id} onPress={() => { setActive(m); router.replace('/home'); }} />)}
          </View>
        </View>
      ) : null}
      <Notice>Clips and feedback are private to your school. Videos open through links that expire after a few minutes.</Notice>
      {confirm && waiting ? <Notice kind="warn">{waiting} clip{waiting === 1 ? ' is' : 's are'} still waiting to upload. They’ll stay on this device and upload after you sign back in.</Notice> : null}
      {confirm
        ? <Button label="Tap again to sign out" kind="danger" onPress={async () => { await signOut(); router.replace('/'); }} />
        : <Button label="Sign out" kind="secondary" onPress={() => setConfirm(true)} />}
      <P muted>SkillProgress pilot · version 0.2</P>
    </Screen>
  );
}
