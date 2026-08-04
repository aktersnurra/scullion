// Long-press (500 ms) → pushes the event named in data-long-press-event.
// The payload carries the element's other data-* attributes under their
// original hyphenated names mapped to snake_case (data-item-id → "item_id"),
// so server handlers pattern-match snake_case keys rather than the browser's
// camelCased dataset. Movement or release cancels.
const LongPress = {
  mounted() {
    const DURATION = 500
    let timer = null

    const payload = () => {
      const out = {}
      for (const attr of this.el.attributes) {
        if (attr.name.startsWith("data-") && attr.name !== "data-long-press-event") {
          out[attr.name.slice(5).replace(/-/g, "_")] = attr.value
        }
      }
      return out
    }

    const start = () => {
      timer = setTimeout(() => {
        this.pushEvent(this.el.dataset.longPressEvent, payload())
      }, DURATION)
    }
    const cancel = () => timer && (clearTimeout(timer), (timer = null))

    this.el.addEventListener("touchstart", start, {passive: true})
    this.el.addEventListener("touchend", cancel)
    this.el.addEventListener("touchmove", cancel)
    this.el.addEventListener("touchcancel", cancel)
    this.el.addEventListener("mousedown", start)
    this.el.addEventListener("mouseup", cancel)
    this.el.addEventListener("mouseleave", cancel)
    this.el.addEventListener("contextmenu", (e) => e.preventDefault())
  },
}

export default LongPress
