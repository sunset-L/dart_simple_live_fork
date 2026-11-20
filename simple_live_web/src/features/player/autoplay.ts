export function createAutoplay(
  video: HTMLVideoElement,
  onBlocked: (blocked: boolean) => void,
  canPlay: () => boolean,
) {
  let mutedForAutoplay = false;
  let generation = 0;

  const complete = () => {
    mutedForAutoplay = false;
    onBlocked(false);
  };
  const reset = () => {
    generation++;
    if (mutedForAutoplay) video.muted = false;
    complete();
  };

  async function enableSound() {
    if (!mutedForAutoplay || !canPlay()) return;
    const version = ++generation;
    const wasPaused = video.paused;
    // This must run synchronously inside a real input event, before awaiting.
    video.muted = false;
    if (video.volume === 0) video.volume = 0.8;
    try {
      await video.play();
      if (version === generation) complete();
    } catch {
      if (version !== generation) return;
      video.muted = true;
      if (!wasPaused) void video.play().catch(() => {});
    }
  }

  const gesture = (event: Event) => {
    // Ordinary interaction may enable sound, but must never undo a pause
    // or a volume slider explicitly set to zero.
    if (event.isTrusted && !video.paused && video.volume > 0)
      void enableSound();
  };
  const inputEvents = ["click", "keydown", "touchend"];
  for (const event of inputEvents) window.addEventListener(event, gesture);

  return {
    async play(current: () => boolean) {
      const version = ++generation;
      if (mutedForAutoplay) video.muted = false;
      try {
        await video.play();
        if (current() && version === generation) complete();
      } catch (error) {
        if (
          !current() ||
          version !== generation ||
          !(error instanceof DOMException) ||
          error.name !== "NotAllowedError" ||
          video.muted
        )
          throw error;
        mutedForAutoplay = true;
        onBlocked(true);
        video.muted = true;
        // Unmuting immediately here would make the browser pause again.
        // Keep muted playback until a real gesture grants audible playback.
        await video.play();
      } finally {
        // The opener is only needed during startup, not for later navigation.
        window.opener = null;
      }
    },
    enableSound: () => void enableSound(),
    reset,
    destroy() {
      for (const event of inputEvents) window.removeEventListener(event, gesture);
      reset();
    },
  };
}
