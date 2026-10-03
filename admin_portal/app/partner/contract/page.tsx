'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Camera, CheckCircle2, Circle, Loader2, Square, Video } from 'lucide-react';

import { ContractText } from '../../components/contract-text';
import { Badge, Empty, ErrorBox, Loading } from '../../components/ui';
import {
  money,
  partnerFetch,
  readPartnerSession,
  signContract,
  when,
} from '../../lib/partner-api';
import { PartnerShell } from '../partner-shell';

type Contract = {
  id: string;
  reference: string;
  status: string;
  renderedText: string;
  videoScript: string;
  securityDeposit: number;
  commissionSharePct: number;
  termMonths: number;
  sentAt?: string | null;
  signedAt?: string | null;
  endsAt?: string | null;
};

const MAX_SECONDS = 60;

/** The first recording container the browser will actually produce. */
function pickMimeType(): string | undefined {
  if (typeof MediaRecorder === 'undefined') return undefined;
  const candidates = [
    'video/webm;codecs=vp8,opus',
    'video/webm',
    'video/mp4',
  ];
  return candidates.find((type) => MediaRecorder.isTypeSupported(type));
}

/**
 * Read the contract, then sign it: a live photograph and a video of the words on
 * screen.
 *
 * **The camera is opened with `getUserMedia` and the photograph is taken from that
 * live stream onto a canvas.** It is not a file input. A file input — even with
 * `capture="user"` — falls back to the gallery on desktop and on some Android
 * builds, and a photograph chosen from a gallery proves nothing at all about who
 * was sitting there. Here there is no path to a stored file: if the camera does
 * not open, the page says so and signing cannot proceed.
 *
 * **The words are fixed and shown on screen.** One sentence, read in every
 * partner's own voice, is evidence that can be compared with the contract and with
 * the other videos. A hundred people each saying it their own way is a hundred
 * recordings that cannot be compared with anything, which is why the script is not
 * a suggestion.
 *
 * What the server adds, and this page never sends: the time (its own clock, not
 * the phone's), the IP, and the phone number OTP already proved at sign-in.
 */
