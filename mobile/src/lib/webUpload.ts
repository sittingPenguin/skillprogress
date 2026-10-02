// Web (browser) upload path. Used by the web version until the installed app is available.
// It uses the same register_clip() call, so a retry with the same upload id never duplicates.
import * as Crypto from 'expo-crypto';
import { supabase, VIDEO_BUCKET } from './supabase';

export interface WebUploadInput {
  file: Blob;
  mimeType: string;
  studentId: string;
  skillId: string;
  recordedOn: string;
  drill: string | null;
  durationMs: number | null;
  uploadId?: string;
}

export async function uploadFromBrowser(input: WebUploadInput): Promise<{ clipId: string; uploadId: string }> {
  const uploadId = input.uploadId ?? Crypto.randomUUID();
  const { data, error } = await supabase.rpc('register_clip', {
    p_upload_id: uploadId, p_student: input.studentId, p_skill: input.skillId,
    p_recorded_on: input.recordedOn, p_drill: input.drill,
  });
  if (error) throw Object.assign(new Error(error.message), { step: 'Creating the clip record' });
  const clip = data as { id: string; storage_path: string };
  const up = await supabase.storage.from(VIDEO_BUCKET).upload(clip.storage_path, input.file, {
    contentType: input.mimeType || 'video/mp4', upsert: true,
  });
  if (up.error) throw Object.assign(new Error(up.error.message), { uploadId, step: 'Uploading the video' });
  const done = await supabase.from('clips').update({ upload_status: 'ready', duration_ms: input.durationMs }).eq('id', clip.id);
  if (done.error) throw Object.assign(new Error(done.error.message), { uploadId, step: 'Marking the clip ready' });
  return { clipId: clip.id, uploadId };
}
