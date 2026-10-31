import React, { useState, useRef, useEffect, useCallback } from 'react';
import confetti from 'canvas-confetti';
import {
  Sparkles,
  Mic,
  MicOff,
  Upload,
  SlidersHorizontal,
  Volume2,
  VolumeX,
  Wifi,
  SplitSquareHorizontal,
  AlertCircle,
} from 'lucide-react';
import {
  DEFAULT_RAW_ROOM_PHOTO_URL,
  renovateRoomWithNanoBanana,
  speakRenovationConfirmation,
} from './services/geminiService';

interface SpeechRecognitionEvent {
  resultIndex: number;
  results: {
    length: number;
    [index: number]: {
      isFinal: boolean;
      [index: number]: {
        transcript: string;
      };
    };
  };
}

interface SpeechRecognitionInstance {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  start: () => void;
  stop: () => void;
  onresult: ((event: SpeechRecognitionEvent) => void) | null;
  onerror: (() => void) | null;
  onend: (() => void) | null;
}

export function App() {
  // Original Photo (BEFORE - Left of slider) & Nano Banana Photorealistic Output (AFTER - Right of slider)
  const [originalPhotoUrl, setOriginalPhotoUrl] = useState<string>(
    DEFAULT_RAW_ROOM_PHOTO_URL
  );
  const [afterImageUrl, setAfterImageUrl] = useState<string>(
    DEFAULT_RAW_ROOM_PHOTO_URL
  );
  const [isCustomUpload, setIsCustomUpload] = useState<boolean>(false);
  const [isDraggingOver, setIsDraggingOver] = useState<boolean>(false);

  // Reformulated Nano Banana Inpainting Voice Confirmation
  const [, setNanoBananaPrompt] = useState<string>('');
  const [voiceConfirmation, setVoiceConfirmation] = useState<string>(
    'Upload your room photo and dictate or type your renovation instructions. Nano Banana will preserve the exact room geometry while replacing the floor, walls, and furniture.'
  );
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Continuous Voice & Free-Form Text Input state
  const [promptText, setPromptText] = useState<string>('');
  const [isListening, setIsListening] = useState<boolean>(false);
  const [isGenerating, setIsGenerating] = useState<boolean>(false);
  const [isSpeaking, setIsSpeaking] = useState<boolean>(false);
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [modelUsed, setModelUsed] = useState<string>('gemini-2.5-flash-image');
  const [latencyMs, setLatencyMs] = useState<number | null>(null);

  // Full-Screen Split-Screen Before/After Curtain Slider (0% to 100%)
  const [curtainPosition, setCurtainPosition] = useState<number>(50);
  const [isDraggingCurtain, setIsDraggingCurtain] = useState<boolean>(false);

  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const recognitionRef = useRef<SpeechRecognitionInstance | null>(null);
  const comparatorRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (typeof window !== 'undefined' && 'speechSynthesis' in window) {
      window.speechSynthesis.getVoices();
    }
  }, []);

  // Trigger Nano Banana Image-to-Image / Inpainting Renovation
  const handleRenovateSpace = useCallback(
    async (overrideInstruction?: string) => {
      const instruction = (overrideInstruction ?? promptText).trim();
      if (!instruction || !originalPhotoUrl) return;

      setIsGenerating(true);
      setErrorMessage(null);

      try {
        const result = await renovateRoomWithNanoBanana(
          originalPhotoUrl,
          instruction
        );

        setAfterImageUrl(result.renovatedImageUrl);
        setNanoBananaPrompt(result.nanoBananaPrompt);
        setVoiceConfirmation(result.voiceConfirmation);
        setModelUsed(result.modelUsed);
        setLatencyMs(result.latencyMs);
        setIsGenerating(false);

        // Reveal the renovated "AFTER" side clearly while keeping "BEFORE" visible on the left
        setCurtainPosition(35);

        try {
          confetti({
            particleCount: 24,
            spread: 55,
            origin: { x: 0.65, y: 0.85 },
            colors: ['#6366f1', '#38bdf8', '#10b981'],
            disableForReducedMotion: true,
          });
        } catch {
          // Ignore in headless environments
        }

        speakRenovationConfirmation(
          result.voiceConfirmation,
          isMuted,
          () => setIsSpeaking(true),
          () => setIsSpeaking(false)
        );
      } catch (err) {
        setIsGenerating(false);
        setErrorMessage(
          err instanceof Error
            ? err.message
            : 'Failed to generate renovated image with Nano Banana.'
        );
      }
    },
    [promptText, originalPhotoUrl, isMuted]
  );

  // Continuous Voice Dictation via Web Speech API
  const toggleContinuousMicrophone = () => {
    if (isListening) {
      recognitionRef.current?.stop();
      setIsListening(false);
      if (promptText.trim()) {
        handleRenovateSpace(promptText);
      }
      return;
    }

    const SpeechRecognitionConstructor =
      (window as unknown as Record<string, unknown>).SpeechRecognition ||
      (window as unknown as Record<string, unknown>).webkitSpeechRecognition;

    if (!SpeechRecognitionConstructor) {
      const simulatedVoice =
        'Keep the perspective, window and arches of this room, replace the floor with solid oak herringbone parquet, repaint all walls in clean mineral plaster, and add a sofa and coffee table in the same angle';
      setPromptText(simulatedVoice);
      handleRenovateSpace(simulatedVoice);
      return;
    }

    try {
      const recognition = new (SpeechRecognitionConstructor as new () => SpeechRecognitionInstance)();
      recognition.lang = 'en-US';
      recognition.interimResults = true;
      recognition.continuous = true;

      recognition.onresult = (event: SpeechRecognitionEvent) => {
        let transcript = '';
        for (let i = 0; i < event.results.length; i++) {
          transcript += event.results[i][0].transcript;
        }
        if (transcript.trim()) {
          setPromptText(transcript.trim());
        }
      };

      recognition.onerror = () => setIsListening(false);
      recognition.onend = () => setIsListening(false);

      recognitionRef.current = recognition;
      setIsListening(true);
      recognition.start();
    } catch {
      setIsListening(false);
    }
  };

  // Upload Original Room Photo ("Uploaded Site Photo")
  const handleFileUpload = (file: File) => {
    if (!file.type.startsWith('image/')) return;
    const reader = new FileReader();
    reader.onloadend = () => {
      const base64DataUrl = reader.result as string;
      setOriginalPhotoUrl(base64DataUrl);
      setAfterImageUrl(base64DataUrl);
      setIsCustomUpload(true);
      setErrorMessage(null);
      setCurtainPosition(50);
    };
    reader.readAsDataURL(file);
  };

  const handleDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    setIsDraggingOver(false);
    const file = e.dataTransfer.files?.[0];
    if (file) handleFileUpload(file);
  };

  // Interactive Full-Screen Curtain Dragging (Mouse & Touch)
  const updateCurtainFromClientX = useCallback((clientX: number) => {
    if (!comparatorRef.current) return;
    const rect = comparatorRef.current.getBoundingClientRect();
    const percentage = ((clientX - rect.left) / rect.width) * 100;
    setCurtainPosition(Math.max(2, Math.min(98, Math.round(percentage))));
  }, []);

  useEffect(() => {
    if (!isDraggingCurtain) return;
    const handleMouseMove = (e: MouseEvent) =>
      updateCurtainFromClientX(e.clientX);
    const handleTouchMove = (e: TouchEvent) => {
      if (e.touches[0]) updateCurtainFromClientX(e.touches[0].clientX);
    };
    const handleUp = () => setIsDraggingCurtain(false);

    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('touchmove', handleTouchMove);
    window.addEventListener('mouseup', handleUp);
    window.addEventListener('touchend', handleUp);
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('touchmove', handleTouchMove);
      window.removeEventListener('mouseup', handleUp);
      window.removeEventListener('touchend', handleUp);
    };
  }, [isDraggingCurtain, updateCurtainFromClientX]);

  return (
    <div className="flex h-screen w-screen flex-col bg-slate-950 text-slate-100 select-none overflow-hidden">
      {/* ================= HEADER ================= */}
      <header className="flex h-16 shrink-0 items-center justify-between border-b border-slate-800/80 bg-slate-950/90 px-6 backdrop-blur-xl z-30">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-indigo-500 via-indigo-600 to-cyan-500 shadow-lg shadow-indigo-500/25">
            <SplitSquareHorizontal className="h-5 w-5 text-white" />
          </div>
          <div>
            <div className="flex items-center gap-2.5">
              <h1 className="text-lg font-bold tracking-tight text-white">
                AuraSpace <span className="text-indigo-400">Studio</span>
              </h1>
              <span className="inline-flex items-center gap-1.5 rounded-full border border-indigo-500/30 bg-indigo-500/10 px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider text-indigo-300">
                <span className="h-1.5 w-1.5 rounded-full bg-indigo-400 animate-ping" />
                Nano Banana Image-to-Image Inpainting
              </span>
            </div>
            <p className="text-[11px] text-slate-400">
              Structural Perspective Preservation • Natural Surface Replacement & Renovation
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={() => {
              setIsMuted((m) => {
                if (!m && 'speechSynthesis' in window) {
                  window.speechSynthesis.cancel();
                  setIsSpeaking(false);
                }
                return !m;
              });
            }}
            className={`flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-xs font-medium transition ${
              !isMuted
                ? 'border-emerald-500/40 bg-emerald-500/10 text-emerald-300'
                : 'border-slate-800 bg-slate-900/60 text-slate-400'
            }`}
          >
            {isMuted ? (
              <VolumeX className="h-3.5 w-3.5" />
            ) : (
              <Volume2 className="h-3.5 w-3.5" />
            )}
            <span>{isMuted ? 'Voice Muted' : 'Voice Confirmation ON'}</span>
          </button>

          <div className="flex items-center gap-2 rounded-full border border-emerald-500/30 bg-slate-900/90 px-3.5 py-1.5 text-xs">
            <Wifi className="h-3.5 w-3.5 text-emerald-400" />
            <span className="font-medium text-slate-200">
              Nano Banana ({modelUsed})
            </span>
            {latencyMs !== null && (
              <span className="rounded bg-emerald-500/20 px-1.5 py-0.5 text-[10px] font-semibold text-emerald-300">
                {(latencyMs / 1000).toFixed(1)}s
              </span>
            )}
          </div>
        </div>
      </header>

      {/* ================= MAIN WORKSPACE ================= */}
      <div className="flex flex-1 overflow-hidden">
        {/* -------- LEFT SIDEBAR (UPLOADED SITE PHOTO, CONTINUOUS MIC, TEXT, RENOVATE SPACE) -------- */}
        <aside className="flex w-[380px] shrink-0 flex-col justify-between border-r border-slate-800/80 bg-slate-900/65 p-5 overflow-y-auto backdrop-blur-xl z-20 gap-5">
          <div className="space-y-5">
            {/* 1. Uploaded Site Photo Import */}
            <div>
              <label className="mb-2 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-300">
                <Upload className="h-3.5 w-3.5 text-indigo-400" />
                Uploaded Site Photo (BEFORE Reference)
              </label>

              <div
                onDragOver={(e) => {
                  e.preventDefault();
                  setIsDraggingOver(true);
                }}
                onDragLeave={() => setIsDraggingOver(false)}
                onDrop={handleDrop}
                onClick={() => fileInputRef.current?.click()}
                className={`group relative cursor-pointer overflow-hidden rounded-xl border-2 border-dashed transition ${
                  isDraggingOver
                    ? 'border-indigo-400 bg-indigo-500/15'
                    : 'border-slate-700/80 bg-slate-950/60 hover:border-indigo-500/60'
                }`}
              >
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) handleFileUpload(file);
                  }}
                />
                {originalPhotoUrl && (
                  <div className="relative aspect-[16/10] w-full overflow-hidden bg-slate-950">
                    <img
                      src={originalPhotoUrl}
                      alt="Uploaded Site Photo"
                      className="h-full w-full object-cover opacity-90 transition duration-300 group-hover:scale-105"
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-slate-950/90 via-slate-950/25 to-transparent flex flex-col justify-end p-3">
                      <div className="flex items-center justify-between">
                        <span className="text-xs font-semibold text-white">
                          {isCustomUpload
                            ? 'Uploaded Site Photo (Active Input)'
                            : 'Default Room Photo'}
                        </span>
                        <span className="rounded-lg bg-indigo-600/90 px-2.5 py-1 text-[11px] font-semibold text-white shadow">
                          Upload Photo
                        </span>
                      </div>
                      <p className="text-[11px] text-slate-300 mt-0.5">
                        Sent directly as `inlineData` to Nano Banana Image-to-Image
                      </p>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* 2. Continuous Voice Microphone & Free-Form Text Input */}
            <div className="rounded-2xl border border-slate-800/90 bg-slate-950/70 p-4 space-y-3.5">
              <div className="flex items-center justify-between">
                <label className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-200">
                  <Mic className="h-3.5 w-3.5 text-indigo-400" />
                  Renovation & Replacement Brief
                </label>
                {isListening && (
                  <span className="inline-flex items-center gap-1.5 rounded-full bg-rose-500/20 px-2.5 py-0.5 text-[11px] font-semibold text-rose-300 border border-rose-500/40">
                    <span className="h-2 w-2 rounded-full bg-rose-500 animate-ping" />
                    Listening...
                  </span>
                )}
              </div>

              {/* Continuous Voice Dictation Button */}
              <button
                type="button"
                onClick={toggleContinuousMicrophone}
                className={`flex w-full items-center justify-center gap-2.5 rounded-xl border px-4 py-3 text-xs font-semibold transition shadow-lg ${
                  isListening
                    ? 'border-rose-500 bg-rose-500/25 text-rose-100 shadow-rose-500/20 animate-pulse'
                    : 'border-indigo-500/40 bg-slate-900 text-slate-100 hover:border-indigo-500 hover:bg-slate-800/90'
                }`}
              >
                {isListening ? (
                  <>
                    <MicOff className="h-4 w-4 text-rose-400 animate-bounce" />
                    <span>Stop Voice & Renovate Space</span>
                  </>
                ) : (
                  <>
                    <Mic className="h-4 w-4 text-indigo-400" />
                    <span>Dictate Renovation (Continuous Mic)</span>
                  </>
                )}
              </button>

              {/* Free-Form Text Field & RENOVATE SPACE Button */}
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  handleRenovateSpace();
                }}
                className="space-y-3"
              >
                <textarea
                  rows={4}
                  value={promptText}
                  onChange={(e) => setPromptText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && !e.shiftKey) {
                      e.preventDefault();
                      handleRenovateSpace();
                    }
                  }}
                  placeholder="Ex: Conserve la perspective, la fenêtre et les arches, mais remplace le sol par un parquet chevron en chêne, repeins les murs en enduit minéral beige et ajoute un canapé et une table..."
                  className="w-full resize-none rounded-xl border border-slate-700/80 bg-slate-900/90 p-3 text-xs text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />

                <button
                  type="submit"
                  disabled={isGenerating || !promptText.trim()}
                  className="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-indigo-600 to-cyan-600 py-3.5 text-xs font-bold uppercase tracking-wider text-white shadow-lg shadow-indigo-600/25 transition hover:from-indigo-500 hover:to-cyan-500 disabled:opacity-40"
                >
                  <Sparkles className="h-4 w-4" />
                  <span>
                    {isGenerating
                      ? 'NANO BANANA RENOVATING...'
                      : 'RENOVATE SPACE'}
                  </span>
                </button>
              </form>

              {errorMessage && (
                <div className="flex items-start gap-2 rounded-xl border border-rose-500/40 bg-rose-500/10 p-3 text-xs text-rose-200">
                  <AlertCircle className="h-4 w-4 shrink-0 text-rose-400 mt-0.5" />
                  <span>{errorMessage}</span>
                </div>
              )}
            </div>

            {/* 3. Split-Screen Curtain Slider Control */}
            <div className="rounded-2xl border border-slate-800/90 bg-slate-950/70 p-4 space-y-2.5">
              <div className="flex items-center justify-between">
                <label className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-slate-200">
                  <SlidersHorizontal className="h-3.5 w-3.5 text-cyan-400" />
                  Before / After Curtain
                </label>
                <span className="text-[11px] font-semibold text-indigo-300">
                  {curtainPosition}% Before / {100 - curtainPosition}% After
                </span>
              </div>
              <input
                type="range"
                min={2}
                max={98}
                value={curtainPosition}
                onChange={(e) => setCurtainPosition(Number(e.target.value))}
                className="h-1.5 w-full cursor-pointer appearance-none rounded-lg bg-slate-800 accent-indigo-500"
              />
              <div className="flex justify-between text-[10px] text-slate-400">
                <span>← Left: Uploaded Site Photo</span>
                <span>Right: Nano Banana Output →</span>
              </div>
            </div>
          </div>
        </aside>

        {/* -------- CENTRAL FULL-SCREEN 2D SPLIT-SCREEN BEFORE / AFTER COMPARATOR -------- */}
        <main
          ref={comparatorRef}
          onMouseDown={(e) => updateCurtainFromClientX(e.clientX)}
          className="relative flex-1 overflow-hidden bg-slate-950 cursor-ew-resize"
        >
          {/* LEFT OF SLIDER: Original Uploaded Site Photo ("BEFORE") */}
          {originalPhotoUrl && (
            <div
              className="pointer-events-none absolute inset-0 flex items-center justify-center overflow-hidden p-4"
              style={{
                clipPath: `inset(0 ${100 - curtainPosition}% 0 0)`,
              }}
            >
              <img
                src={originalPhotoUrl}
                alt="BEFORE - Original Uploaded Room Photo"
                className="max-h-full max-w-full h-full w-full object-contain object-center"
                draggable={false}
              />
            </div>
          )}

          {/* RIGHT OF SLIDER: Direct Photorealistic Nano Banana Output ("AFTER") */}
          {afterImageUrl && (
            <div
              className="pointer-events-none absolute inset-0 flex items-center justify-center overflow-hidden p-4"
              style={{
                clipPath: `inset(0 0 0 ${curtainPosition}%)`,
              }}
            >
              <img
                src={afterImageUrl}
                alt="AFTER - Photorealistic Nano Banana Renovated Room"
                className="max-h-full max-w-full h-full w-full object-contain object-center"
                draggable={false}
              />
            </div>
          )}

          {/* BEFORE & AFTER Corner Badges */}
          <div className="pointer-events-none absolute top-4 left-4 z-20 rounded-full bg-slate-950/85 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-slate-200 border border-slate-700/80 backdrop-blur-md shadow-lg">
            BEFORE • Original Photo
          </div>
          <div className="pointer-events-none absolute top-4 right-4 z-20 rounded-full bg-indigo-950/90 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-indigo-200 border border-indigo-500/50 backdrop-blur-md shadow-lg">
            AFTER • Nano Banana Photorealistic Renovation
          </div>

          {/* Interactive Sliding Curtain Divider & Handle */}
          <div
            style={{ left: `${curtainPosition}%` }}
            className="pointer-events-none absolute inset-y-0 z-20 w-0.5 bg-gradient-to-b from-indigo-400 via-white to-cyan-400 shadow-[0_0_20px_rgba(99,102,241,0.95)]"
          >
            <div
              onMouseDown={(e) => {
                e.stopPropagation();
                setIsDraggingCurtain(true);
              }}
              onTouchStart={(e) => {
                e.stopPropagation();
                setIsDraggingCurtain(true);
              }}
              className="pointer-events-auto absolute top-1/2 -translate-x-1/2 -translate-y-1/2 flex h-12 w-12 cursor-ew-resize items-center justify-center rounded-full border-2 border-white bg-indigo-600 text-white shadow-2xl transition transform hover:scale-110"
              title="Slide left or right to compare BEFORE and AFTER"
            >
              <SlidersHorizontal className="h-5 w-5" />
            </div>
          </div>

          {/* Loading Overlay during Nano Banana Image-to-Image Generation */}
          {isGenerating && (
            <div className="pointer-events-none absolute inset-0 z-30 flex flex-col items-center justify-center bg-slate-950/65 backdrop-blur-sm">
              <div className="flex flex-col items-center gap-3 rounded-2xl border border-indigo-500/40 bg-slate-900/95 px-6 py-5 shadow-2xl max-w-md text-center">
                <div className="relative flex h-12 w-12 items-center justify-center">
                  <span className="absolute inset-0 rounded-full border-2 border-indigo-500 border-t-transparent animate-spin" />
                  <Sparkles className="h-5 w-5 text-indigo-400 animate-pulse" />
                </div>
                <p className="text-sm font-semibold text-white">
                  Nano Banana Image-to-Image Renovation in Progress...
                </p>
                <p className="text-xs text-slate-400">
                  Preserving exact room perspective, windows & arches while replacing surfaces & integrating furniture
                </p>
              </div>
            </div>
          )}

          {/* Bottom Voice Confirmation Banner */}
          <div
            onMouseDown={(e) => e.stopPropagation()}
            className="pointer-events-none absolute bottom-5 left-1/2 z-20 w-full max-w-2xl -translate-x-1/2 px-4 cursor-default"
          >
            <div className="pointer-events-auto flex items-center justify-between gap-4 rounded-2xl border border-slate-700/80 bg-slate-950/90 px-5 py-3.5 shadow-2xl backdrop-blur-xl">
              <div className="flex items-center gap-3.5">
                <button
                  onClick={() =>
                    speakRenovationConfirmation(
                      voiceConfirmation,
                      false,
                      () => setIsSpeaking(true),
                      () => setIsSpeaking(false)
                    )
                  }
                  className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border transition ${
                    isSpeaking
                      ? 'border-indigo-400 bg-indigo-500/25 text-indigo-300 shadow-lg shadow-indigo-500/30'
                      : 'border-slate-700 bg-slate-900 text-indigo-400 hover:border-indigo-500/60'
                  }`}
                  title="Replay Voice Confirmation"
                >
                  <Volume2 className={`h-5 w-5 ${isSpeaking ? 'animate-pulse' : ''}`} />
                </button>
                <div>
                  <div className="flex items-center gap-2">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-indigo-400">
                      AI Voice Confirmation
                    </span>
                    {isSpeaking && (
                      <span className="inline-flex items-center gap-0.5">
                        <span className="h-2.5 w-0.5 bg-indigo-400 animate-pulse" />
                        <span className="h-3.5 w-0.5 bg-cyan-400 animate-pulse" />
                        <span className="h-2 w-0.5 bg-indigo-400 animate-pulse" />
                      </span>
                    )}
                  </div>
                  <p className="text-xs font-medium text-slate-100 leading-relaxed">
                    "{voiceConfirmation}"
                  </p>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}

export default App;
