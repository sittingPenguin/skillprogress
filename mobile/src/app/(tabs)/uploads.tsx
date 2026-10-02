import React, { useEffect, useState } from 'react';
import { View } from 'react-native';
import { uploadQueue, type QueuedUpload } from '../../lib/uploads';
import { radius, space, useTheme } from '../../lib/theme';
import { Button, Empty, fmtDate, Notice, P, Pill, Row, Screen } from '../../components/ui';

export default function Uploads() {
  const t = useTheme();
  const [items, setItems] = useState<QueuedUpload[]>([]);
  const [confirmCancel, setConfirmCancel] = useState<string | null>(null);
  useEffect(() => uploadQueue.subscribe(setItems), []);

  const failed = items.filter((i) => i.status === 'failed').length;
  const done = items.filter((i) => i.status === 'done').length;

  return (
    <Screen>
      {items.length === 0 ? <Empty icon="cloud-done-outline" title="Nothing waiting" body="Clips you record appear here while they upload." /> : null}
      {failed > 1 ? <Button label={`Retry all ${failed}`} icon="refresh" onPress={() => uploadQueue.retryAll()} /> : null}
      {items.map((i) => (
        <View key={i.uploadId} style={{ borderWidth: 1, borderColor: t.line, borderRadius: radius.l, padding: space.m, gap: space.s }}>
          <Row title={`${i.studentName} · ${i.skillName}`} subtitle={`Filmed ${fmtDate(i.recordedOn)}`} />
          {i.status === 'uploading' || i.status === 'waiting' ? (
            <View style={{ gap: 6 }}>
              <Pill kind="uploading" label={i.status === 'waiting' ? 'Waiting to upload' : `Uploading ${Math.round(i.progress * 100)}%`} />
              <View accessibilityRole="progressbar" accessibilityValue={{ min: 0, max: 100, now: Math.round(i.progress * 100) }}
                style={{ height: 8, borderRadius: 4, backgroundColor: t.surface, overflow: 'hidden' }}>
                <View style={{ height: '100%', width: `${Math.round(i.progress * 100)}%`, backgroundColor: t.brand }} />
              </View>
            </View>
          ) : null}
          {i.status === 'done' ? <Pill kind="published" label="Uploaded" /> : null}
          {i.status === 'failed' ? <Notice kind="warn">{i.error ?? 'Upload paused.'}</Notice> : null}
          {i.status === 'waiting' && i.error ? <P muted>{i.error}</P> : null}
          {i.status !== 'done' ? (
            <View style={{ flexDirection: 'row', gap: space.s }}>
              {i.status === 'failed' ? <Button style={{ flex: 1 }} label="Retry" icon="refresh" onPress={() => uploadQueue.retry(i.uploadId)} /> : null}
              {confirmCancel === i.uploadId
                ? <Button style={{ flex: 1 }} kind="danger" label="Tap again to cancel" onPress={() => { uploadQueue.cancel(i.uploadId); setConfirmCancel(null); }} />
                : <Button style={{ flex: 1 }} kind="secondary" label="Cancel" onPress={() => setConfirmCancel(i.uploadId)} />}
            </View>
          ) : null}
        </View>
      ))}
      {done ? <Button label="Clear finished" kind="secondary" onPress={() => uploadQueue.clearDone()} /> : null}
      {items.length ? <P muted>Retrying never creates a duplicate clip. Each clip keeps the same upload ID until it finishes.</P> : null}
    </Screen>
  );
}
