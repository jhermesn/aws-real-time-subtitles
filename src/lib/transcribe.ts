import { TranscribeStreamingClient, StartStreamTranscriptionCommand } from "@aws-sdk/client-transcribe-streaming";
import { fromCognitoIdentityPool } from "@aws-sdk/credential-providers";
import mic from "microphone-stream";
import appConfig from '../config';
import { Buffer } from 'buffer';

const languagesTranscribe = ["en-US","en-GB","es-US","fr-CA","fr-FR","en-AU","it-IT","de-DE","pt-BR","ja-JP","ko-KR","zh-CN","th-TH","es-ES","ar-SA","pt-PT","ca-ES","ar-AE","hi-IN","zh-HK","nl-NL","no-NO","sv-SE","pl-PL","fi-FI","zh-TW","en-IN","en-IE","en-NZ","en-AB","en-ZA","en-WL","de-CH","af-ZA","eu-ES","hr-HR","cs-CZ","da-DK","fa-IR","gl-ES","el-GR","he-IL","id-ID","lv-LV","ms-MY","ro-RO","ru-RU","sr-RS","sk-SK","so-SO","tl-PH","uk-UA","vi-VN","zu-ZA"];
const identifyLanguagesOptions = ["en-US","es-US","fr-FR","it-IT","de-DE","pt-BR","ja-JP","ko-KR","zh-CN","hi-IN","th-TH"];

export const automaticLanguage = "auto";
export const transcribeLanguageOptions = [automaticLanguage, ...languagesTranscribe].map(lang => ({ label: lang, value: lang }));

export type ClientConfig = {
  region: string;
  credentials: ReturnType<typeof fromCognitoIdentityPool>;
};

let clientConfig: ClientConfig | undefined;
let activeMicStream: InstanceType<typeof mic> | undefined;

export const createConfig = async (): Promise<ClientConfig> => {
  clientConfig = {
    region: appConfig.aws_region,
    credentials: fromCognitoIdentityPool({
      clientConfig: { region: appConfig.aws_region },
      identityPoolId: appConfig.cognito_identity_pool_id,
    }),
  };
  return clientConfig;
};

const encodePCMChunk = (chunk: Buffer): Buffer => {
  const input = mic.toRaw(chunk);
  let offset = 0;
  const buffer = new ArrayBuffer(input.length * 2);
  const view = new DataView(buffer);
  for (let i = 0; i < input.length; i++, offset += 2) {
    const s = Math.max(-1, Math.min(1, input[i]));
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  }
  return Buffer.from(buffer);
};

export type TranscribeCallback = ( // NOSONAR - boolean flag is idiomatic for streaming partial/final events
  transcript: string,
  isFinal: boolean,
  speaker: string | undefined,
  identifiedLanguage: string | undefined
) => void;

export const startStreamingTranscription = async ({
  mediaStream,
  callback,
  options,
}: {
  mediaStream: MediaStream;
  callback: TranscribeCallback;
  options: { language: string; identifyLanguage: boolean };
}): Promise<void> => {
  activeMicStream = new mic();
  const { language, identifyLanguage } = options;

  activeMicStream.setStream(mediaStream);

  if (!clientConfig) throw new Error('clientConfig not initialised, call createConfig first');
  const transcribeClient = new TranscribeStreamingClient(clientConfig);

  const getAudioStream = async function* () {
    for await (const chunk of activeMicStream as AsyncIterable<Buffer>) {
      if (chunk.length <= 44100) {
        yield { AudioEvent: { AudioChunk: encodePCMChunk(chunk) } };
      }
    }
  };

  const command = new StartStreamTranscriptionCommand({
    ...(identifyLanguage === true
      ? { IdentifyLanguage: true, LanguageOptions: identifyLanguagesOptions.join() }
      : { LanguageCode: language }),
    MediaEncoding: "pcm",
    MediaSampleRateHertz: 44100,
    AudioStream: getAudioStream(),
    ShowSpeakerLabel: true,
  });

  const data = await transcribeClient.send(command);
  for await (const event of data.TranscriptResultStream!) {
    const results = event.TranscriptEvent?.Transcript?.Results;
    if (results?.length) {
      const newTranscript = results[0].Alternatives?.[0]?.Transcript ?? "";
      const final = !results[0].IsPartial;
      const speaker = results[0].Alternatives?.[0]?.Items?.[0]?.Speaker ?? undefined;
      const identifiedLang = identifyLanguage && final ? results[0].LanguageCode : undefined;
      callback(newTranscript + " ", final, speaker, identifiedLang);
    }
  }
};

export const stopStreamingTranscription = (): void => {
  if (activeMicStream) {
    activeMicStream.stop();
    activeMicStream.destroy();
    activeMicStream = undefined;
  }
};
