# ii-sidebarPolicies-anime — brief

**Purpose.** Browse a booru's results for some tags in the left sidebar, and open or save the
one image worth keeping.

**Primary action.** Picking an image. The image *is* the control: a click (left or right)
anywhere on it opens its menu at the pointer — Open file link, Go to source, Download. It
used to be a 30px `more_vert` button in each image's corner, which covered the art and cost
every image a `RippleButton` layer, while a click on the image itself did nothing.

**Hierarchy.** The images first, as a justified grid. Then the provider chip and the tag
chips above them, which say what was searched. Then "Page N" and "Next page".

**Reference.** The Google Photos grid (justified rows of rounded tiles, gaps on the 4dp
grid, the tile is the tap target) with the Launcher3 `ArrowPopup` menu that Android puts on a
long-press, which is DESIGN.md's popup recipe.

**Interaction.**
- *Tile.* Hover and pressed films via `StateOverlay` (onSurface), pointing-hand cursor, the
  tag tooltip as before. No focus state: tiles are not in the tab order, and nothing on this
  page is keyboard-navigable except the input field.
- *Rounding.* Every tile is `rounding.small` inside a response padded 4, and the response
  owns **one** `OpacityMask` whose mask is the same row model drawn as rounded rectangles.
  The rows are plain `Column`/`Row` on both sides so the mask and the tiles land on the same
  pixels. Rows fill the width exactly; they stopped 5px short of the right edge because the
  row width subtracted one gap too many.
- *Menu.* One per response, not one per image. `ArrowPopupMotion` on a zero-size pivot at
  the click point, so it grows out of the corner nearest the click. It hangs right and down
  of the pointer when there is room, else flips, then clamps inside the window by
  `elevationMargin`. The card is drawn from the window's content item, as `CalendarPopup`
  does, so neither the list's clip nor the next response paints over it. Dismiss: any press
  outside (consumed), a wheel outside (closes and lets the scroll through, since the card
  would otherwise sit on a stale point), Escape, a menu row, or the sidebar closing. Focus
  goes back to the tag field.

**Edge states.**
- *Loading:* each tile is a `colLayer2` block at its final size, and the image fades in on
  `StyledImage`'s own effects spec. The grid never reflows as images arrive, since sizes come
  from the API.
- *Error / message:* the Markdown message line, unchanged.
- *One image* (waifu.im often returns one): one full-width tile at the same radius as the
  rest. It was radius 50, a literal.
- *Empty:* the host's `PagePlaceholder` — out of this row.

**Cost.** Per response: one `OpacityMask` (grid) instead of an image mask and a
`RippleButton` mask per image, which was forty offscreen passes for a page of twenty. The tag
strip's `OpacityMask` goes (the chips are rounded themselves; `clip` holds the strip). One
menu `StyledRectangularShadow` per response, only while it is shown.

**Delete.** The per-image `more_vert` button and per-image menu `Loader`. The raw `Button`
root. The tile's own `OpacityMask`. The response's `colLayer1` fill, which sat on the page's
`colLayer1` and has never been visible. The literal `50` radius and the 10/5/30 paddings.

**Security (trust boundary).** Image URLs and file names come from a remote API and went into
`bash -c` inside single quotes. Download passes them as positional arguments now, and
`ImageDownloaderProcess` escapes its URL as it already did its path. A file name decoded from
the URL could contain `/`; it is flattened. The notification named `downloadPath` even for an
NSFW image saved to `nsfwPath`.

**Out of scope.** `Anime.qml` (the list, input, commands, placeholder) and `ApiCommandButton`
belong to `ii-sidebarPolicies-root`. `services/Booru.qml`. The strip of list content that
shows below the input box is the host's, noted there.
