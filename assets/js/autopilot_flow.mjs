import * as THREE from "three"

const PALETTE = {
  paper: 0xf6f3ea,
  surface: 0xfffdf7,
  ink: 0x252a24,
  muted: 0x62675c,
  forest: 0x35593c,
  sage: 0xdce7d8,
  peach: 0xf1d4c2,
  line: 0xc8ccc0,
  warning: 0x78501c,
  danger: 0x9b3d2c
}

const STATE_FILL = {
  current: PALETTE.forest,
  done: PALETTE.sage,
  failed: PALETTE.peach,
  waiting: PALETTE.surface
}

const STATE_BORDER = {
  current: PALETTE.ink,
  done: PALETTE.forest,
  failed: PALETTE.warning,
  waiting: PALETTE.line
}

export function layoutPipeline(payload, width = 760, height = 228) {
  const stages = Array.isArray(payload?.stages) ? payload.stages : []
  const items = Array.isArray(payload?.items) ? payload.items : []
  const padX = 24
  const usable = Math.max(width - padX * 2, 240)
  const stageCount = Math.max(stages.length, 1)
  const gap = 10
  const nodeW = Math.max(Math.floor((usable - gap * (stageCount - 1)) / stageCount), 34)
  const nodeH = 26
  const stageY = height - 30

  const stageNodes = stages.map((stage, index) => {
    const cx = padX + index * (nodeW + gap) + nodeW / 2
    return {
      index,
      id: stage.id,
      label: stage.label,
      state: stage.state || "waiting",
      x: cx,
      y: stageY,
      w: nodeW,
      h: nodeH
    }
  })

  const connectors = []
  for (let i = 0; i < stageNodes.length - 1; i++) {
    const left = stageNodes[i]
    const right = stageNodes[i + 1]
    const active =
      left.state === "current" ||
      right.state === "current" ||
      (left.state === "done" && right.state !== "waiting")
    connectors.push({
      fromX: left.x + left.w / 2 + 2,
      toX: right.x - right.w / 2 - 2,
      y: stageY,
      active,
      failed: right.state === "failed" || left.state === "failed"
    })
  }

  const cell = 18
  const cellGap = 5
  const cols = Math.max(Math.floor((usable + cellGap) / (cell + cellGap)), 6)
  const gridTop = height - 86

  const pixels = items.slice(0, 256).map((item, idx) => {
    const col = idx % cols
    const row = Math.floor(idx / cols)
    const x = padX + col * (cell + cellGap) + cell / 2
    const y = gridTop - row * (cell + cellGap)
    return {
      index: idx,
      taskId: item.task_id,
      position: item.position ?? idx,
      title: item.title || `Task ${idx + 1}`,
      state: item.state || "waiting",
      stage: item.stage || "plan",
      note: item.note || "",
      href: item.href || null,
      x,
      y,
      size: cell
    }
  })

  const focus =
    pixels.find(p => p.state === "current") ||
    pixels.find(p => p.state === "failed") ||
    pixels[0] ||
    null

  const targetStage =
    (focus && stageNodes.find(s => s.id === focus.stage)) ||
    stageNodes.find(s => s.state === "current" || s.state === "failed") ||
    null

  const route =
    focus && targetStage
      ? {
          fromX: targetStage.x,
          fromY: targetStage.y - targetStage.h / 2 - 2,
          midY: Math.round((targetStage.y - targetStage.h / 2 + focus.y + focus.size / 2) / 2),
          toX: focus.x,
          toY: focus.y + focus.size / 2 + 2,
          state: focus.state
        }
      : null

  return {width, height, stageNodes, connectors, pixels, route, focus}
}

export function hitTestPixel(layout, px, py) {
  if (!layout) return null
  const yWorld = layout.height - py
  for (const cell of layout.pixels) {
    const half = cell.size / 2 + 2
    if (
      px >= cell.x - half &&
      px <= cell.x + half &&
      yWorld >= cell.y - half &&
      yWorld <= cell.y + half
    ) {
      return cell
    }
  }
  return null
}

function parsePayload(raw) {
  if (!raw) return {stages: [], items: [], status: "idle"}
  try {
    return JSON.parse(raw)
  } catch {
    return {stages: [], items: [], status: "idle"}
  }
}

