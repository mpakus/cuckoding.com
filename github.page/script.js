const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const revealElements = [...document.querySelectorAll("[data-reveal]")];
const parallaxLayers = [...document.querySelectorAll("[data-parallax]")];
const progress = document.querySelector(".scroll-progress span");

const showReveals = () => revealElements.forEach((element) => element.setAttribute("data-visible", ""));

if (reduceMotion.matches || !("IntersectionObserver" in window)) {
  showReveals();
} else {
  document.documentElement.classList.add("motion-ready");
  const revealObserver = new IntersectionObserver(
    (entries, observer) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        entry.target.setAttribute("data-visible", "");
        observer.unobserve(entry.target);
      });
    },
    { rootMargin: "0px 0px -5% 0px", threshold: 0 },
  );
  requestAnimationFrame(() => revealElements.forEach((element) => {
    const rect = element.getBoundingClientRect();
    if (rect.top < window.innerHeight * 0.95 && rect.bottom > 0) {
      element.setAttribute("data-visible", "");
    } else {
      revealObserver.observe(element);
    }
  }));
}

let frameRequested = false;

const paintScroll = () => {
  frameRequested = false;
  const pageRange = document.documentElement.scrollHeight - window.innerHeight;
  if (progress && !reduceMotion.matches) {
    progress.style.transform = `scaleX(${pageRange > 0 ? window.scrollY / pageRange : 0})`;
  }

  if (reduceMotion.matches) return;
  const viewportCenter = window.innerHeight / 2;
  parallaxLayers.forEach((layer) => {
    const speed = Number(layer.dataset.parallax);
    const rect = layer.parentElement.getBoundingClientRect();
    const distance = rect.top + rect.height / 2 - viewportCenter;
    const offset = Math.max(-24, Math.min(24, distance * -speed));
    layer.style.transform = `translate3d(0, ${offset}px, 0)`;
  });
};

const requestPaint = () => {
  if (frameRequested) return;
  frameRequested = true;
  requestAnimationFrame(paintScroll);
};

window.addEventListener("scroll", requestPaint, { passive: true });
window.addEventListener("resize", requestPaint);
reduceMotion.addEventListener("change", () => {
  if (reduceMotion.matches) {
    parallaxLayers.forEach((layer) => layer.removeAttribute("style"));
    showReveals();
  }
  requestPaint();
});
requestPaint();
