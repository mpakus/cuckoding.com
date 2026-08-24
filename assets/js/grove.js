function prefersReducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

function palette(energy, blocked) {
  return {
    skyTop: "rgba(20, 16, 40, 0)",
    skyBottom: "rgba(42, 70, 48, 0.28)",
    ground: "#3d5a32",
    groundDark: "#24351e",
    trunk: "#8a6a4e",
    trunkDark: "#4a3426",
    leaf: blocked ? "#c9a15a" : "#6ea84a",
    leafLite: blocked ? "#e6c97a" : "#a4d46a",
    leafDeep: "#2f5a32",
    glow: blocked ? "rgba(210, 150, 70, 0.22)" : `rgba(150, 120, 255, ${0.1 + energy * 0.28})`,
    mote: blocked ? "rgba(232, 180, 90, 0.65)" : "rgba(186, 168, 255, 0.8)",
    flower: "rgba(255, 255, 255, 0.72)",
  }
}

function lerp(a, b, t) {
  return a + (b - a) * t
}

function clamp(n, min, max) {
  return Math.min(max, Math.max(min, n))
}

function readStats(el) {
  const working = Number(el.dataset.working || 0)
  const blocked = Number(el.dataset.blocked || 0)
  const total = Number(el.dataset.total || 0)
  const base = total === 0 ? 0.1 : 0.22 + Math.min(total, 6) * 0.05
  const activeBoost = Math.min(working, 5) * 0.14
  const blockPull = blocked > 0 ? 0.04 : 0
  return {
    working,
    blocked,
    total,
    target: clamp(base + activeBoost - blockPull, 0.08, 0.98),
    energy: working > 0 ? 1 : blocked > 0 ? 0.35 : 0.12,
  }
}

function drawBranch(ctx, x, y, len, angle, depth, maxDepth, growth, time, wind, colors) {
  const reveal = growth * maxDepth
  if (depth > reveal) return

  const frac = clamp(reveal - depth, 0, 1)
  const sway = Math.sin(time * 0.0009 + depth * 0.65 + x * 0.012) * wind * (0.035 + (maxDepth - depth) * 0.008)
  const a = angle + sway
  const x2 = x + Math.cos(a) * len * frac
  const y2 = y + Math.sin(a) * len * frac
  const width = Math.max(0.6, (maxDepth - depth + 1) * 1.15 * Math.min(1, growth * 1.2))

  ctx.beginPath()
  ctx.moveTo(x, y)
  ctx.quadraticCurveTo(
    (x + x2) / 2 + Math.cos(a + Math.PI / 2) * width * 0.4,
    (y + y2) / 2 + Math.sin(a + Math.PI / 2) * width * 0.15,
    x2,
    y2
  )
  ctx.strokeStyle = depth < 3 ? colors.trunkDark : colors.trunk
  ctx.lineWidth = width
  ctx.lineCap = "round"
  ctx.stroke()

  const leafy = depth >= maxDepth - 3 || len < 16
  if (leafy && frac > 0.35) {
    const count = 3 + Math.floor(growth * 5)
    for (let i = 0; i < count; i += 1) {
      const spread = (i - count / 2) * 0.42
      const lx = x2 + Math.cos(a + spread) * (5 + growth * 8)
      const ly = y2 + Math.sin(a + spread) * (4 + growth * 6)
      const r = (3.2 + growth * 5.5) * frac
      const shade = i % 3 === 0 ? colors.leafLite : i % 3 === 1 ? colors.leaf : colors.leafDeep
      ctx.beginPath()
      ctx.fillStyle = shade
      ctx.globalAlpha = 0.55 + frac * 0.4
      ctx.ellipse(lx, ly, r * 1.15, r * 0.72, a + spread, 0, Math.PI * 2)
      ctx.fill()
      ctx.globalAlpha = 1
    }
  }

  if (depth >= maxDepth || len < 8) return

  const shrink = 0.68 + growth * 0.08
  const fork = 0.38 + (1 - depth / maxDepth) * 0.18
  drawBranch(ctx, x2, y2, len * shrink, a - fork, depth + 1, maxDepth, growth, time, wind, colors)
  drawBranch(ctx, x2, y2, len * (shrink - 0.04), a + fork * 0.92, depth + 1, maxDepth, growth, time, wind, colors)
  if (growth > 0.55 && depth < 3 && depth % 2 === 0) {
    drawBranch(ctx, x2, y2, len * 0.52, a + 0.08, depth + 2, maxDepth, growth, time, wind, colors)
  }
}

function drawTree(ctx, x, groundY, scale, growth, time, wind, colors) {
  const maxDepth = 9
  const len = 26 * scale + growth * 38 * scale
  ctx.save()
  ctx.shadowColor = colors.glow
  ctx.shadowBlur = 18 + growth * 22
  drawBranch(ctx, x, groundY, len, -Math.PI / 2, 0, maxDepth, growth, time, wind, colors)
  ctx.restore()
}

