(function () {
  if (typeof window === 'undefined') return;
  if (window.location.pathname.startsWith('/super_admin')) return;

  const BRAND_REPLACEMENTS = [
    [/\bChatwoot\b/g, 'MarkChat'],
    [/\bCaptain\b/g, 'MarkCopilot'],
    [/https?:\/\/(www\.|app\.)?chatwoot\.com[^\s"']*/gi, 'https://markchat.co.ke'],
    [/https?:\/\/chwt\.app[^\s"']*/gi, 'https://markchat.co.ke'],
  ];

  function scrubText(str) {
    if (!str || typeof str !== 'string') return str;
    let out = str;
    for (const [re, rep] of BRAND_REPLACEMENTS) {
      out = out.replace(re, rep);
    }
    return out;
  }

  function scrubTitle() {
    if (document.title) {
      const next = scrubText(document.title);
      if (next !== document.title) document.title = next;
    }
  }

  function scrubNode(root) {
    if (!root) return;
    if (root.nodeType === Node.TEXT_NODE) {
      const next = scrubText(root.nodeValue);
      if (next !== root.nodeValue) root.nodeValue = next;
      return;
    }
    if (root.nodeType !== Node.ELEMENT_NODE) return;

    const tag = root.tagName;
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'TEXTAREA' || tag === 'INPUT') {
      if (root.placeholder) {
        const nextPh = scrubText(root.placeholder);
        if (nextPh !== root.placeholder) root.placeholder = nextPh;
      }
      return;
    }

    for (const attr of ['title', 'aria-label', 'alt']) {
      if (root.hasAttribute && root.hasAttribute(attr)) {
        const val = root.getAttribute(attr);
        const next = scrubText(val);
        if (next !== val) root.setAttribute(attr, next);
      }
    }

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    let node;
    while ((node = walker.nextNode())) {
      const parentTag = node.parentElement && node.parentElement.tagName;
      if (parentTag === 'SCRIPT' || parentTag === 'STYLE' || parentTag === 'TEXTAREA') continue;
      const next = scrubText(node.nodeValue);
      if (next !== node.nodeValue) node.nodeValue = next;
    }
  }

  function boot() {
    scrubTitle();
    scrubNode(document.body);
    const observer = new MutationObserver((mutations) => {
      scrubTitle();
      for (const m of mutations) {
        if (m.type === 'characterData') {
          scrubNode(m.target);
        } else {
          for (const added of m.addedNodes) {
            scrubNode(added);
          }
        }
      }
    });
    if (document.body) {
      observer.observe(document.body, { childList: true, subtree: true, characterData: true });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();