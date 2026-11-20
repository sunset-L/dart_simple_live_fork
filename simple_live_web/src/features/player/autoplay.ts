export function createAutoplay(
  video: HTMLVideoElement,
  onBlocked: (blocked: boolean) => void,
  canPlay: () => boolean,
) {
  let startup: "initial" | "assisting" | "finished" = "initial";
  let mutedForAutoplay = false;
  let generation = 0;
  let attemptedPlayback = false;
  let loading = false;
  let soundAttempt: number | undefined;
  let nextPassiveAttempt = 0;
  const inputEvents = [
    "pointermove",
    "pointerdown",
    "click",
    "wheel",
    "keydown",
    "touchend",
  ];

  function removeInputs() {
    for (const event of inputEvents)
      window.removeEventListener(event, gesture, true);
  }
  function finishStartup() {
    startup = "finished";
    removeInputs();
  }
  function invalidate() {
    generation++;
    soundAttempt = undefined;
  }
  function complete() {
    mutedForAutoplay = false;
    onBlocked(false);
    finishStartup();
  }
  function cancelStartupAssistance() {
    invalidate();
    // Relinquish the temporary mute without changing the user's controls.
    complete();
  }

  function soundAllowed() {
    const browser = navigator as Navigator & {
      getAutoplayPolicy?: (element: HTMLMediaElement) => string;
    };
    try {
      if (browser.getAutoplayPolicy)
        return browser.getAutoplayPolicy(video) === "allowed";
    } catch {
      // Not all implementations support querying an individual media element.
    }
    return Boolean(
      navigator.userActivation?.isActive ||
      navigator.userActivation?.hasBeenActive,
    );
  }

  async function enableSound(resume: boolean) {
    if (
      !mutedForAutoplay ||
      !canPlay() ||
      soundAttempt !== undefined ||
      (!resume && (video.paused || video.volume === 0))
    )
      return;
    const version = ++generation;
    soundAttempt = version;
    const wasPaused = video.paused;
    // Keep this synchronous so a real input's activation is not lost.
    video.muted = false;
    if (resume && video.volume === 0) video.volume = 0.8;
    try {
      await video.play();
      if (version === generation) complete();
    } catch {
      if (version !== generation || !canPlay()) return;
      nextPassiveAttempt = performance.now() + 1000;
      video.muted = true;
      // A control operation invalidates this attempt before it can undo a pause.
      if (!wasPaused && version === generation && canPlay())
        await video.play().catch(() => {});
    } finally {
      if (soundAttempt === version) soundAttempt = undefined;
    }
  }

  function gesture(event: Event) {
    if (startup !== "assisting" || !event.isTrusted) return;
    const passive = event.type === "pointermove" || event.type === "wheel";
    if (
      passive &&
      (performance.now() < nextPassiveAttempt || !soundAllowed())
    )
      return;
    // Touch/pen pointerdown is not an activation; wait for click/touchend.
    if (
      event instanceof PointerEvent &&
      event.type === "pointerdown" &&
      event.pointerType !== "mouse"
    )
      return;
    void enableSound(false);
  }

  return {
    beginLoad() {
      invalidate();
      loading = true;
    },
    async play(current: () => boolean) {
      attemptedPlayback = true;
      loading = false;
      const version = ++generation;
      try {
        await video.play();
        if (current() && version === generation && !mutedForAutoplay) complete();
      } catch (error) {
        if (!current() || version !== generation) return;
        if (
          !(error instanceof DOMException) ||
          error.name !== "NotAllowedError" ||
          video.muted
        )
          throw error;
        mutedForAutoplay = true;
        onBlocked(true);
        video.muted = true;
        if (startup === "initial") {
          startup = "assisting";
          for (const event of inputEvents)
            window.addEventListener(event, gesture, {
              capture: true,
              passive: true,
            });
        }
        // Playback takes priority. Never immediately undo this fallback mute.
        await video.play();
      } finally {
        window.opener = null;
      }
    },
    enableSound: () => void enableSound(true),
    cancelStartupAssistance,
    paused() {
      if (!loading && soundAttempt === undefined && video.paused)
        cancelStartupAssistance();
    },
    reset() {
      loading = false;
      invalidate();
      // The initial empty source must not consume the page's startup phase.
      if (attemptedPlayback) complete();
    },
    destroy() {
      cancelStartupAssistance();
    },
  };
}
