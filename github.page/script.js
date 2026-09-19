const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const revealElements = [...document.querySelectorAll("[data-reveal]")];
const storySteps = [...document.querySelectorAll("[data-story-step]")];
const storyImages = [...document.querySelectorAll("[data-story-image]")];
const storyLabel = document.querySelector("[data-story-label]");
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

const activateStory = (index) => {
  storySteps.forEach((step) => step.classList.toggle("is-active", step.dataset.storyStep === index));
  storyImages.forEach((image) => image.classList.toggle("is-active", image.dataset.storyImage === index));
  if (storyLabel) storyLabel.textContent = storySteps[Number(index)]?.dataset.label ?? "";
};

if ("IntersectionObserver" in window) {
  const storyObserver = new IntersectionObserver(
    (entries) => {
      const current = entries
        .filter((entry) => entry.isIntersecting)
        .sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (current) activateStory(current.target.dataset.storyStep);
    },
    { rootMargin: "-28% 0px -28%", threshold: [0.2, 0.5, 0.8] },
  );
  storySteps.forEach((step) => storyObserver.observe(step));
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
    const rotation = Number(layer.dataset.rotate || 0);
    const rect = layer.parentElement.getBoundingClientRect();
    const distance = rect.top + rect.height / 2 - viewportCenter;
    const offset = Math.max(-96, Math.min(96, distance * -speed));
    const turn = rotation + offset * 0.035;
    layer.style.transform = `translate3d(0, ${offset}px, 0) rotate(${turn}deg)`;
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
  if (reduceMotion.matches) parallaxLayers.forEach((layer) => layer.removeAttribute("style"));
  requestPaint();
});
requestPaint();
