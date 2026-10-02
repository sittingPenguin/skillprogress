// Holds the clip being prepared on the New clip screen while the camera screen is open.
type Listener = () => void;
export interface DraftVideo { uri: string; durationMs: number | null; source: 'camera' | 'library' }

let video: DraftVideo | null = null;
const listeners = new Set<Listener>();

export const clipDraft = {
  get: () => video,
  set(v: DraftVideo | null) { video = v; listeners.forEach((l) => l()); },
  subscribe(l: Listener) { listeners.add(l); return () => { listeners.delete(l); }; },
};
