// active-storage-async_variants
// Renders the correct fallback for async ActiveStorage variants, and polls
// for completion. Pairs with the gem's image_tag/video_tag `async:` /
// `direct:` options.

const STATE_ATTR = "data-async-variant-state-value"
const SRC_ATTR = "data-async-variant-src-value"
const DIRECT_ATTR = "data-async-variant-direct-value"
const SELECTOR = `[${STATE_ATTR}]`
const HEADER = "X-Async-Variant-State"
const POLLABLE_STATES = ["pending", "processing"]
const POLL_BASE_MS = 3000
const MAX_POLLS = 10
const RETRY_BASE_MS = 10000
const MAX_RETRIES = 3

const isSafari = typeof navigator !== "undefined" &&
  /^((?!chrome|android).)*safari/i.test(navigator.userAgent)

const elementState = new WeakMap()

function stateFor(el) {
  let s = elementState.get(el)
  if (!s) {
    s = { pollTimer: null, pollCount: 0, retries: 0 }
    elementState.set(el, s)
  }
  return s
}

function srcUrl(el) { return el.getAttribute(SRC_ATTR) }
function directUrl(el) { return el.getAttribute(DIRECT_ATTR) }
function variantState(el) { return el.getAttribute(STATE_ATTR) }

async function fetchAsyncState(url) {
  if (!url) return null
  try {
    const response = await fetch(url, { method: "HEAD", redirect: "error", cache: "no-store" })
    return response.headers.get(HEADER)
  } catch {
    return null
  }
}

function schedulePoll(el) {
  const s = stateFor(el)
  s.pollTimer = setTimeout(() => poll(el), POLL_BASE_MS * Math.pow(2, s.pollCount))
}

function stopPolling(el) {
  const s = elementState.get(el)
  if (s && s.pollTimer) {
    clearTimeout(s.pollTimer)
    s.pollTimer = null
  }
}

function startPolling(el) {
  const s = stateFor(el)
  if (s.pollTimer) return
  s.pollCount = 0
  schedulePoll(el)
}

async function poll(el) {
  const state = await fetchAsyncState(srcUrl(el))
  const s = stateFor(el)
  s.pollTimer = null
  if (POLLABLE_STATES.includes(state)) {
    s.pollCount += 1
    if (s.pollCount < MAX_POLLS) schedulePoll(el)
    return
  }
  if (state === "failed") return
  const target = directUrl(el) || srcUrl(el)
  if (!target) return
  el.src = target + (target.includes("?") ? "&" : "?") + "_t=" + Date.now()
}

function fallback(el) {
  const url = srcUrl(el)
  if (url) el.setAttribute("src", url)
}

function onLoad(event) {
  const el = event.target
  if (!el.matches || !el.matches(SELECTOR)) return
  if (POLLABLE_STATES.includes(variantState(el))) startPolling(el)
}

function onError(event) {
  const el = event.target
  if (!el.matches || !el.matches(SELECTOR)) return
  const s = stateFor(el)
  if (s.retries >= MAX_RETRIES) return
  setTimeout(() => fallback(el), RETRY_BASE_MS * Math.pow(2, s.retries))
  s.retries += 1
}

function setupVideo(el) {
  if (el.nodeName !== "VIDEO") return
  if (isSafari) fallback(el)
  // Browser autoplay-via-attribute is permitted on first load, but the
  // attribute also makes Turbo's cloneNode(true) snapshot start playback on
  // the detached clone (ghost audio). Strip the attribute after insertion --
  // playback is already scheduled -- and rely on play() here for restored
  // snapshots (which won't have the attribute anymore).
  // https://github.com/hotwired/turbo/issues/1017
  if (el.hasAttribute("autoplay")) {
    el.removeAttribute("autoplay")
    const promise = el.play()
    if (promise && typeof promise.catch === "function") promise.catch(() => {})
  }
}

function processAdded(node) {
  if (node.nodeType !== 1) return
  if (node.matches && node.matches(SELECTOR)) setupVideo(node)
  if (node.querySelectorAll) node.querySelectorAll(SELECTOR).forEach(setupVideo)
}

function processRemoved(node) {
  if (node.nodeType !== 1) return
  if (node.matches && node.matches(SELECTOR)) {
    stopPolling(node)
    elementState.delete(node)
  }
  if (node.querySelectorAll) {
    node.querySelectorAll(SELECTOR).forEach(el => {
      stopPolling(el)
      elementState.delete(el)
    })
  }
}

let started = false
function start() {
  if (started || typeof document === "undefined") return
  started = true
  document.addEventListener("load", onLoad, true)
  document.addEventListener("error", onError, true)
  const observer = new MutationObserver(records => {
    for (const r of records) {
      r.addedNodes.forEach(processAdded)
      r.removedNodes.forEach(processRemoved)
    }
  })
  observer.observe(document.documentElement, { childList: true, subtree: true })
  document.querySelectorAll(SELECTOR).forEach(setupVideo)
}

function autostart() {
  if (typeof window === "undefined" || window.ActiveStorageAsyncVariants !== null) start()
}

if (typeof document !== "undefined") {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", autostart)
  } else {
    setTimeout(autostart, 1)
  }
}

export { start }
