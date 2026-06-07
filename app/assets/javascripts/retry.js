// Declarative shadow roots are only attached by the initial HTML parser, not by
// fragment insertion (innerHTML / Turbo frame swaps), so promote them on connect.
customElements.define("async-variant-retry", class extends HTMLElement {
  connectedCallback() {
    if (this.shadowRoot) return
    const template = this.querySelector(":scope > template[shadowrootmode]")
    if (!template) return
    this.attachShadow({ mode: template.getAttribute("shadowrootmode") }).append(template.content)
    template.remove()
  }
})
