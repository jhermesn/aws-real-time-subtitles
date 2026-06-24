import { useState } from 'react';
import { SpaceBetween, Container, Header, Button, Box, Select, FormField, Input, Alert } from '@cloudscape-design/components';
import { transcribeLanguageOptions } from '../lib/transcribe';
import { translateLanguageOptions } from '../lib/translate';

type Room = {
  label: string;
  src: string;
  tgt: string;
  speakerUrl: string;
};

async function createRoom(label: string, src: string, tgt: string): Promise<string> {
  const res = await fetch('/api/sign-room', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ src, tgt, room: label }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({})) as { error?: string };
    throw new Error(err.error ?? `HTTP ${res.status}`);
  }
  const { token } = await res.json() as { token: string };
  const params = new URLSearchParams({ token, src, tgt, room: label });
  return `${window.location.origin}/speaker?${params}`;
}

export default function AdminView() {
  const [label, setLabel] = useState('');
  const [src, setSrc] = useState('en-US');
  const [tgt, setTgt] = useState('pt');
  const [rooms, setRooms] = useState<Room[]>([]);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);

  const handleCreate = async () => {
    if (!label.trim()) return;
    setCreating(true);
    setError(null);
    try {
      const speakerUrl = await createRoom(label.trim(), src, tgt);
      setRooms(prev => [...prev, { label: label.trim(), src, tgt, speakerUrl }]);
      setLabel('');
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setCreating(false);
    }
  };

  const handleCopy = (url: string) => {
    navigator.clipboard.writeText(url).then(() => {
      setCopied(url);
      setTimeout(() => setCopied(null), 2000);
    });
  };

  return (
    <SpaceBetween size="l" direction="vertical">
      <Container header={<Header variant="h2">Create room</Header>}>
        <SpaceBetween size="m" direction="vertical">
          <FormField label="Room label">
            <Input
              value={label}
              onChange={({ detail }) => setLabel(detail.value)}
              placeholder="e.g. Keynote (EN to PT)"
              disabled={creating}
            />
          </FormField>
          <SpaceBetween size="m" direction="horizontal">
            <FormField label="Speaker language">
              <Select
                selectedOption={{ label: src, value: src }}
                onChange={({ detail }) => setSrc(detail.selectedOption.value ?? 'en-US')}
                options={transcribeLanguageOptions}
                disabled={creating}
              />
            </FormField>
            <FormField label="Subtitle language">
              <Select
                selectedOption={{ label: tgt, value: tgt }}
                onChange={({ detail }) => setTgt(detail.selectedOption.value ?? 'pt')}
                options={translateLanguageOptions}
                disabled={creating}
              />
            </FormField>
          </SpaceBetween>
          {error && <Alert type="error">{error}</Alert>}
          <Button variant="primary" onClick={handleCreate} loading={creating} disabled={!label.trim()}>
            Generate speaker URL
          </Button>
        </SpaceBetween>
      </Container>

      {rooms.length > 0 && (
        <Container header={<Header variant="h2">Active rooms ({rooms.length})</Header>}>
          <SpaceBetween size="m" direction="vertical">
            {rooms.map((room, i) => (
              <Box key={i}>
                <SpaceBetween size="xs" direction="vertical">
                  <Box fontWeight="bold">{room.label}</Box>
                  <Box color="text-body-secondary" fontSize="body-s">
                    {room.src} → {room.tgt}
                  </Box>
                  <SpaceBetween size="s" direction="horizontal">
                    <Box fontSize="body-s" color="text-status-info">
                      <code style={{ wordBreak: 'break-all' }}>{room.speakerUrl}</code>
                    </Box>
                    <Button
                      variant="inline-link"
                      onClick={() => handleCopy(room.speakerUrl)}
                    >
                      {copied === room.speakerUrl ? 'Copied!' : 'Copy'}
                    </Button>
                  </SpaceBetween>
                </SpaceBetween>
              </Box>
            ))}
          </SpaceBetween>
        </Container>
      )}
    </SpaceBetween>
  );
}
