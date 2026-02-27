# UI Implementation Playbook

Use this file as a focused checklist based on the user journey being edited.

## Common Baseline

- Reuse existing components before creating new ones.
- Keep one visual language per screen (spacing, headings, control density).
- Prefer explicit labels and predictable placement for primary actions.
- Implement `loading`, `empty`, `error`, and `success/content` states.
- Validate API data defensively before rendering.

## Journey: Create/Edit Forms

- Use Grid for form structure and keep a single gap system.
- Keep `FormGroup` semantics for labels, required marker, and help text.
- Keep input sizing and focus behavior consistent with existing inputs.
- Use progressive disclosure: show advanced fields only when needed.
- Keep validation messages local, clear, and actionable.

## Journey: List and Search

- Show useful empty-first-use content with next action guidance.
- Distinguish "no results for current filter" from "no records exist yet".
- Keep row/card action hierarchy consistent (primary vs secondary).
- Preserve scanability (column alignment, concise labels, stable spacing).

## Journey: Details and Review

- Prioritize critical information first; relegate metadata to secondary areas.
- Keep section headers and spacing rhythm consistent across detail pages.
- Group related actions near relevant content.

## Journey: Error and Recovery

- Show errors only for real failures, not for valid empty payloads.
- Provide retry path when network/API failure occurs.
- Avoid leaking technical internals in user-facing messages.

## Decision Rule for New Components

Create a new component only when:

- Reuse of existing component creates more complexity than value, and
- The new component can be reused in at least one additional screen/journey.

Otherwise, extend existing shared components.