function motionEnabled(doc) {
  return doc?.documentElement?.dataset?.motion === "on"
}

function makeBox(w, h, fillHex, borderHex, z = 0) {
  const group = new THREE.Group()
  const outer = new THREE.Mesh(
    new THREE.PlaneGeometry(w, h),
    new THREE.MeshBasicMaterial({color: borderHex})
  )
  const inner = new THREE.Mesh(
    new THREE.PlaneGeometry(Math.max(w - 2, 2), Math.max(h - 2, 2)),
    new THREE.MeshBasicMaterial({color: fillHex})
  )
  inner.position.z = 0.1
  group.add(outer)
  group.add(inner)
  group.position.z = z
  return group
}

function disposeGroup(root) {
  root.traverse(obj => {
    if (obj.geometry) obj.geometry.dispose()
    if (obj.material) {
      if (Array.isArray(obj.material)) obj.material.forEach(m => m.dispose())
      else obj.material.dispose()
    }
  })
  while (root.children.length > 0) root.remove(root.children[0])
}

export const AutopilotFlowCanvas = {
  mounted() {
    this.stageHost = this.el.querySelector("[data-flow-canvas]")
    this.tooltip = this.el.querySelector("[data-flow-readout]")
    if (!this.stageHost) return

    this.hovered = null
    this.frame = null
    this.tick = 0
    this.pulses = []

    try {
      const canvas = document.createElement("canvas")
      canvas.className = "block h-full w-full"
      canvas.setAttribute("aria-hidden", "true")
      this.renderer = new THREE.WebGLRenderer({
        canvas,
        antialias: false,
        alpha: true,
        powerPreference: "low-power"
      })
      this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
      this.scene = new THREE.Scene()
      this.root = new THREE.Group()
      this.scene.add(this.root)
      this.camera = new THREE.OrthographicCamera(0, 760, 228, 0, -10, 10)
      this.camera.position.z = 5
      this.stageHost.replaceChildren(canvas)
      this.canvas = canvas
      this.el.dataset.webgl = "ready"
    } catch {
      this.renderer = null
      this.el.dataset.webgl = "fallback"
      return
    }

    this.onMove = event => {
      if (!this.layout || !this.canvas) return
      const rect = this.canvas.getBoundingClientRect()
      const hit = hitTestPixel(this.layout, event.clientX - rect.left, event.clientY - rect.top)
      this.canvas.style.cursor = hit ? "pointer" : "default"
      if (hit?.taskId !== this.hovered?.taskId) {
        this.hovered = hit
        this.updateReadout(hit || this.layout.focus)
        this.drawOnce()
      }
    }

    this.onLeave = () => {
      this.hovered = null
      if (this.canvas) this.canvas.style.cursor = "default"
      this.updateReadout(this.layout?.focus || null)
      this.drawOnce()
    }

    this.onClick = event => {
      if (!this.layout || !this.canvas) return
      const rect = this.canvas.getBoundingClientRect()
      const hit = hitTestPixel(this.layout, event.clientX - rect.left, event.clientY - rect.top)
      if (!hit) return
      const link = document.getElementById(`autopilot-pixel-${hit.taskId}`)
      if (link) {
        event.preventDefault()
        link.click()
      }
    }

    this.canvas.addEventListener("pointermove", this.onMove)
    this.canvas.addEventListener("pointerleave", this.onLeave)
    this.canvas.addEventListener("click", this.onClick)

    this.resizeObserver =
      typeof ResizeObserver !== "undefined"
        ? new ResizeObserver(() => this.rebuild())
        : null
    this.resizeObserver?.observe(this.stageHost)

    this.motionObserver =
      typeof MutationObserver !== "undefined"
        ? new MutationObserver(() => this.syncLoop())
        : null
    this.motionObserver?.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-motion"]
    })

    this.rebuild()
  },

  updated() {
    if (!this.renderer) return
    this.rebuild()
  },

  destroyed() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    this.resizeObserver?.disconnect()
    this.motionObserver?.disconnect()
    if (this.canvas) {
      this.canvas.removeEventListener("pointermove", this.onMove)
      this.canvas.removeEventListener("pointerleave", this.onLeave)
      this.canvas.removeEventListener("click", this.onClick)
    }
    if (this.root) disposeGroup(this.root)
    this.renderer?.dispose()
  },

  rebuild() {
    if (!this.renderer || !this.stageHost) return
    this.payload = parsePayload(this.el.dataset.flow)
    const width = Math.max(Math.floor(this.stageHost.clientWidth || 720), 260)
    const rows = Math.max(Math.ceil((this.payload.items?.length || 1) / Math.max(Math.floor((width - 43) / 23), 6)), 1)
    const height = Math.min(Math.max(126 + rows * 23, 148), 320)
    this.stageHost.style.height = `${height}px`
    this.renderer.setSize(width, height, false)
    this.camera.left = 0
    this.camera.right = width
    this.camera.top = height
    this.camera.bottom = 0
    this.camera.updateProjectionMatrix()

    this.layout = layoutPipeline(this.payload, width, height)
    this.populateScene()
    this.updateReadout(this.hovered || this.layout.focus)
    this.syncLoop()
  },

  populateScene() {
    disposeGroup(this.root)
    this.pulses = []
    const L = this.layout

    for (let gx = 12; gx < L.width; gx += 24) {
      for (let gy = 12; gy < L.height; gy += 24) {
        const dot = new THREE.Mesh(
          new THREE.PlaneGeometry(2, 2),
          new THREE.MeshBasicMaterial({color: PALETTE.line, transparent: true, opacity: 0.45})
        )
        dot.position.set(gx, gy, -1)
        this.root.add(dot)
      }
    }

    for (const c of L.connectors) {
      const span = Math.max(c.toX - c.fromX, 2)
      const color = c.failed ? PALETTE.warning : c.active ? PALETTE.forest : PALETTE.line
      const bar = new THREE.Mesh(
        new THREE.PlaneGeometry(span, 2),
        new THREE.MeshBasicMaterial({color})
      )
      bar.position.set((c.fromX + c.toX) / 2, c.y, 0)
      this.root.add(bar)

      if (c.active) {
        const packet = new THREE.Mesh(
          new THREE.PlaneGeometry(5, 5),
          new THREE.MeshBasicMaterial({color: PALETTE.ink})
        )
        packet.position.set(c.fromX, c.y, 0.5)
        this.root.add(packet)
        this.pulses.push({kind: "span", mesh: packet, fromX: c.fromX, toX: c.toX, y: c.y})
      }
    }

    for (const node of L.stageNodes) {
      const box = makeBox(
        node.w,
        node.h,
        STATE_FILL[node.state] ?? PALETTE.surface,
        STATE_BORDER[node.state] ?? PALETTE.line,
        0.2
      )
      box.position.set(node.x, node.y, 0.2)
      this.root.add(box)

      const pipColor =
        node.state === "current"
          ? PALETTE.paper
          : node.state === "failed"
            ? PALETTE.danger
            : node.state === "done"
              ? PALETTE.forest
              : PALETTE.muted
      const pip = new THREE.Mesh(
        new THREE.PlaneGeometry(6, 6),
        new THREE.MeshBasicMaterial({color: pipColor})
      )
      pip.position.set(node.x - node.w / 2 + 8, node.y, 0.6)
      this.root.add(pip)
      if (node.state === "current") {
        this.pulses.push({kind: "beacon", mesh: pip})
      }
    }

    if (L.route) {
      const r = L.route
      const routeColor =
        r.state === "failed" ? PALETTE.warning : r.state === "current" ? PALETTE.forest : PALETTE.line
      const segs = [
        {x: r.fromX, y: (r.fromY + r.midY) / 2, w: 2, h: Math.abs(r.fromY - r.midY) + 2},
        {x: (r.fromX + r.toX) / 2, y: r.midY, w: Math.abs(r.toX - r.fromX) + 2, h: 2},
        {x: r.toX, y: (r.midY + r.toY) / 2, w: 2, h: Math.abs(r.midY - r.toY) + 2}
      ]
      for (const s of segs) {
        const mesh = new THREE.Mesh(
          new THREE.PlaneGeometry(Math.max(s.w, 2), Math.max(s.h, 2)),
          new THREE.MeshBasicMaterial({color: routeColor})
        )
        mesh.position.set(s.x, s.y, 0.15)
        this.root.add(mesh)
      }
      if (r.state === "current") {
        const runner = new THREE.Mesh(
          new THREE.PlaneGeometry(6, 6),
          new THREE.MeshBasicMaterial({color: PALETTE.ink})
        )
        runner.position.set(r.fromX, r.fromY, 0.7)
        this.root.add(runner)
        this.pulses.push({kind: "route", mesh: runner, route: r})
      }
    }

    for (const cell of L.pixels) {
      const selected = this.hovered?.taskId === cell.taskId
      const box = makeBox(
        selected ? cell.size + 3 : cell.size,
        selected ? cell.size + 3 : cell.size,
        STATE_FILL[cell.state] ?? PALETTE.surface,
        selected ? PALETTE.ink : STATE_BORDER[cell.state] ?? PALETTE.line,
        0.3
      )
      box.position.set(cell.x, cell.y, 0.3)
      this.root.add(box)

      if (cell.state === "current") {
        const core = new THREE.Mesh(
          new THREE.PlaneGeometry(6, 6),
          new THREE.MeshBasicMaterial({color: PALETTE.paper})
        )
        core.position.set(cell.x, cell.y, 0.8)
        this.root.add(core)
        this.pulses.push({kind: "beacon", mesh: core})
      } else if (cell.state === "failed") {
        const mark = new THREE.Mesh(
          new THREE.PlaneGeometry(6, 2),
          new THREE.MeshBasicMaterial({color: PALETTE.danger})
        )
        mark.position.set(cell.x, cell.y, 0.8)
        this.root.add(mark)
      } else if (cell.state === "done") {
        const mark = new THREE.Mesh(
          new THREE.PlaneGeometry(5, 5),
          new THREE.MeshBasicMaterial({color: PALETTE.forest})
        )
        mark.position.set(cell.x, cell.y, 0.8)
        this.root.add(mark)
      }
    }
  },

  updateReadout(target) {
    if (!this.tooltip) return
    if (!target) {
      this.tooltip.textContent = "Select a task square to inspect its saved workflow and agent notes."
      return
    }
    const status =
      target.state === "current"
        ? "active"
        : target.state === "failed"
          ? "needs attention"
          : target.state === "done"
            ? "done"
            : "queued"
    const detail = target.note ? ` — ${target.note}` : ""
    this.tooltip.textContent = `#${target.position + 1} ${target.title} (${status} · ${target.stage})${detail}`
  },

  animateStep(t) {
    for (const item of this.pulses) {
      if (item.kind === "span") {
        const u = (t * 0.65) % 1
        item.mesh.position.x = item.fromX + (item.toX - item.fromX) * u
      } else if (item.kind === "beacon") {
        const scale = (Math.floor(t * 3) % 2) === 0 ? 1 : 0.6
        item.mesh.scale.set(scale, scale, 1)
      } else if (item.kind === "route") {
        const r = item.route
        const u = (t * 0.55) % 1
        if (u < 0.34) {
          const k = u / 0.34
          item.mesh.position.set(r.fromX, r.fromY + (r.midY - r.fromY) * k, 0.7)
        } else if (u < 0.67) {
          const k = (u - 0.34) / 0.33
          item.mesh.position.set(r.fromX + (r.toX - r.fromX) * k, r.midY, 0.7)
        } else {
          const k = (u - 0.67) / 0.33
          item.mesh.position.set(r.toX, r.midY + (r.toY - r.midY) * k, 0.7)
        }
      }
    }
  },

  drawOnce() {
    if (!this.renderer) return
    this.renderer.render(this.scene, this.camera)
  },

  syncLoop() {
    if (!this.renderer) return
    if (this.frame) {
      cancelAnimationFrame(this.frame)
      this.frame = null
    }
    const shouldAnimate =
      motionEnabled(document) &&
      this.pulses.length > 0 &&
      (this.payload?.status === "running" || this.pulses.some(p => p.kind !== "beacon"))

    if (!shouldAnimate) {
      this.animateStep(0)
      this.drawOnce()
      return
    }

    const start = performance.now()
    const step = now => {
      if (!motionEnabled(document)) {
        this.frame = null
        this.animateStep(0)
        this.drawOnce()
        return
      }
      this.animateStep((now - start) / 1000)
      this.drawOnce()
      this.frame = requestAnimationFrame(step)
    }
    this.frame = requestAnimationFrame(step)
  }
}
