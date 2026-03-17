---
name: AntDesignUx
description: Expert UI/UX guidance using Ant Design System. USE WHEN ant design, antd, ui design, ux design, interface design, component selection, form design, layout design, create page, create interface, build ui, design system, ant design best practices, component usage.
---

# AntDesignUx

Expert UI/UX skill for creating functional, elegant, aesthetically pleasing, and non-fatiguing interfaces using Ant Design. Guides correct component usage, design best practices, and the creation of interfaces that keep users engaged for hours without cognitive fatigue.

## Workflow Routing

**When executing a workflow, output this notification:**

```
Running the **WorkflowName** workflow from the **AntDesignUx** skill...
```

| Workflow | Trigger | File |
|----------|---------|------|
| **DesignReview** | "review ui", "check design", "review interface" | `Workflows/DesignReview.md` |
| **ComponentGuide** | "which component", "component selection", "what component to use" | `Workflows/ComponentGuide.md` |
| **BuildInterface** | "create page", "build interface", "design page", "create ui" | `Workflows/BuildInterface.md` |

## Quick Reference

**Core Design Values:** Natural, Certain, Meaningful, Growing

**Key Principles:**
- Minimize cognitive load: use familiar patterns, consistent layouts
- One primary action per view: guide users to the right action
- 8px grid system: all spacing follows `y = 8 + 8*n` formula
- 14px base font: optimized for screen reading at 50cm
- WCAG AAA compliance: 7:1 contrast ratio minimum

**Full Documentation:**
- Component Do/Don't rules: `ComponentRules.md`
- Layout and spacing guide: `LayoutGuide.md`
- Feedback and messaging patterns: `FeedbackPatterns.md`
- Copywriting and tone: `CopywritingGuide.md`

## Examples

**Example 1: Design a form page**
```
User: "Create a settings form with 10 fields"
-> Invokes BuildInterface workflow
-> Recommends grouped form layout (7-15 items = grouping recommended)
-> Applies vertical single-column layout for maximum efficiency
-> Uses consistent component types for same data kinds
-> Validates against Do/Don't rules
```

**Example 2: Review an existing interface**
```
User: "Review the dashboard design for UX issues"
-> Invokes DesignReview workflow
-> Checks button hierarchy, form patterns, navigation
-> Validates spacing, contrast, and visual hierarchy
-> Reports violations with specific fix recommendations
```

**Example 3: Choose the right component**
```
User: "I need to let users pick from 12 options"
-> Invokes ComponentGuide workflow
-> Radio: 2-5 options (all visible) -> Not suitable
-> Dropdown/Select: 5+ options -> Recommended
-> Provides implementation guidance
```
