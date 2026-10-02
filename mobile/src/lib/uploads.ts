// Upload queue built for patchy school Wi-Fi.
//  - Each clip gets an upload id on the device BEFORE the first attempt. The server's
//    register_clip() returns the same clip for the same id, so retries never duplicate.
//  - Video goes up with the resumable (tus) protocol in 6 MB chunks, so a dropped
//    connection resumes from the last chunk, even after the app is closed.
//  - The queue is saved on the device and retried when the app comes back to the foreground.
//  - Local copies live in the app's private cache and are deleted once uploaded.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { AppState } from 'react-native';
import { Directory, File, Paths } from 'expo-file-system';
import * as Crypto from 'expo-crypto';
import * as tus from 'tus-js-client';
import { supabase, SUPABASE_URL, SUPABASE_KEY, VIDEO_BUCKET } from './supabase';

export type UploadStatus = 'waiting' | 'uploading' | 'failed' | 'done';

export interface QueuedUpload {
  uploadId: string;
  localUri: string;
  mimeType: string;
  studentId: string;
  studentName: string;
  skillId: string;
  skillName: string;
  recordedOn: string; // YYYY-MM-DD, when it was filmed
  drill: string | null;
  durationMs: number | null;
  status: UploadStatus;
  progress: number; // 0..1
  error: string | null;
  clipId: string | null;
  storagePath: string | null;
  attempts: number;
  createdAt: string;
}

export type NewUpload = Pick<QueuedUpload, 'studentId' | 'studentName' | 'skillId' | 'skillName' | 'recordedOn' | 'drill' | 'durationMs'> & {
  sourceUri: string;
};

const KEY = 'sp.uploadQueue.v1';
const TUS_KEY = 'sp.tus.';
const AUTO_RETRIES = 3;

// tus needs somewhere to remember half-finished uploads between app launches.
const tusUrlStorage = {
  async findAllUploads() { return []; },
  async findUploadsByFingerprint(fp: string) {
    const v = await AsyncStorage.getItem(TUS_KEY + fp);
    return v ? [JSON.parse(v)] : [];
  },
  async removeUpload(urlStorageKey: string) { await AsyncStorage.removeItem(urlStorageKey); },
  async addUpload(fp: string, upload: unknown) {
    await AsyncStorage.setItem(TUS_KEY + fp, JSON.stringify(upload));
    return TUS_KEY + fp;
  },
};

function friendly(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  if (/network|fetch|timeout|offline|connect/i.test(msg)) return 'Connection lost. The clip is safe on this device and will resume.';
  if (/row-level|not allowed|42501|permission/i.test(msg)) return 'You no longer have access to this pupil. Ask your school admin.';
  if (/sign in|jwt|session/i.test(msg)) return 'Sign in again to finish this upload.';
  return msg.length > 140 ? msg.slice(0, 140) + '…' : msg;
}

class UploadQueue {
  private items: QueuedUpload[] = [];
  private listeners = new Set<(items: QueuedUpload[]) => void>();
  private loaded = false;
  private running = false;
  private current: tus.Upload | null = null;

  async init() {
    if (this.loaded) return;
    try {
      const raw = await AsyncStorage.getItem(KEY);
      this.items = raw ? (JSON.parse(raw) as QueuedUpload[]) : [];
    } catch { this.items = []; }
    // Anything interrupted mid-upload when the app closed goes back in the line.
    this.items = this.items.map((i) => (i.status === 'uploading' ? { ...i, status: 'waiting' } : i));
    this.loaded = true;
    this.emit();
    AppState.addEventListener('change', (s) => { if (s === 'active') this.retryAll(false); });
    this.process();
  }

  subscribe(fn: (items: QueuedUpload[]) => void) {
    this.listeners.add(fn);
    fn(this.items);
    return () => { this.listeners.delete(fn); };
  }

  list() { return this.items; }

  async add(n: NewUpload) {
    const uploadId = Crypto.randomUUID();
    const ext = /\.mov$/i.test(n.sourceUri) ? 'mov' : 'mp4';
    const dir = new Directory(Paths.cache, 'pending-uploads');
    try { dir.create({ intermediates: true, idempotent: true }); } catch { /* exists */ }
    const dest = new File(dir, `${uploadId}.${ext}`);
    await Promise.resolve(new File(n.sourceUri).copy(dest));
    const item: QueuedUpload = {
      uploadId, localUri: dest.uri, mimeType: ext === 'mov' ? 'video/quicktime' : 'video/mp4',
      studentId: n.studentId, studentName: n.studentName, skillId: n.skillId, skillName: n.skillName,
      recordedOn: n.recordedOn, drill: n.drill, durationMs: n.durationMs,
      status: 'waiting', progress: 0, error: null, clipId: null, storagePath: null, attempts: 0,
      createdAt: new Date().toISOString(),
    };
    this.items = [item, ...this.items];
    await this.save();
    this.process();
    return item;
  }

  async retry(uploadId: string) {
    this.patch(uploadId, { status: 'waiting', error: null, attempts: 0 });
    await this.save();
    this.process();
  }

