// Stores the sign-in session in the device keychain / keystore.
// SecureStore values are size-limited, so long sessions are split into chunks.
import { Platform } from 'react-native';
import * as SecureStore from 'expo-secure-store';

const CHUNK = 1800;
const safeKey = (k: string) => k.replace(/[^A-Za-z0-9._-]/g, '_');

async function getItem(key: string): Promise<string | null> {
  if (Platform.OS === 'web') {
    try { return globalThis.localStorage?.getItem(key) ?? null; } catch { return null; }
  }
  const k = safeKey(key);
  const count = await SecureStore.getItemAsync(`${k}.n`);
  if (!count) return null;
  const parts: string[] = [];
  for (let i = 0; i < Number(count); i++) {
    const part = await SecureStore.getItemAsync(`${k}.${i}`);
    if (part == null) return null;
    parts.push(part);
  }
  return parts.join('');
}

async function removeItem(key: string): Promise<void> {
  if (Platform.OS === 'web') {
    try { globalThis.localStorage?.removeItem(key); } catch { /* ignore */ }
    return;
  }
  const k = safeKey(key);
  const count = Number((await SecureStore.getItemAsync(`${k}.n`)) ?? 0);
  for (let i = 0; i < count; i++) await SecureStore.deleteItemAsync(`${k}.${i}`);
  await SecureStore.deleteItemAsync(`${k}.n`);
}

async function setItem(key: string, value: string): Promise<void> {
  if (Platform.OS === 'web') {
    try { globalThis.localStorage?.setItem(key, value); } catch { /* ignore */ }
    return;
  }
  await removeItem(key);
  const k = safeKey(key);
  const n = Math.ceil(value.length / CHUNK);
  for (let i = 0; i < n; i++) {
    await SecureStore.setItemAsync(`${k}.${i}`, value.slice(i * CHUNK, (i + 1) * CHUNK), {
      keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY,
    });
  }
  await SecureStore.setItemAsync(`${k}.n`, String(n));
}

export const secureSessionStorage = { getItem, setItem, removeItem };
