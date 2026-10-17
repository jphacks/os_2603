import { useEffect, useRef, useState } from "react";

// Web Speech API による音声入力（メモを声で入れる）。
// iOS Safari でも Chrome でも動く場面と動かない場面があるため、
// 非対応時は isSupported=false を返し、UIは手入力にフォールバックする。

type SR = typeof window extends { SpeechRecognition: infer T } ? T : any;

function getRecognition(): any {
  const w = window as any;
  const Ctor = w.SpeechRecognition || w.webkitSpeechRecognition;
  return Ctor ? new Ctor() : null;
}

export function useSpeech(onResult: (text: string) => void) {
  const [listening, setListening] = useState(false);
  const [isSupported] = useState(() => {
    const w = window as any;
    return !!(w.SpeechRecognition || w.webkitSpeechRecognition);
  });
  const recRef = useRef<any>(null);
  const cbRef = useRef(onResult);
  cbRef.current = onResult;

  useEffect(() => {
    return () => {
      try {
        recRef.current?.stop();
      } catch {
        /* noop */
      }
    };
  }, []);

  const start = () => {
    if (!isSupported || listening) return;
    const rec = getRecognition();
    if (!rec) return;
    rec.lang = "ja-JP";
    rec.interimResults = true;
    rec.continuous = false;
    let finalText = "";
    rec.onresult = (e: any) => {
      let interim = "";
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const t = e.results[i][0].transcript;
        if (e.results[i].isFinal) finalText += t;
        else interim += t;
      }
      cbRef.current((finalText + interim).trim());
    };
    rec.onend = () => setListening(false);
    rec.onerror = () => setListening(false);
    recRef.current = rec;
    setListening(true);
    rec.start();
  };

  const stop = () => {
    try {
      recRef.current?.stop();
    } catch {
      /* noop */
    }
    setListening(false);
  };

  return { listening, isSupported, start, stop };
}
