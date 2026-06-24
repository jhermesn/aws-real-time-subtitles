import { useState, useEffect, useCallback, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { createConfig, startStreamingTranscription, stopStreamingTranscription } from '../lib/transcribe';
import { createTranslateClient, translateText } from '../lib/translate';
import styles from './SpeakerView.module.css';

type SubtitleState = {
  final: string;
  partial: string;
};

export default function SpeakerView() {
  const [params] = useSearchParams();
  const src = params.get('src') ?? 'en-US';
  const tgt = params.get('tgt') ?? 'pt';
  const room = params.get('room') ?? '';

  const [active, setActive] = useState(false);
  const [subtitles, setSubtitles] = useState<SubtitleState>({ final: '', partial: '' });
  const [error, setError] = useState<string | null>(null);
  const [panelOpen, setPanelOpen] = useState(false);
  const [rawTranscription, setRawTranscription] = useState<string[]>([]);

  const recorderRef = useRef<MediaRecorder | undefined>(undefined);
  const pendingRef = useRef<{
    text: string;
    lang: string | undefined;
    timer: ReturnType<typeof setTimeout> | null;
  }>({ text: '', lang: undefined, timer: null });

  const handleStart = useCallback(async () => {
    setError(null);
    setSubtitles({ final: '', partial: '' });
    setRawTranscription([]);
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
      let transcriptionLines: string[] = [];

      await startStreamingTranscription({
        mediaStream,
        options: { language: src, identifyLanguage: src === 'auto' },
        callback: (transcript, isFinal, speaker, identifiedLanguage) => {
          if (isFinal) {
            const newSpeaker = previousSpeaker === undefined || speaker !== previousSpeaker;
            if (newSpeaker) {
              transcriptionLines.push(transcript);
              previousSpeaker = speaker;
            } else {
              transcriptionLines[transcriptionLines.length - 1] += transcript;
            }
            setRawTranscription([...transcriptionLines]);
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
      <span className={styles.watermark}>aws · subtitles</span>

      <div className={styles.overlay}>
        {subtitles.final && (
          <div key={subtitles.final} className={styles.finalText}>{subtitles.final}</div>
        )}
        {subtitles.partial && (
          <div className={styles.partialText}>{subtitles.partial}</div>
        )}
        {(showIdleHint) && (
          <div className={styles.idleHint}>Press Start mic to begin</div>
        )}
        {error && (
          <div className={styles.errorText}>{error}</div>
        )}
      </div>

      <div className={styles.controls}>
        {!active ? (
          <button className={styles.btn} onClick={handleStart}>▶ Start mic</button>
        ) : (
          <button className={`${styles.btn} ${styles.btnStop}`} onClick={handleStop}>■ Stop</button>
        )}
        <button className={styles.btnPanel} onClick={() => setPanelOpen(o => !o)}>
          {panelOpen ? '✕ Close' : '☰ Info'}
        </button>
      </div>

      {panelOpen && (
        <div className={styles.panel}>
          <div className={styles.panelRow}><b>Room:</b> {room || '-'}</div>
          <div className={styles.panelRow}><b>Lang:</b> {src} → {tgt}</div>
          <div className={styles.panelDivider} />
          <div className={styles.panelLabel}>Raw transcription</div>
          <div className={styles.panelScroll}>
            {rawTranscription.map((line, i) => (
              <div key={`${i}-${line.slice(0, 12)}`} className={styles.panelLine}>{line}</div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
