// Runs after the libraries: gives them GlassChat's look before the page draws.
(function () {
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  if (window.Chart) {
    Chart.defaults.color = dark ? '#a1a1a6' : '#6e6e73';
    Chart.defaults.borderColor = dark ? 'rgba(255,255,255,.12)' : 'rgba(0,0,0,.1)';
    Chart.defaults.font.family = '-apple-system, system-ui, sans-serif';
    Chart.defaults.animation = false;
  }
  if (window.mermaid) {
    mermaid.initialize({ startOnLoad: true, theme: dark ? 'dark' : 'neutral', securityLevel: 'strict' });
  }
})();
