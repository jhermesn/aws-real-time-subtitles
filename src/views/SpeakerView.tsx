import { useState, useEffect, useCallback, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { createConfig, startStreamingTranscription, stopStreamingTranscription } from '../lib/transcribe';
import { createTranslateClient, translateText } from '../lib/translate';
import styles from './SpeakerView.module.css';

type SubtitleState = {
  final: string;
  partial: string;
};

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

  const [active, setActive] = useState(false);
  const [subtitles, setSubtitles] = useState<SubtitleState>({ final: '', partial: '' });
  const [error, setError] = useState<string | null>(null);

  const recorderRef = useRef<MediaRecorder | undefined>(undefined);
  const pendingRef = useRef<{
    text: string;
    lang: string | undefined;
    timer: ReturnType<typeof setTimeout> | null;
  }>({ text: '', lang: undefined, timer: null });

  const handleStart = useCallback(async () => {
    setError(null);
    setSubtitles({ final: '', partial: '' });
    pendingRef.current = { text: '', lang: undefined, timer: null };

    let mediaStream: MediaStream;
    try {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      setError('Microphone access denied. Allow mic in browser settings and try again.');
      return;
    }

    const recorder = new MediaRecorder(mediaStream);
    recorder.onstop = () => mediaStream.getTracks().forEach(t => t.stop());
    recorder.start();
    recorderRef.current = recorder;
    setActive(true);

    const flushTranslation = (sourceLang: string) => {
      const text = pendingRef.current.text.trim();
      if (!text) return;
      pendingRef.current.text = '';
      pendingRef.current.lang = undefined;
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
      const config = await createConfig();
      createTranslateClient(config);

      let previousSpeaker: string | undefined;

      await startStreamingTranscription({
        mediaStream,
        options: { language: src, identifyLanguage: src === 'auto' },
        callback: (transcript, isFinal, speaker, identifiedLanguage) => { // NOSONAR - boolean flag is idiomatic for streaming partial/final events
          if (isFinal) {
            const newSpeaker = previousSpeaker === undefined || speaker !== previousSpeaker;
            if (!newSpeaker) {
              // same speaker — transcript is cumulative, handled by pending flush
            }
            previousSpeaker = speaker;
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
  }, [src, tgt]);

  const handleStop = useCallback(() => {
    stopStreamingTranscription();
    recorderRef.current?.stop();
    recorderRef.current = undefined;
    setActive(false);
  }, []);

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
          <div className={styles.idleHint}>Tap mic to begin</div>
        )}
        {error && (
          <div className={styles.errorText}>{error}</div>
        )}
      </div>

      <div className={styles.controls}>
        {active ? (
          <button className={`${styles.btn} ${styles.btnStop}`} onClick={handleStop} aria-label="Stop">
            <StopIcon />
          </button>
        ) : (
          <button className={styles.btn} onClick={handleStart} aria-label="Start mic">
            <MicIcon />
          </button>
        )}
      </div>
    </div>
  );
}