export default function Page() {
  const router = useRouter();

  const [contract, setContract] = useState<Contract | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState('');

  const [readIt, setReadIt] = useState(false);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [cameraOn, setCameraOn] = useState(false);
  const [cameraError, setCameraError] = useState('');

  const [selfie, setSelfie] = useState<Blob | null>(null);
  const [selfieUrl, setSelfieUrl] = useState('');

  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [clip, setClip] = useState<Blob | null>(null);
  const [clipUrl, setClipUrl] = useState('');

  const load = useCallback(async () => {
    setContract(await partnerFetch<Contract>('/api/v1/partner/contract'));
  }, []);

  useEffect(() => {
    if (!readPartnerSession()) {
      router.replace('/partner/login');
      return;
    }

    setLoading(true);
    void load()
      .catch((e) =>
        setError(e instanceof Error ? e.message : 'Your contract is not ready yet.'),
      )
      .finally(() => setLoading(false));
  }, [load, router]);

  // Everything the camera holds is released when the page goes away: the stream,
  // the interval, and the two blob URLs. A camera light left on after navigating
  // away is alarming, and reasonably so.
  useEffect(
    () => () => {
      streamRef.current?.getTracks().forEach((track) => track.stop());
      if (timerRef.current) clearInterval(timerRef.current);
      if (selfieUrl) URL.revokeObjectURL(selfieUrl);
      if (clipUrl) URL.revokeObjectURL(clipUrl);
    },
    [selfieUrl, clipUrl],
  );

  const startCamera = async () => {
    setCameraError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: { ideal: 1280 } },
        audio: true,
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play().catch(() => undefined);
      }
      setCameraOn(true);
    } catch {
      // Named plainly rather than "something went wrong": the two real causes
      // are a refused permission and a browser with no camera access at all,
      // and the person can act on either one.
      setCameraError(
        'The camera did not open. Allow camera and microphone access for this page, '
          + 'and open it on a phone or a laptop with a camera. A photograph from your '
          + 'gallery cannot be used for a signature.',
      );
      setCameraOn(false);
    }
  };

  const takeSelfie = () => {
    const video = videoRef.current;
    if (!video || !video.videoWidth) return;

    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext('2d');
    if (!context) return;

    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    canvas.toBlob(
      (blob) => {
        if (!blob) return;
        if (selfieUrl) URL.revokeObjectURL(selfieUrl);
        setSelfie(blob);
        setSelfieUrl(URL.createObjectURL(blob));
      },
      'image/jpeg',
      0.9,
    );
  };

  const stopRecording = () => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
    if (recorderRef.current?.state === 'recording') {
      recorderRef.current.stop();
    }
    setRecording(false);
  };

  const startRecording = () => {
    const stream = streamRef.current;
    if (!stream) return;

    const mimeType = pickMimeType();
    if (!mimeType) {
      setCameraError(
        'This browser cannot record video. Please open the partner portal in Chrome.',
      );
      return;
    }

    chunksRef.current = [];
    const recorder = new MediaRecorder(stream, { mimeType });
    recorder.ondataavailable = (event) => {
      if (event.data.size > 0) chunksRef.current.push(event.data);
    };
    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: mimeType });
      if (clipUrl) URL.revokeObjectURL(clipUrl);
      setClip(blob);
      setClipUrl(URL.createObjectURL(blob));
    };

    recorder.start();
    recorderRef.current = recorder;
    setRecording(true);
    setSeconds(0);

    timerRef.current = setInterval(() => {
      setSeconds((value) => {
        // Stopped by the clock as well as by the button. A recording left running
        // becomes a file too large to upload, and the person finds that out only
        // after reading the whole thing aloud.
        if (value + 1 >= MAX_SECONDS) {
          stopRecording();
          return MAX_SECONDS;
        }
        return value + 1;
      });
    }, 1000);
  };


  const submit = async () => {
    if (!selfie || !clip) return;
    setBusy(true);
    setError('');
    try {
      const result = await signContract(
        selfie,
        clip,
        `${navigator.userAgent} · ${window.screen.width}x${window.screen.height}`,
      );
      streamRef.current?.getTracks().forEach((track) => track.stop());
      setCameraOn(false);
      setDone(result.reference);
      await load().catch(() => undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The signature could not be saved.');
    } finally {
      setBusy(false);
    }
  };

  if (loading) {
    return (
      <PartnerShell title="Contract">
        <Loading />
      </PartnerShell>
    );
  }

  if (!contract) {
    return (
      <PartnerShell title="Contract">
        {error && <ErrorBox message={error} />}
        <section className="panel">
          <Empty
            title="Not ready yet"
            copy="UDrive is preparing your contract. You will be told when it is ready to read."
          />
        </section>
      </PartnerShell>
    );
  }

  if (done || contract.status === 'Signed') {
    return (
      <PartnerShell
        title="Signed"
        subtitle={`${contract.reference} · ${when(contract.signedAt)}`}
      >
        <section className="panel">
          <header className="panelHeader">
            <div>
              <h2>Your area is yours</h2>
              <p>
                The contract runs until {when(contract.endsAt)}. Your photograph and
                video are kept only as proof of this signature, are visible to
                UDrive&apos;s SuperAdmin alone, and are deleted after the contract ends.
              </p>
            </div>
            <Badge value="Signed" />
          </header>
          <div style={{ padding: '0 22px 22px' }}>
            <div className="contractText">
              <ContractText text={contract.renderedText} />
            </div>
          </div>
        </section>
      </PartnerShell>
    );
  }

  const canSign = readIt && selfie && clip;

  return (
    <PartnerShell
      title="Your contract"
      subtitle={`${contract.reference} · sent ${when(contract.sentAt)}`}
    >
      {error && <ErrorBox message={error} />}

      {/* ─────────────────────────────── step 1: read it */}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>1 — Read the whole agreement</h2>
            <p>
              Deposit {money(contract.securityDeposit)} (refundable) ·{' '}
              {contract.commissionSharePct}% of UDrive&apos;s commission in your area ·{' '}
              {contract.termMonths} months
            </p>
          </div>
        </header>
        <div style={{ padding: '0 22px 10px' }}>
          <div className="contractText">
              <ContractText text={contract.renderedText} />
            </div>
        </div>
        <div style={{ padding: '0 22px 22px' }}>
          <label className="signCheck">
            <input
              type="checkbox"
              checked={readIt}
              onChange={(e) => setReadIt(e.target.checked)}
            />
            <span>
              I have read the whole agreement above and I accept it of my own free
              will.
            </span>
          </label>
        </div>
      </section>

      {/* ───────────────────── step 2 and 3: the camera */}

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>2 — Your photograph, taken now</h2>
            <p>
              The camera opens here. A photograph from your gallery cannot be used —
              this has to be taken at the moment you sign.
            </p>
          </div>
          {selfie ? <Badge value="Taken" /> : <Badge value="Pending" />}
        </header>

        {cameraError && <ErrorBox message={cameraError} />}

        <div className="captureGrid">
          <div className="captureBox">
            <video ref={videoRef} muted playsInline className="captureVideo" />
            {!cameraOn && (
              <div className="captureOverlay">
                <Camera />
                <p>The camera is off</p>
              </div>
            )}
            {recording && (
              <div className="recordingDot">
                <Circle /> {seconds}s / {MAX_SECONDS}s
              </div>
            )}
          </div>

          <div className="captureSide">
            {!cameraOn ? (
              <button
                className="primaryButton wide"
                disabled={busy || !readIt}
                onClick={() => void startCamera()}
              >
                <Camera /> Open the camera
              </button>
            ) : (
              <>
                <button
                  className="primaryButton wide"
                  disabled={busy || recording}
                  onClick={takeSelfie}
                >
                  <Camera /> {selfie ? 'Take it again' : 'Take the photograph'}
                </button>

                {selfieUrl && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={selfieUrl} alt="Your photograph" className="capturePreview" />
                )}
              </>
            )}
            {!readIt && (
              <p className="captureHint">
                Read the agreement and tick the box above first.
              </p>
            )}
          </div>
        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>3 — A short video, reading these words</h2>
            <p>
              Read the sentence below out loud, exactly as written. Up to one minute.
            </p>
          </div>
          {clip ? <Badge value="Recorded" /> : <Badge value="Pending" />}
        </header>

        <div style={{ padding: '0 22px 14px' }}>
          <p className="scriptBox">{contract.videoScript}</p>
          <p className="captureHint">
            The same words for every partner, on purpose: it is what makes the
            recording worth keeping. Say your own name where it asks for it.
          </p>
        </div>

        <div className="captureGrid">
          <div className="captureBox">
            {clipUrl ? (
              <video src={clipUrl} controls className="captureVideo" />
            ) : (
              <div className="captureOverlay">
                <Video />
                <p>Nothing recorded yet</p>
              </div>
            )}
          </div>

          <div className="captureSide">
            {!cameraOn ? (
              <p className="captureHint">Open the camera in step 2 first.</p>
            ) : recording ? (
              <button className="dangerButton wide" onClick={stopRecording}>
                <Square /> Stop recording ({seconds}s)
              </button>
            ) : (
              <button
                className="primaryButton wide"
                disabled={busy || !selfie}
                onClick={startRecording}
              >
                <Video /> {clip ? 'Record it again' : 'Start recording'}
              </button>
            )}
            {!selfie && cameraOn && (
              <p className="captureHint">Take the photograph in step 2 first.</p>
            )}
          </div>

        </div>
      </section>

      <section className="panel">
        <header className="panelHeader">
          <div>
            <h2>4 — Sign it</h2>
            <p>
              UDrive records the time from its own server, the address you are
              connecting from, and the phone number you signed in with. These are kept
              only as proof of this signature.
            </p>
          </div>
        </header>
        <div className="buttonRow" style={{ paddingTop: 0 }}>
          <button
            className="primaryButton"
            disabled={!canSign || busy}
            onClick={() => void submit()}
          >
            {busy ? <Loader2 className="spin" /> : <CheckCircle2 />} Complete the
            signature
          </button>
          {!canSign && (
            <p className="captureHint" style={{ margin: 0 }}>
              All three steps have to be done first.
            </p>
          )}
        </div>
      </section>
    </PartnerShell>
  );
}
