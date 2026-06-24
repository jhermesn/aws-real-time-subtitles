import { TranslateClient, TranslateTextCommand } from "@aws-sdk/client-translate";
import { ClientConfig } from "./transcribe";

let translateClient: TranslateClient | null = null;

export const translateLanguageOptions = [
  "af","sq","am","ar","hy","az","bn","bs","bg","ca","zh","zh-TW","hr","cs","da","fa-AF",
  "nl","en","et","fa","tl","fi","fr","fr-CA","ka","de","el","gu","ht","ha","he","hi",
  "hu","is","id","ga","it","ja","kn","kk","ko","lv","lt","mk","ms","ml","mt","mr","mn",
  "no","ps","pl","pt","pt-PT","pa","ro","ru","sr","si","sk","sl","so","es","es-MX","sw",
  "sv","ta","te","th","tr","uk","ur","uz","vi","cy",
].map(lang => ({ label: lang, value: lang }));

export const createTranslateClient = (config: ClientConfig): void => {
  translateClient = new TranslateClient(config);
};

export const translateText = async (
  text: string,
  sourceLang: string,
  targetLang: string
): Promise<string> => {
  const command = new TranslateTextCommand({
    Text: text,
    SourceLanguageCode: sourceLang,
    TargetLanguageCode: targetLang,
  });
  if (!translateClient) throw new Error('translateClient not initialised, call createTranslateClient first');
  const response = await translateClient.send(command);
  return response.TranslatedText ?? "";
};
