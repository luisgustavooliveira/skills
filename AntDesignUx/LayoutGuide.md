# Layout & Visual Design Guide

Standard Operating Procedures for spacing, typography, color, shadow, and motion in Ant Design interfaces.

---

## Spacing System (8px Grid)

### Formula
`y = 8 + 8 * n` where n >= 0

### Standard Spacing Scale
| Name | Value | Usage |
|------|-------|-------|
| Small | 8px | Tight grouping, related elements |
| Medium | 16px | Default separation between form items |
| Large | 24px | Section separation, card padding |

### DO
- Use 8px increments for ALL vertical spacing
- Use the **24-column grid** for horizontal layout (1440px canvas)
- Keep gutters fixed width during responsive resizing
- Use **proximity** to create visual groups: closer = related, farther = separate
- Apply **3 spacing levels** to create clear visual hierarchy

### DON'T
- Don't use arbitrary spacing values (e.g., 13px, 17px, 25px)
- Don't mix spacing scales inconsistently across the same page
- Don't rely solely on dividers when spacing can convey grouping

---

## Typography

### Font Stack
```css
font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
  'Helvetica Neue', Arial, 'Noto Sans', sans-serif,
  'Apple Color Emoji', 'Segoe UI Emoji', 'Noto Color Emoji';
```

### Base Size
- **14px** base font size (optimized for 50cm screen reading distance)
- **22px** base line-height for 14px text

### Font Hierarchy
| Token | Usage |
|-------|-------|
| `colorTextHeading` | Page and section titles |
| `colorText` | Body text, primary content |
| `colorTextSecondary` | Supporting information, descriptions |
| `colorTextDisabled` | Disabled states, inactive elements |

### Font Weight
| Weight | Value | Usage |
|--------|-------|-------|
| Regular | 400 | Default body text |
| Medium | 500 | Emphasis, subheadings |
| Semibold | 600 | Bold English words only |

### DO
- Limit to **3-5 font sizes** per interface
- Use the pentatonic scale for font size progression
- Maintain minimum **7:1 contrast ratio** (WCAG AAA)
- Use sentence case for headlines, titles, labels, menus, buttons

### DON'T
- Don't use more than 5 different font sizes in one system
- Don't capitalize entire words or phrases (harder to scan)
- Don't use font weight alone to create hierarchy (combine with size/color)

---

## Color System

### Brand Color
- Primary: `#1677ff` (Ant Design Blue, 6th depth of base palette)
- Use `@ant-design/colors` for programmatic palette generation

### Functional Colors
| Purpose | Usage |
|---------|-------|
| Success | Positive confirmation, completed states |
| Error | Errors, destructive actions, validation failures |
| Warning | Caution, attention-needed states |
| Info | Informational, neutral notices |
| Link | Interactive text, navigation |

### Neutral Colors
- Text, borders, backgrounds follow a defined gray scale
- Minimum **7:1 contrast ratio** for all text against background

### DO
- Derive all colors from the seed token `colorPrimary`
- Use semantic color tokens (not raw hex values) in components
- Use status colors consistently: green=success, red=error, yellow=warning, blue=info
- Test color combinations for accessibility compliance

### DON'T
- Don't use raw hex colors directly; use design tokens
- Don't create custom grays outside the neutral palette
- Don't rely on color alone to convey meaning (add icons/text)
- Don't use more than 3-4 primary colors in one interface

---

## Shadow System (4 Levels)

| Level | Usage | Example |
|-------|-------|---------|
| **0** | Baseline, grounded elements | Input boxes, default cards |
| **1** | Low elevation, hover/click states | Cards on hover, raised elements |
| **2** | Medium elevation, expanding panels | Dropdowns, popovers, expanding content |
| **3** | High elevation, independent layers | Modals, dialogs, floating elements |

### DO
- Use shadows to create **depth hierarchy** (not decoration)
- Apply consistent shadow direction per component type
- Use Level 2 for dropdowns and expanding panels
- Use Level 3 only for modals and high-priority overlays

### DON'T
- Don't mix shadow levels arbitrarily on the same plane
- Don't use shadows on every element (creates visual noise)
- Don't create custom shadow values outside the 4-level system

---

## Motion & Animation

### Three Principles
1. **Natural**: Based on laws of nature, smooth and intuitive
2. **Performant**: Minimal transition time, purposeful
3. **Concise**: Meaningful and justified, never over-fancy

### DO
- Use motion to provide feedback on user actions
- Keep transitions under 300ms for perceived responsiveness
- Use easing curves that mimic natural deceleration
- Animate only properties that don't trigger layout recalculation (transform, opacity)

### DON'T
- Don't add animation for decoration without functional purpose
- Don't use bouncing, spinning, or flashy effects in enterprise UIs
- Don't animate elements that are not in the user's focus area
- Don't block user interaction during animations

---

## Visual Contrast Principles

### DO
- Emphasize **one primary action** per area using visual weight
- Use contrast of size, color, and weight to create hierarchy
- Weaken secondary elements instead of only strengthening primary ones
- Use **status colors** (dots, badges) to differentiate states

### DON'T
- Don't make contrast subtle; it must be **strong** to be effective
- Don't emphasize both options equally when the system recommends one
- Don't use visual emphasis to influence decisions that should be neutral (e.g., Accept vs Reject in legal contexts should use default buttons for both)

---

## Responsive Layout Adaptation

### Two Common Patterns
1. **Left-Right Layout**: Fixed sidebar navigation, scalable content area
2. **Top-Bottom Layout**: Fixed margins, scalable center content

### DO
- Design for **1440px** as base canvas width
- Use the 24-column grid for responsive layouts
- Keep navigation fixed, scale content area
- Test at common breakpoints: 1280px, 1440px, 1920px

### DON'T
- Don't use fixed pixel widths for content areas
- Don't break the grid system for one-off layouts
- Don't hide essential content at smaller breakpoints without alternative access