  async retryAll(resetAttempts = true) {
    this.items = this.items.map((i) => (i.status === 'failed' ? { ...i, status: 'waiting', error: null, attempts: resetAttempts ? 0 : i.attempts } : i));
    await this.save();
    this.process();
  }

  async cancel(uploadId: string) {
    const item = this.items.find((i) => i.uploadId === uploadId);
    if (!item) return;
    if (item.status === 'uploading' && this.current) { try { await this.current.abort(true); } catch { /* ignore */ } }
    if (item.clipId) await supabase.from('clips').update({ upload_status: 'failed' }).eq('id', item.clipId);
    this.deleteLocal(item);
    await AsyncStorage.removeItem(TUS_KEY + uploadId);
    this.items = this.items.filter((i) => i.uploadId !== uploadId);
    await this.save();
  }

  async clearDone() {
    this.items = this.items.filter((i) => i.status !== 'done');
    await this.save();
  }

  private deleteLocal(item: QueuedUpload) {
    try { const f = new File(item.localUri); if (f.exists) f.delete(); } catch { /* ignore */ }
  }

  private patch(uploadId: string, p: Partial<QueuedUpload>) {
    this.items = this.items.map((i) => (i.uploadId === uploadId ? { ...i, ...p } : i));
    this.emit();
  }

  private emit() { const snap = [...this.items]; this.listeners.forEach((l) => l(snap)); }
  private async save() { this.emit(); await AsyncStorage.setItem(KEY, JSON.stringify(this.items)); }

  private async process() {
    if (this.running || !this.loaded) return;
    this.running = true;
    try {
      let next: QueuedUpload | undefined;
      while ((next = this.items.find((i) => i.status === 'waiting'))) {
        await this.uploadOne(next);
      }
    } finally {
      this.running = false;
    }
  }

  private async uploadOne(item: QueuedUpload) {
    const id = item.uploadId;
    this.patch(id, { status: 'uploading', error: null, attempts: item.attempts + 1 });
    try {
      const { data: s } = await supabase.auth.getSession();
      if (!s.session) throw new Error('Sign in again to finish this upload.');
      if (!new File(item.localUri).exists) throw new Error('The video file is no longer on this device. Please record it again.');

      // 1. Create (or, on retry, fetch) the clip record. Same upload id = same clip.
      const { data: clip, error } = await supabase.rpc('register_clip', {
        p_upload_id: id, p_student: item.studentId, p_skill: item.skillId,
        p_recorded_on: item.recordedOn, p_drill: item.drill,
      });
      if (error) throw new Error(error.message);
      const c = clip as { id: string; storage_path: string };
      this.patch(id, { clipId: c.id, storagePath: c.storage_path });
      await this.save();

      // 2. Resumable upload of the video into the private bucket.
      await new Promise<void>((resolve, reject) => {
        const upload = new tus.Upload({ uri: item.localUri, name: `${id}.mp4`, type: item.mimeType } as unknown as Blob, {
          endpoint: `${SUPABASE_URL}/storage/v1/upload/resumable`,
          retryDelays: [0, 2000, 5000, 10000, 20000],
          chunkSize: 6 * 1024 * 1024, // Supabase requires exactly 6 MB chunks
          uploadDataDuringCreation: true,
          removeFingerprintOnSuccess: true,
          storeFingerprintForResuming: true,
          urlStorage: tusUrlStorage as unknown as tus.UrlStorage,
          fingerprint: async () => id,
          headers: { authorization: `Bearer ${s.session!.access_token}`, apikey: SUPABASE_KEY, 'x-upsert': 'true' },
          metadata: { bucketName: VIDEO_BUCKET, objectName: c.storage_path, contentType: item.mimeType, cacheControl: '3600' },
          onProgress: (sent, total) => this.patch(id, { progress: total ? sent / total : 0 }),
          onError: (e) => reject(e),
          onSuccess: () => resolve(),
        });
        this.current = upload;
        upload.findPreviousUploads().then((prev) => {
          if (prev.length) upload.resumeFromPreviousUpload(prev[0]);
          upload.start();
        });
      });
      this.current = null;

      // 3. Mark the clip ready and remove the local copy.
      const { error: e2 } = await supabase.from('clips')
        .update({ upload_status: 'ready', duration_ms: item.durationMs == null ? null : Math.round(item.durationMs) })
        .eq('id', c.id);
      if (e2) throw new Error(e2.message);
      this.deleteLocal(item);
      this.patch(id, { status: 'done', progress: 1 });
      await this.save();
    } catch (e) {
      this.current = null;
      const attempts = (this.items.find((i) => i.uploadId === id)?.attempts) ?? AUTO_RETRIES;
      const retryable = attempts < AUTO_RETRIES && !/no longer|access/i.test(friendly(e));
      this.patch(id, { status: retryable ? 'waiting' : 'failed', error: friendly(e) });
      await this.save();
      if (retryable) await new Promise((r) => setTimeout(r, 3000 * attempts));
    }
  }
}

export const uploadQueue = new UploadQueue();
