// Plays a private clip through a short-lived signed link, with slow motion and frame-accurate seeking.
import React, { useEffect, useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { useEvent } from 'expo';
import { useVideoPlayer, VideoView } from 'expo-video';
import { Ionicons } from '@expo/vector-icons';
import { supabase, VIDEO_BUCKET, VIDEO_LINK_SECONDS } from '../lib/supabase';
import { radius, useTheme } from '../lib/theme';
import { Loading, Notice } from './ui';

const SPEEDS = [1, 0.5, 0.25];

export interface PlayerApi { seek: (seconds: number) => void; time: () => number; play: (rate?: number) => void; pause: () => void }
type ControllerRef = React.MutableRefObject<PlayerApi | null>;

export function ClipPlayer({ storagePath, aspect = 4 / 5, controller }: { storagePath: string; aspect?: number; controller?: ControllerRef }) {
  const [url, setUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    supabase.storage.from(VIDEO_BUCKET).createSignedUrl(storagePath, VIDEO_LINK_SECONDS).then(({ data, error: e }) => {
      if (!alive) return;
      if (e || !data) setError('This clip can’t be played right now. Check your connection, or it may have been removed.');
      else setUrl(data.signedUrl);
    });
    return () => { alive = false; };
  }, [storagePath]);

  if (error) return <Notice kind="warn">{error}</Notice>;
  if (!url) return <Loading label="Loading clip…" />;
  return <Player url={url} aspect={aspect} controller={controller} />;
}

function Player({ url, aspect, controller }: { url: string; aspect: number; controller?: ControllerRef }) {
  const t = useTheme();
  const player = useVideoPlayer(url, (p) => { p.timeUpdateEventInterval = 0.1; p.loop = false; });
  const { isPlaying } = useEvent(player, 'playingChange', { isPlaying: player.playing });
  const time = useEvent(player, 'timeUpdate', { currentTime: 0, bufferedPosition: 0, currentLiveTimestamp: null, currentOffsetFromLive: null });
  const [speed, setSpeed] = useState(1);
  useEffect(() => {
    if (!controller) return;
    controller.current = {
      seek: (sec) => { player.pause(); player.currentTime = Math.max(0, sec); },
      time: () => player.currentTime,
      play: (rate) => { if (rate) { player.playbackRate = rate; setSpeed(rate); } player.play(); },
      pause: () => player.pause(),
    };
    return () => { controller.current = null; };
  }, [player, controller]);

  const step = (d: number) => { player.pause(); player.currentTime = Math.max(0, player.currentTime + d); };
  const setRate = (r: number) => { player.playbackRate = r; setSpeed(r); };

  return (
    <View style={{ borderRadius: radius.l, overflow: 'hidden', backgroundColor: '#0d1719' }}>
      <VideoView player={player} style={{ width: '100%', aspectRatio: aspect }} contentFit="contain" nativeControls={false} />
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, padding: 8, flexWrap: 'wrap' }}>
        <Ctl icon={isPlaying ? 'pause' : 'play'} label={isPlaying ? 'Pause' : 'Play'} onPress={() => (isPlaying ? player.pause() : player.play())} />
        <Ctl icon="play-back" label="Back a tenth of a second" onPress={() => step(-0.1)} />
        <Ctl icon="play-forward" label="Forward a tenth of a second" onPress={() => step(0.1)} />
        <Text style={{ color: '#e7efec', fontVariant: ['tabular-nums'], minWidth: 54 }} accessibilityLabel={`Time ${time.currentTime.toFixed(1)} seconds`}>
          {time.currentTime.toFixed(1)}s
        </Text>
        <View style={{ flex: 1 }} />
        {SPEEDS.map((s) => (
          <Pressable key={s} accessibilityRole="button" accessibilityLabel={`Speed ${s} times`} accessibilityState={{ selected: speed === s }}
            onPress={() => setRate(s)}
            style={{ minWidth: 48, minHeight: 40, borderRadius: 8, borderWidth: 1, borderColor: 'rgba(255,255,255,.35)', backgroundColor: speed === s ? '#e7efec' : 'transparent', alignItems: 'center', justifyContent: 'center' }}>
            <Text style={{ color: speed === s ? '#0d1719' : '#e7efec', fontWeight: '600' }}>{s}×</Text>
          </Pressable>
        ))}
      </View>
      <View style={{ height: 3, backgroundColor: t.brand, width: player.duration ? `${Math.min(100, (time.currentTime / player.duration) * 100)}%` : '0%' }} />
    </View>
  );
}

function Ctl({ icon, label, onPress }: { icon: React.ComponentProps<typeof Ionicons>['name']; label: string; onPress: () => void }) {
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={label} onPress={onPress} style={{ width: 44, height: 44, alignItems: 'center', justifyContent: 'center' }}>
      <Ionicons name={icon} size={22} color="#e7efec" />
    </Pressable>
  );
}
