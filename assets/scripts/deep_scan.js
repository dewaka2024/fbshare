// deep_scan.js — Scans all interactive elements on the current page.
// Returns a JSON array of element descriptors for the Page Inspector.
(function () {
  const scopes = [document];
  const dialogs = document.querySelectorAll(
    '[role="dialog"],[role="menu"],[role="listbox"],[aria-modal="true"]'
  );
  dialogs.forEach(d => scopes.push(d));

  const allEls = [];
  const seen = new Set();

  function isShareCountBtn(el) {
    const t = (el.innerText || '').trim();
    if (t.length === 0 || t.length > 10) return false;
    const tNum = t.replace(/[KkMm,]/g, '');
    if (isNaN(parseFloat(tNum)) || parseFloat(tNum) <= 0) return false;
    const parent = el.parentElement;
    if (!parent) return false;
    const ph = (parent.innerHTML || '').toLowerCase();
    const pa = (parent.getAttribute('aria-label') || '').toLowerCase();
    const gp = parent.parentElement;
    const gph = gp ? (gp.innerHTML || '').toLowerCase() : '';
    return ph.includes('share') || pa.includes('share') || gph.includes('share');
  }

  function isActionBarShareBtn(el) {
    const likeBtn = document.querySelector(
      '[aria-label="Like"],[aria-label="Likes"],[aria-label^="Like "]'
    );
    if (!likeBtn) return false;
    const row = likeBtn.closest('div[role="group"],ul,div');
    if (!row) return false;
    const btns = [...row.querySelectorAll('[role="button"],[tabindex="0"],button')]
      .filter(b => row === b.closest('div[role="group"],ul,div'));
    return btns.length >= 3 && btns[2] === el;
  }

  scopes.forEach(scope => {
    const candidates = scope.querySelectorAll(
      '[role="button"],[role="menuitem"],[role="option"],[role="checkbox"],' +
      '[role="listitem"],button,[tabindex="0"],[tabindex="-1"],[aria-label],' +
      'a[href],[role="link"]'
    );
    candidates.forEach(el => {
      const aria = el.getAttribute('aria-label') || '';
      const testId = el.getAttribute('data-testid') || '';
      const role = el.getAttribute('role') || el.tagName.toLowerCase();
      const tag = el.tagName.toLowerCase();
      const text = (el.innerText || el.textContent || '')
        .trim().replace(/\s+/g, ' ').substring(0, 80);
      const key = (aria + text + el.className).substring(0, 40);
      if (!key.trim()) return;
      if (seen.has(key)) return;
      seen.add(key);
      allEls.push(el);
    });
  });

  window.__scanEls = allEls;

  const result = allEls.map((el, i) => ({
    index: String(i),
    text: (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ').substring(0, 80),
    aria: el.getAttribute('aria-label') || '',
    testId: el.getAttribute('data-testid') || '',
    role: el.getAttribute('role') || el.tagName.toLowerCase(),
    tag: el.tagName.toLowerCase(),
    shareHint: isShareCountBtn(el) || isActionBarShareBtn(el),
  }));

  return JSON.stringify(result);
})();
