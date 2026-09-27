# settings-HermesConfig — brief

**Purpose.** Edit Hermes the agent itself (`~/.hermes/config.yaml` through the gateway's
`config.get`/`config.set`), see its account, and manage the credential vault.

**Primary action.** Persona and system prompt.

**Hierarchy.** Behaviour, Display, **Agent info** (Approvals, Profile home, Provider,
Project), Account, Credential vault. Approvals used to be a section of its own holding two
lines of read-only text. It is Agent info's first fact, and its "set from the sidebar"
line is the subsection tooltip.

**Reference.** Android 16 Settings → Google → (account page): editable preferences
first, read-only facts grouped under one heading.

**Interaction.** The remove-item dialog is latched. It enters by being created shut and
opened a turn later, and its exit plays out before the `Loader` releases. It used to be
`active: removeTarget !== null`, destroyed on the frame Cancel or Remove cleared the
target. The item name is copied at open, so the exit does not read "this item".

**Edge states.** Gateway down: the notice alone (unchanged). A key the agent will not
answer: `UnavailableHint` under its control (unchanged). No vault sources or items: their
empty lines (unchanged).

**Cost.** None.

**Delete.** The Approvals section and the stale `TODO(integrator)` on the page index,
which `check-settings-search.py` now guards.

**Out of scope.** `HermesService`, and the sidebar's approvals picker.
