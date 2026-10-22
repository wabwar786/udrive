import { PLAY_URL } from '@/lib/config';
import { PlayIcon } from './Icons';

export function PlayButton() {
  return (
    <a className="play" href={PLAY_URL} target="_blank" rel="noopener noreferrer">
      <PlayIcon />
      <div><small>Get it on</small><b>Google Play</b></div>
    </a>
  );
}
