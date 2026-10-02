// Full-screen camera for recording a practice clip. Handles camera and microphone permission
// denial clearly, caps clips at 60 seconds and records at 720p to keep uploads small.
import React, { useEffect, useRef, useState } from 'react';
import { Linking, Pressable, Text, View } from 'react-native';
import { router } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView, useCameraPermissions, useMicrophonePermissions } from 'expo-camera';
import { Ionicons } from '@expo/vector-icons';
import { clipDraft } from '../lib/clipDraft';
import { Button, Notice, P, Screen } from '../components/ui';

const MAX_SECONDS = 60;

export default function Record() {
  const cam = useRef<CameraView>(null);
  const [camPerm, requestCam] = useCameraPermissions();
  const [micPerm, requestMic] = useMicrophonePermissions();
  const [facing, setFacing] = useState<'back' | 'front'>('back');
  const [recording, setRecording] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (!recording) return;
    const start = Date.now();
    const iv = setInterval(() => setElapsed(Math.floor((Date.now() - start) / 1000)), 250);
    return () => clearInterval(iv);
  }, [recording]);

  if (!camPerm || !micPerm) return <Screen><P muted>Checking camera access…</P></Screen>;

  if (!camPerm.granted || !micPerm.granted) {
    const blocked = (!camPerm.granted && !camPerm.canAskAgain) || (!micPerm.granted && !micPerm.canAskAgain);
    return (
      <Screen>
        <Notice kind="warn">
          {blocked
            ? 'Camera or microphone access is turned off for SkillProgress. Turn both on in Settings to record, or choose an existing clip instead.'
            : 'SkillProgress needs the camera and microphone to record practice clips. Clips are private to your school.'}
        </Notice>
        {blocked
          ? <Button label="Open Settings" onPress={() => Linking.openSettings()} />
          : <Button label="Allow camera and microphone" onPress={async () => { await requestCam(); await requestMic(); }} />}
        <Button label="Go back" kind="secondary" onPress={() => router.back()} />
      </Screen>
    );
  }

  async function toggle() {
    if (!cam.current) return;
    if (recording) { cam.current.stopRecording(); return; }
    setElapsed(0); setRecording(true);
    const started = Date.now();
    try {
      const res = await cam.current.recordAsync({ maxDuration: MAX_SECONDS, codec: 'avc1' });
      if (res?.uri) {
        clipDraft.set({ uri: res.uri, durationMs: Date.now() - started, source: 'camera' });
        router.back();
      }
    } finally { setRecording(false); }
  }

  return (
    <View style={{ flex: 1, backgroundColor: '#000' }}>
      <CameraView ref={cam} style={{ flex: 1 }} mode="video" facing={facing} videoQuality="720p" videoBitrate={2_500_000} onCameraReady={() => setReady(true)} />
      <SafeAreaView style={{ position: 'absolute', top: 0, left: 0, right: 0 }} edges={['top']}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: 12 }}>
          <Pressable accessibilityRole="button" accessibilityLabel="Close camera" disabled={recording} onPress={() => router.back()} style={{ width: 48, height: 48, alignItems: 'center', justifyContent: 'center' }}>
            <Ionicons name="close" size={30} color="#fff" />
          </Pressable>
          <View accessibilityLiveRegion="polite" style={{ flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: 'rgba(0,0,0,.5)', paddingHorizontal: 10, paddingVertical: 4, borderRadius: 8 }}>
            {recording ? <View style={{ width: 10, height: 10, borderRadius: 5, backgroundColor: '#ff4b3a' }} /> : null}
            <Text style={{ color: '#fff', fontVariant: ['tabular-nums'], fontWeight: '600' }}>
              {recording ? `REC 0:${String(elapsed).padStart(2, '0')} / 1:00` : 'Max 1 minute'}
            </Text>
          </View>
          <Pressable accessibilityRole="button" accessibilityLabel="Switch camera" disabled={recording} onPress={() => setFacing((f) => (f === 'back' ? 'front' : 'back'))} style={{ width: 48, height: 48, alignItems: 'center', justifyContent: 'center' }}>
            <Ionicons name="camera-reverse-outline" size={28} color="#fff" />
          </Pressable>
        </View>
      </SafeAreaView>
      <SafeAreaView style={{ position: 'absolute', bottom: 0, left: 0, right: 0, alignItems: 'center' }} edges={['bottom']}>
        <Pressable
          accessibilityRole="button" accessibilityLabel={recording ? 'Stop recording' : 'Start recording'} disabled={!ready}
          onPress={toggle}
          style={{ width: 84, height: 84, borderRadius: 42, borderWidth: 5, borderColor: '#fff', alignItems: 'center', justifyContent: 'center', marginBottom: 24, opacity: ready ? 1 : 0.5 }}>
          <View style={{ width: recording ? 32 : 64, height: recording ? 32 : 64, borderRadius: recording ? 6 : 32, backgroundColor: '#ff4b3a' }} />
        </Pressable>
      </SafeAreaView>
    </View>
  );
}
