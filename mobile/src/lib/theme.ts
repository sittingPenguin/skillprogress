// Colours and spacing shared across the app. Mirrors the approved demo.
import { useColorScheme } from 'react-native';

const light = {
  bg: '#FFFFFF',
  surface: '#F4F7F6',
  ink: '#11201C',
  muted: '#5A6A66',
  line: '#DCE4E1',
  brand: '#0E6B60',
  brandSoft: '#DDF0EC',
  accent: '#E5482F',
  ok: '#1D7A4B',
  okSoft: '#DFF3E7',
  draft: '#5B4BC4',
  draftSoft: '#ECE9FB',
  warn: '#9A5600',
  warnSoft: '#FBEBD3',
  onInk: '#FFFFFF',
};
const dark: typeof light = {
  bg: '#0A100F',
  surface: '#18231F',
  ink: '#E6EEEB',
  muted: '#93A39F',
  line: '#26332F',
  brand: '#45C2B1',
  brandSoft: '#123430',
  accent: '#FF6E55',
  ok: '#5CCB8E',
  okSoft: '#12301F',
  draft: '#A99CFF',
  draftSoft: '#221D44',
  warn: '#F0B055',
  warnSoft: '#352612',
  onInk: '#0A100F',
};
export type Palette = typeof light;

export function useTheme(): Palette {
  return useColorScheme() === 'dark' ? dark : light;
}

export const space = { xs: 4, s: 8, m: 12, l: 16, xl: 24 };
export const radius = { s: 8, m: 12, l: 16, pill: 999 };
export const touch = 48; // minimum touch target
