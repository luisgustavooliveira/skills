---
name: ui-consistency-guardian
description: Apply QuantaPKI UI implementation standards with usability-first consistency checks. Use when creating or editing frontend React pages, components, forms, lists, loading/empty/error states, visual tokens, spacing, or API-driven UI behavior to enforce simplicity, intuitive usage, and component reuse.
---

# UI Consistency Guardian

Use this skill to convert UI edits into a repeatable implementation flow instead of ad-hoc styling decisions.

## Workflow

### 1. Identify Scope and Journey

- Classify the change as one or more journeys: `create`, `edit`, `list`, `details`, `search/filter`, `empty-first-use`.
- Define the primary user action in one sentence: `User opens X and completes Y`.
- Minimize friction: remove steps, avoid jargon, avoid hidden actions.

### 2. Reuse Before Creating

- Reuse existing shared components first (`FormGroup`, `Input`, `Select`, existing cards/lists/headers).
- Create new component only when no existing component covers the behavior.
- If creating a new component, design it for reuse in at least two flows and keep API narrow.

### 3. Apply Visual and Layout Rules

- Enforce `box-sizing: border-box` globally.
- Prefer CSS Grid as the default form layout strategy.
- Apply spacing scale consistently:
  - Section spacing: `24px`
  - Field/grid spacing: `16px` or `20px` (pick one per form area)
  - Label/input spacing: `6px`
- Apply typography and color tokens from `conductor/ui-standards.md`.
- Avoid hardcoded colors when a CSS variable exists.

### 4. Harden Data, States, and Feedback

- Treat API payloads as untrusted input.
- Validate arrays/objects before use (`Array.isArray(...) ? ... : []`).
- Separate valid empty state from true API failure.
- Always implement all user-visible states:
  - `loading`
  - `empty`
  - `error`
  - `success/content`
- Use clear, action-oriented empty and error messages.

### 5. Run the Usability Pass

- Verify one-pass comprehension:
  - Can a first-time user complete the primary action without documentation?
  - Are labels explicit and task-oriented?
  - Are primary and secondary actions visually distinct?
  - Are defaults safe and intuitive?
- Verify accessibility baseline:
  - Keyboard reachable actions
  - Clear focus cues
  - Touch target intent for interactive elements
- Verify consistency against sibling screens of the same journey.

### 6. Produce a Mandatory Change Report

After implementing UI changes, output a short report with this exact structure:

```md
UI Consistency Report
- Journey: <create|edit|list|details|...>
- Reused Components: <list>
- New Components: <list or "none">
- Standards Applied: <spacing|typography|tokens|layout|states|defensive-data>
- Usability Check: <passed/failed + notes>
- Exceptions: <none or justified deviation>
```

## References

- Source standard: `conductor/ui-standards.md`
- Journey checklist: `references/ui-implementation-playbook.md`

Load only the sections needed for the current journey.
