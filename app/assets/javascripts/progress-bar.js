const CIRCLE_RADIUS = 40; // fallback r attribute; CSS shrinks it to fit the stroke
const PATH_LENGTH = 100;  // normalize the arc so dash math is independent of the radius

const STYLES = `
  :host {
    --progress-color: #2E7D32;
    --error-color: #7a242f;
    --indeterminate-color: #999;
    --track-color: #333333;
    --progress-duration: 120ms;
    --indeterminate-duration: 1.5s;
    --bar-height: 32px;
    --bar-padding: 8px;
    --circular-size: 64px;
    --circular-thickness: 16;
    display: block;
    overflow: hidden;
    background: var(--track-color);
    border: 1px solid #999;
    border-radius: 4px;
    min-height: var(--bar-height);
    padding: var(--bar-padding);
    font-size: 13px;
    align-content: center;
    box-sizing: border-box;
    position: relative;
  }
  .bar {
    position: absolute;
    top: 0;
    left: 0;
    height: 100%;
    width: 0%;
    background: var(--progress-color);
    transition: width var(--progress-duration) ease;
    z-index: 1;
  }
  .text{position: relative; z-index: 2;}
  :host([error]) .bar {
    background: var(--error-color);
  }

  /* Indeterminate (linear): no percent set — a fixed-width segment sweeping across the track. */
  :host(:not([percent])) .bar {
    background: var(--indeterminate-color);
    width: 40%;
    animation: indeterminate-linear var(--indeterminate-duration) infinite linear;
  }

  @keyframes indeterminate-linear {
    0%   { transform: translateX(-100%); }
    100% { transform: translateX(250%); }
  }

  /* Circular mode: the host box styling is for the linear track, so drop it. */
  :host([mode="circular"]) {
    background: transparent;
    border: none;
    overflow: visible;
    padding: 0;
    min-height: 0;
  }

  .circular {
    position: relative;
    display: inline-flex;
    width: var(--circular-size);
    height: var(--circular-size);
  }

  .ring {
    width: 100%;
    height: 100%;
    transform: rotate(-90deg);
  }

  .ring circle {
    fill: none;
    stroke-width: var(--circular-thickness);
    /* Shrink the radius so the stroke's outer edge always lands inside the
       100x100 viewBox, no matter how thick --circular-thickness is. */
    r: calc(49px - var(--circular-thickness) * 0.5px);
  }

  .track {
    stroke: var(--track-color);
  }

  .progress-ring {
    stroke: var(--progress-color);
    stroke-linecap: round;
    stroke-dasharray: ${PATH_LENGTH};
    stroke-dashoffset: ${PATH_LENGTH};
    transition: stroke-dashoffset var(--progress-duration) ease;
  }

  :host(:not([percent])) .progress-ring {
    stroke: var(--indeterminate-color);
  }

  /* The X of the error glyph; revealed by [error]. */
  .error-mark {
    display: none;
    fill: none;
    stroke: var(--error-color);
    stroke-width: var(--circular-thickness);
    stroke-linecap: round;
  }

  .label {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #fff;
    mix-blend-mode: difference;
  }

  /* When the host carries its own inline styling (e.g. a color override), opt
     out of the blend trick and just inherit, so the override wins predictably. */
  :host([style]) .label {
    mix-blend-mode: initial;
    color: inherit;
  }

  /* Indeterminate (circular): no percent set — spin a fixed arc around the ring. */
  :host(:not([percent])) .ring {
    animation: indeterminate-rotate var(--indeterminate-duration) infinite linear;
  }

  :host(:not([percent])) .progress-ring {
    stroke-dashoffset: ${PATH_LENGTH * 0.75};
  }

  @keyframes indeterminate-rotate {
    0%   { transform: rotate(-90deg); }
    100% { transform: rotate(270deg); }
  }

  /* Error (circular): static full ring + X. Last so it beats the indeterminate rules. */
  :host([error]) .track { stroke: var(--error-color); }
  :host([error]) .progress-ring { display: none; }
  :host([error]) .ring { animation: none; }
  :host([error]) .error-mark { display: block; }
`;

const LINEAR_HTML = `
  <div class="bar"></div>
  <div class="text"><slot></slot></div>
`;

const CIRCULAR_HTML = `
  <div class="circular">
    <svg class="ring" viewBox="0 0 100 100">
      <circle class="track" cx="50" cy="50" r="${CIRCLE_RADIUS}"></circle>
      <circle class="progress-ring" cx="50" cy="50" r="${CIRCLE_RADIUS}" pathLength="${PATH_LENGTH}"></circle>
      <path class="error-mark" d="M37 37 L63 63 M63 37 L37 63"></path>
    </svg>
    <span class="label"><slot></slot></span>
  </div>
`;

let styleSheet = null;
function getStyleSheet() {
  if (!styleSheet) {
    styleSheet = new CSSStyleSheet();
    styleSheet.replaceSync(STYLES);
  }
  return styleSheet;
}

function clampPercent(value) {
  const number = Number(value);
  if (Number.isNaN(number)) {
    throw new TypeError(`progress-bar: percent must be numeric, got ${JSON.stringify(value)}`);
  }
  return Math.min(100, Math.max(0, number));
}

class ProgressBar extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this._percent = null;
    this._renderedMode = null;
  }

  connectedCallback() {
    this.render();
    this.setAttribute('role', 'progressbar');
    this.setAttribute('aria-valuemin', '0');
    this.setAttribute('aria-valuemax', '100');
    this.updateBar();
  }

  get percent() {
    return this._percent;
  }

  set percent(value) {
    if (value === null || value === undefined) {
      this.removeAttribute('percent');
    } else {
      this.setAttribute('percent', clampPercent(value));
    }
  }

  get error() {
    return this.hasAttribute('error');
  }

  set error(value) {
    this.toggleAttribute('error', Boolean(value));
  }

  get indeterminate() {
    return !this.hasAttribute('percent');
  }

  get mode() {
    return this.getAttribute('mode') === 'circular' ? 'circular' : 'linear';
  }

  set mode(value) {
    this.setAttribute('mode', value);
  }

  static get observedAttributes() {
    return ['percent', 'mode'];
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (name === 'percent') {
      this._percent = newValue === null ? null : clampPercent(newValue);
    }
    if (name === 'mode') {
      this.render();
    }
    this.updateBar();
  }

  updateBar() {
    if (this.mode === 'circular') {
      const ring = this.shadowRoot?.querySelector('.progress-ring');
      if (ring) {
        ring.style.strokeDashoffset = this.indeterminate
          ? ''
          : String(PATH_LENGTH * (1 - this._percent / 100));
      }
    } else {
      const bar = this.shadowRoot?.querySelector('.bar');
      if (bar) {
        // Leave width to the indeterminate CSS animation when unknown.
        bar.style.width = this.indeterminate ? '' : `${this._percent}%`;
      }
    }

    if (this.indeterminate) {
      this.removeAttribute('aria-valuenow');
    } else {
      this.setAttribute('aria-valuenow', String(this._percent));
    }
  }

  render() {
    const mode = this.mode;
    if (this._renderedMode === mode) {
      return;
    }
    this._renderedMode = mode;
    this.shadowRoot.adoptedStyleSheets = [getStyleSheet()];
    this.shadowRoot.innerHTML = mode === 'circular' ? CIRCULAR_HTML : LINEAR_HTML;
  }
}

if (!customElements.get('progress-bar')) {
  customElements.define('progress-bar', ProgressBar);
}

export default ProgressBar;