function drawGround(ctx, w, h, colors, growth) {
  const gy = h * 0.82
  const grd = ctx.createLinearGradient(0, gy - 30, 0, h)
  grd.addColorStop(0, "transparent")
  grd.addColorStop(0.35, colors.ground)
  grd.addColorStop(1, colors.groundDark)
  ctx.fillStyle = grd
  ctx.beginPath()
  ctx.ellipse(w / 2, gy + 18, w * 0.46, 22 + growth * 10, 0, 0, Math.PI * 2)
  ctx.fill()

  for (let i = 0; i < 9; i += 1) {
    const fx = w * 0.18 + ((i * 47) % Math.floor(w * 0.64))
    const fy = gy + 4 + (i % 3) * 3
    ctx.fillStyle = colors.flower
    ctx.globalAlpha = 0.35 + (i % 4) * 0.1
    ctx.beginPath()
    ctx.arc(fx, fy, 1.2 + (i % 2), 0, Math.PI * 2)
    ctx.fill()
  }
  ctx.globalAlpha = 1
  return gy
}

function spawnMotes(particles, w, h, energy, blocked) {
  if (energy < 0.4) return
  if (particles.length > 48) return
  if (Math.random() > 0.35) return
  particles.push({
    x: w * (0.28 + Math.random() * 0.44),
    y: h * (0.25 + Math.random() * 0.45),
    r: blocked ? 1.1 : 1.4 + Math.random() * 1.6,
    vx: (Math.random() - 0.5) * 0.25,
    vy: -0.12 - Math.random() * 0.22,
    life: 1,
  })
}

function drawMotes(ctx, particles, colors) {
  for (let i = particles.length - 1; i >= 0; i -= 1) {
    const p = particles[i]
    p.x += p.vx
    p.y += p.vy
    p.life -= 0.0045
    if (p.life <= 0) {
      particles.splice(i, 1)
      continue
    }
    ctx.beginPath()
    ctx.fillStyle = colors.mote
    ctx.globalAlpha = p.life * 0.8
    ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2)
    ctx.fill()
    ctx.globalAlpha = 1
  }
}

function paint(state, now) {
  const { canvas, ctx, growth, stats } = state
  const dpr = state.dpr
  const w = canvas.width / dpr
  const h = canvas.height / dpr
  const colors = palette(stats.energy, stats.blocked > 0)
  const wind = state.reduced ? 0 : 0.55 + stats.energy * 1.4

  ctx.clearRect(0, 0, w, h)

  const sky = ctx.createLinearGradient(0, 0, 0, h)
  sky.addColorStop(0, colors.skyTop)
  sky.addColorStop(1, colors.skyBottom)
  ctx.fillStyle = sky
  ctx.fillRect(0, 0, w, h)

  const gy = drawGround(ctx, w, h, colors, growth)
  const companions = Math.min(3, Math.max(0, stats.working - 1) + (stats.total > 2 ? 1 : 0))
  if (companions >= 1) {
    drawTree(ctx, w * 0.22, gy + 2, 0.55, growth * 0.72, now + 800, wind * 0.8, colors)
  }
  if (companions >= 2) {
    drawTree(ctx, w * 0.8, gy + 4, 0.48, growth * 0.64, now + 1400, wind * 0.7, colors)
  }
  if (companions >= 3) {
    drawTree(ctx, w * 0.12, gy + 6, 0.34, growth * 0.5, now + 400, wind, colors)
  }
  drawTree(ctx, w * 0.52, gy, 1, growth, now, wind, colors)

  if (!state.reduced) {
    spawnMotes(state.particles, w, h, stats.energy, stats.blocked > 0)
    drawMotes(ctx, state.particles, colors)
  }
}

export const Grove = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    this.ctx = this.canvas.getContext("2d")
    this.particles = []
    this.growth = 0.08
    this.workedMs = 0
    this.last = performance.now()
    this.reduced = prefersReducedMotion()
    this.stats = readStats(this.el)
    this.resize = this.resize.bind(this)
    this.tick = this.tick.bind(this)
    this.ro = new ResizeObserver(this.resize)
    this.ro.observe(this.el)
    this.resize()
    if (this.reduced) {
      paint(this, this.last)
      return
    }
    this.raf = requestAnimationFrame(this.tick)
  },

  updated() {
    this.stats = readStats(this.el)
    if (this.reduced) paint(this, performance.now())
  },

  destroyed() {
    if (this.raf) cancelAnimationFrame(this.raf)
    if (this.ro) this.ro.disconnect()
  },

  resize() {
    const rect = this.el.querySelector(".desk-grove-frame").getBoundingClientRect()
    this.dpr = Math.min(window.devicePixelRatio || 1, 2)
    this.canvas.width = Math.max(1, Math.floor(rect.width * this.dpr))
    this.canvas.height = Math.max(1, Math.floor(rect.height * this.dpr))
    this.ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0)
    paint(this, performance.now())
  },

  tick(now) {
    const dt = Math.min(48, now - this.last)
    this.last = now
    if (this.stats.working > 0) this.workedMs += dt
    else this.workedMs = Math.max(0, this.workedMs - dt * 0.35)

    const lived = clamp(this.workedMs / 90000, 0, 0.28)
    const target = clamp(this.stats.target + lived, 0.08, 0.99)
    this.growth = lerp(this.growth, target, 0.045)
    paint(this, now)
    this.raf = requestAnimationFrame(this.tick)
  },
}
