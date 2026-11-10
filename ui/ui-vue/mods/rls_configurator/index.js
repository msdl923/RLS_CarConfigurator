// RLS Konfigurator - UI entry point.
// Does nothing at UI boot except listen for one event. Lua (rlsConfigurator_core) sends
// "RlsConfiguratorAvailability" when the RLS vehicle list of a brand factory store is shown; only then
// is the overlay compiled and mounted (same lazy approach RLS uses for its tester menu).
import { getComponent } from "@/services/uiMods"

const OVERLAY_FILE = "/ui/ui-vue/mods/rls_configurator/ConfiguratorOverlay.vue"
const HOST_ID = "rls-configurator-host"

let mounted = false
let mountPromise = null
let lastAvailability = null

function payloadObject(payload) {
  if (Array.isArray(payload) && payload[0] && typeof payload[0] === "object") return payload[0]
  return payload && typeof payload === "object" ? payload : null
}

async function compileAndMount() {
  try {
    if (!window.Vue || !window.bngVue?.app?._context) {
      console.warn("[rls_configurator] Vue app context not ready")
      return false
    }
    let data = await getComponent(OVERLAY_FILE, false, true)
    if (!data?.compiled && typeof data?.compile === "function") data = await data.compile()
    if (data?.error || !data?.component) {
      console.error("[rls_configurator] Overlay compile failed", data && data.error, data && data.errorObj)
      return false
    }
    const hostEl = document.createElement("div")
    hostEl.id = HOST_ID
    document.body.appendChild(hostEl)
    const vnode = window.Vue.createVNode(data.component, { initial: lastAvailability })
    vnode.appContext = window.bngVue.app._context
    window.Vue.render(vnode, hostEl)
    mounted = true
    console.info("[rls_configurator] overlay mounted")
    return true
  } catch (err) {
    console.error("[rls_configurator] mount failed", err)
    return false
  }
}

function mountOverlay() {
  if (mounted || document.getElementById(HOST_ID)) {
    mounted = true
    return Promise.resolve(true)
  }
  if (!mountPromise) mountPromise = compileAndMount().finally(() => { mountPromise = null })
  return mountPromise
}

function onAvailability(payload) {
  const data = payloadObject(payload)
  if (!data) return
  lastAvailability = data
  if (!mounted && data.available === true) mountOverlay()
}

export function onLoad() {
  if (window.__rlsConfiguratorListening) return
  const bus = window.vueEventBus
  if (!bus || typeof bus.on !== "function") {
    console.warn("[rls_configurator] vueEventBus missing, configurator disabled")
    return
  }
  window.__rlsConfiguratorListening = true
  bus.on("RlsConfiguratorAvailability", onAvailability)
  console.info("[rls_configurator] loaded")
}

export function onUnload() {
  window.__rlsConfiguratorListening = false
  const bus = window.vueEventBus
  if (bus && typeof bus.off === "function") bus.off("RlsConfiguratorAvailability", onAvailability)
  const hostEl = document.getElementById(HOST_ID)
  if (hostEl && window.Vue?.render) {
    try { window.Vue.render(null, hostEl) } catch (_) {}
    hostEl.remove()
  }
  mounted = false
  lastAvailability = null
}
