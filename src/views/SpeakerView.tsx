import { useState, useEffect, useCallback, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { createConfig, startStreamingTranscription, stopStreamingTranscription } from '../lib/transcribe';
import { createTranslateClient, translateText } from '../lib/translate';
import styles from './SpeakerView.module.css';

type SubtitleState = {
  final: string;
  partial: string;
};

const INACTIVITY_TIMEOUT_MS = 5 * 60 * 1000;

const baseLang = (lang: string): string => lang.split('-')[0].toLowerCase();

const MicIcon = () => (
  <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor">
    <path d="M12 14a3 3 0 0 0 3-3V5a3 3 0 0 0-6 0v6a3 3 0 0 0 3 3zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V20H9v2h6v-2h-2v-2.08A7 7 0 0 0 19 11h-2z"/>
  </svg>
);

const StopIcon = () => (
  <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
    <rect x="5" y="5" width="14" height="14" rx="2"/>
  </svg>
);

export default function SpeakerView() {
  const [params] = useSearchParams();
  const src = params.get('src') ?? 'en-US';
  const tgt = params.get('tgt') ?? 'pt';
  const token = params.get('token') ?? '';

  const [active, setActive] = useState(false);
  const [subtitles, setSubtitles] = useState<SubtitleState>({ final: '', partial: '' });
  const [error, setError] = useState<string | null>(null);
  const [timedOut, setTimedOut] = useState(false);

  const mediaStreamRef = useRef<MediaStream | undefined>(undefined);
  const inactivityTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastFinalTextRef = useRef<string>('');
  const pendingRef = useRef<{
    text: string;
    lang: string | undefined;
    timer: ReturnType<typeof setTimeout> | null;
  }>({ text: '', lang: undefined, timer: null });

  const handleStop = useCallback(() => {
    stopStreamingTranscription();
    mediaStreamRef.current?.getTracks().forEach(t => t.stop());
    mediaStreamRef.current = undefined;
    if (inactivityTimerRef.current) {
      clearTimeout(inactivityTimerRef.current);
      inactivityTimerRef.current = null;
    }
    setActive(false);
  }, []);

  // Real VAD (pausing the audio generator on silence) risks the Transcribe
  // stream closing server-side mid-utterance. A wall-clock counter since the
  // last final result is simpler and catches the actual leak: a mic left on
  // after the talk ends.
  const scheduleAutoStop = useCallback(() => {
    if (inactivityTimerRef.current) clearTimeout(inactivityTimerRef.current);
    inactivityTimerRef.current = setTimeout(() => {
      handleStop();
      setTimedOut(true);
    }, INACTIVITY_TIMEOUT_MS);
  }, [handleStop]);

  const handleStart = useCallback(async () => {
    setError(null);
    setTimedOut(false);
    setSubtitles({ final: '', partial: '' });
    pendingRef.current = { text: '', lang: undefined, timer: null };
    lastFinalTextRef.current = '';

    if (!token) {
      setError('Missing room token. Ask the organizer for a fresh speaker link.');
      return;
    }

    let mediaStream: MediaStream;
    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      setError('Microphone access denied. Allow mic in browser settings and try again.');
      return;
    }

    mediaStreamRef.current = mediaStream;
    setActive(true);
    scheduleAutoStop();

    const flushTranslation = (sourceLang: string) => {
      const text = pendingRef.current.text.trim();
      if (!text) return;
      pendingRef.current.text = '';
      pendingRef.current.lang = undefined;

      // Transcribe occasionally re-emits the same final segment; skip the
      // repeat rather than pay for translating it twice.
      if (text === lastFinalTextRef.current) return;
      lastFinalTextRef.current = text;

      if (baseLang(sourceLang) === baseLang(tgt)) {
        setSubtitles({ final: text, partial: '' });
        return;
      }

      translateText(text, sourceLang, tgt)
        .then(translated => {
          setSubtitles({ final: translated, partial: '' });
        })
        .catch(err => {
          const msg = String(err);
          if (msg.includes('UnsupportedLanguagePairException')) {
            setError('Unsupported language pair. Change target language and restart.');
          }
        });
    };

    try {
      const config = await createConfig(token);
      createTranslateClient(config);

      await startStreamingTranscription({
        mediaStream,
        options: { language: src, identifyLanguage: src === 'auto' },
        callback: (transcript, isFinal, identifiedLanguage) => { // NOSONAR - boolean flag is idiomatic for streaming partial/final events
          if (isFinal) {
            scheduleAutoStop();
            setSubtitles((prev: SubtitleState) => ({ ...prev, partial: '' }));

            const effectiveLang = identifiedLanguage ?? src;
            pendingRef.current.text += transcript;
            pendingRef.current.lang = effectiveLang;

            if (pendingRef.current.timer) clearTimeout(pendingRef.current.timer);
            pendingRef.current.timer = setTimeout(() => {
              flushTranslation(pendingRef.current.lang ?? effectiveLang);
            }, 400);
          } else {
            setSubtitles((prev: SubtitleState) => ({ ...prev, partial: transcript }));
          }
        },
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      if (pendingRef.current.timer) clearTimeout(pendingRef.current.timer);
      setActive(false);
    }
  }, [src, tgt, token, scheduleAutoStop]);

  useEffect(() => () => handleStop(), [handleStop]);

  const showIdleHint = !active && !subtitles.final && !subtitles.partial;

  return (
    <div className={styles.root}>
      {subtitles.final && (
        <div key={subtitles.final} className={styles.finalText}>{subtitles.final}</div>
      )}

      <div className={styles.bottomArea}>
        {subtitles.partial && (
          <div className={styles.partialText}>{subtitles.partial}</div>
        )}
        {showIdleHint && (
          <div className={styles.idleHint}>
            {timedOut ? 'Stopped after 5 min of silence, tap mic to resume' : 'Tap mic to begin'}
          </div>
        )}
        {error && (
          <div className={styles.errorText}>{error}</div>
        )}
      </div>

      <div className={styles.controls}>
        {active ? (
          <button type="button" className={`${styles.btn} ${styles.btnStop}`} onClick={handleStop} aria-label="Stop">
            <StopIcon />
          </button>
        ) : (
          <button type="button" className={styles.btn} onClick={handleStart} aria-label="Start mic">
            <MicIcon />
          </button>
        )}
      </div>
    </div>
  );
}
