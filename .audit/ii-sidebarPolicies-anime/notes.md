# ii-sidebarPolicies-anime — notes

**Opening it.** `qs -c ii ipc call sidebarLeft open`, then the bookmark icon in the tab row
(about `336,82` on this 1920x1080 screen). The panel pins Hermes on open, so every restart or
reload lands there. Check that the tab is Anime before typing: one test query went to Hermes
this session. Before driving it with `ydotool`, check that `hyprctl layers -j` lists
`quickshell:sidebarLeft`. A live reload closes the sidebar, and keystrokes then go to the
window behind it.

**Providers, as of 2026-09-26, from this network.**
- yande.re: its edge resets about half the connections, on both `yande.re` and
  `assets.yande.re`. The search retries up to twice on status 0 and each tile reloads its
  image up to twice. Without the tile retry about a third of the grid stayed blank.
- Danbooru: every path, `/posts` HTML included, is a Cloudflare managed challenge whatever the
  User-Agent. Only `/` answers. Nothing client-side gets past that. It is reported as such now.
  Recheck from another network before assuming it is global.
- Gelbooru: 401 without `api_key` and `user_id`. There are config options for them now
  (`sidebar.booru.gelbooru.*`), with no settings UI. Not tested with a real key.
- Zerochan: the Chrome User-Agent in `networking.userAgent` gets a browser check. A
  descriptive one passes. An alias tag (`landscape` → `Scenery`) redirects without `?json`
  and lands on HTML, which shows the generic failure. Downloads are the 600px JPEG, because
  the full image's extension is only in a per-post `?json` request.
- waifu.im: `/search` is behind Cloudflare now. `/images` uses PascalCase parameters and
  `IsNsfw=All` rather than `null`.

**Verified live.** The grid's rounding with one mask, rows flush with both edges, the menu
flipping left near the right edge and up near the input, outside press (consumed), wheel
(closes and scrolls), Escape, and a real Download. The file name had spaces and was saved
and notified correctly. The test file and the `~/Pictures/homework` it created were removed.

**Rejected.** Rounding tiles with painted corner pieces (`RoundCorner`): they only match an
opaque card, and `colLayer1` is translucent with transparency on. `ClippingRectangle` costs
the same two framebuffers per tile as the mask it would replace.

**Not done.** The agy/Gemini vision pass. The menu has no arrow-key navigation, and tiles are
not in the tab order; that was accepted in the brief.

**For the cohesion pass (motion).** The image menu opens and closes on `ArrowPopupMotion` from
the click point. It used to be an opacity-only fade on `elementMoveFast` that the `Loader`
destroyed before the fade-out could play.
