(() => {
  const scenes = [...document.querySelectorAll("[data-parallax]")].map(frame => ({
    frame,
    stage: frame.querySelector(".stage") || frame,
    layers: [...frame.querySelectorAll("[data-motion]")],
  }));
  const toggle = document.querySelector("#motion-toggle");
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  let paused = false;
  let pending = false;

  try { paused = localStorage.getItem("ccoding-parallax") === "paused"; } catch { /* Storage is optional. */ }

  function paint() {
    pending = false;
    const off = paused || reduced.matches;
    for (const { frame, stage, layers } of scenes) {
      const bounds = frame.getBoundingClientRect();
      const size = stage.getBoundingClientRect();
      const progress = Math.max(0, Math.min(1, (innerHeight - bounds.top) / (innerHeight + bounds.height)));
      const camera = Math.max(0, Math.min(1, -bounds.top / Math.max(1, bounds.height - size.height)));
      const wave = Math.sin(progress * Math.PI * 4);
      // The two weapon tips meet before the sticky scene leaves the viewport.
      const approach = Math.max(0, 1 - progress * 1.8) * size.width * 0.18;
      for (const layer of layers) {
        let x = 0, y = 0, angle = 0;
        const motion = layer.dataset.motion;
        let scale = motion === "depth" || motion === "vault" ? 1.13 : 1;
        if (!off) {
          switch (motion) {
            case "depth": y = (progress * 2 - 1) * size.height * 0.055; break;
            case "vault": scale += camera * 0.15; break;
            case "emissary": scale += camera * 0.42; y = -camera * size.height * 0.015; break;
            case "sword": x = -approach; angle = -approach / size.width * 8; break;
            case "morgenstern": x = approach; angle = approach / size.width * 8; break;
            case "pan": angle = wave * 6; y = -Math.abs(wave) * size.height * 0.035; break;
            case "dance": angle = -wave * 4; y = -Math.abs(wave) * size.height * 0.022; break;
            case "leisure": y = -progress * size.height * 0.04; break;
            case "weight": y = progress * size.height * 0.025; break;
          }
        }
        layer.style.transform = `translate3d(${x}px, ${y}px, 0) rotate(${angle}deg) scale(${scale})`;
      }
    }
  }

  function schedule() {
    if (!pending && !paused && !reduced.matches) {
      pending = true;
      requestAnimationFrame(paint);
    }
  }

  function preference() {
    // Pausing keeps page geometry stable; no JS or reduced motion removes the pinning.
    document.documentElement.dataset.motion = reduced.matches ? "reduced" : "enabled";
    toggle.hidden = false;
    toggle.disabled = reduced.matches;
    toggle.setAttribute("aria-pressed", String(paused || reduced.matches));
    toggle.textContent = reduced.matches ? "Reduced motion on" : paused ? "Resume parallax" : "Pause parallax";
    paint();
  }

  toggle.addEventListener("click", () => {
    paused = !paused;
    try { localStorage.setItem("ccoding-parallax", paused ? "paused" : "running"); } catch { /* Storage is optional. */ }
    preference();
  });
  reduced.addEventListener("change", preference);
  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule);
  preference();
})();
