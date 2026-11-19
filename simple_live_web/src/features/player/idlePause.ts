// Temporary three-minute interval for user acceptance; restore to ten minutes afterward.
const idleDelay = 3 * 60 * 1000;
const warningDuration = 10 * 1000;

export function watchIdlePlayback(
  video: HTMLVideoElement,
  showCountdown: (seconds: number | null) => void,
  pause: () => void,
) {
  let timer: number | undefined;
  let lastActivity: number | undefined;
  let pauseAt: number | undefined;

  const stop = () => {
    window.clearTimeout(timer);
    lastActivity = undefined;
    if (pauseAt !== undefined) showCountdown(null);
    pauseAt = undefined;
  };

  function check() {
    if (video.paused || lastActivity === undefined) {
      stop();
      return;
    }
    const now = performance.now();
    const untilWarning = idleDelay - (now - lastActivity);
    if (untilWarning > 0) {
      timer = window.setTimeout(check, untilWarning);
      return;
    }
    pauseAt ??= now + warningDuration;
    const remaining = pauseAt - now;
    if (remaining <= 0) {
      stop();
      pause();
      return;
    }
    const seconds = Math.ceil(remaining / 1000);
    showCountdown(seconds);
    timer = window.setTimeout(check, remaining - (seconds - 1) * 1000);
  }

  const playing = () => {
    if (lastActivity !== undefined) return;
    lastActivity = performance.now();
    timer = window.setTimeout(check, idleDelay);
  };
  const activity = () => {
    if (lastActivity === undefined) return;
    lastActivity = performance.now();
    if (pauseAt === undefined) return;
    pauseAt = undefined;
    showCountdown(null);
    window.clearTimeout(timer);
    timer = window.setTimeout(check, idleDelay);
  };

  const inputEvents = ["pointermove", "pointerdown", "wheel", "keydown"];
  const stopEvents = ["pause", "ended", "error"];
  video.addEventListener("playing", playing);
  for (const event of stopEvents) video.addEventListener(event, stop);
  for (const event of inputEvents)
    window.addEventListener(event, activity, { capture: true, passive: true });

  return () => {
    window.clearTimeout(timer);
    video.removeEventListener("playing", playing);
    for (const event of stopEvents) video.removeEventListener(event, stop);
    for (const event of inputEvents)
      window.removeEventListener(event, activity, true);
  };
}
