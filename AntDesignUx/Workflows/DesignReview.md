# DesignReview Workflow

Review an existing interface for Ant Design UX compliance and best practices.

## Step 1: Load Context

Read the following context files before reviewing:
- `ComponentRules.md` - Do/Don't for all components
- `LayoutGuide.md` - Spacing, typography, color, shadow rules
- `FeedbackPatterns.md` - Feedback and messaging patterns
- `CopywritingGuide.md` - Text and tone rules

## Step 2: Identify the Target

Ask the user to specify:
1. Which file(s) or component(s) to review
2. Any specific concerns or focus areas

## Step 3: Review Checklist

Evaluate the interface against these categories:

### Buttons & Actions
- [ ] Only one primary button per group
- [ ] Button labels use verbs
- [ ] Buttons ordered by importance
- [ ] Danger buttons used for destructive actions
- [ ] Adequate spacing between button groups

### Forms
- [ ] Single-column vertical layout used
- [ ] Consistent components for same data types
- [ ] Helpful placeholders (not redundant)
- [ ] Appropriate layout for item count (basic/step/grouped)
- [ ] Inline validation for errors

### Data Display
- [ ] Correct list type (Table/List/Card) for the use case
- [ ] Empty states handled with prompts and actions
- [ ] Pagination present for long lists
- [ ] Clickable titles for navigation to details

### Navigation
- [ ] Appropriate nav type for menu count
- [ ] Breadcrumbs when hierarchy >= 3 levels
- [ ] No back button + breadcrumbs simultaneously

### Feedback
- [ ] Appropriate feedback component for urgency level
- [ ] Error messages explain what + why + next action
- [ ] No stacked messages/notifications
- [ ] Destructive operations have confirmation

### Layout & Spacing
- [ ] 8px grid compliance
- [ ] Proximity creates correct visual groupings
- [ ] Strong contrast for hierarchy (not subtle)
- [ ] Shadow levels used consistently

### Copywriting
- [ ] User-centered language
- [ ] Consistent terminology
- [ ] No jargon or overly technical text
- [ ] Sentence case for titles/labels

### Anti-Fatigue (Extended Use)
- [ ] Neutral color palette with controlled saturation
- [ ] Adequate whitespace to reduce visual density
- [ ] No excessive animations or moving elements
- [ ] Information hierarchy reduces scanning effort
- [ ] Moderate challenge level (not overwhelming, not trivial)

## Step 4: Report Findings

Format the review as:

```
## Design Review: [Component/Page Name]

### Score: X/10

### Critical Issues (Must Fix)
1. [Issue] -> [Specific fix with component/token reference]

### Warnings (Should Fix)
1. [Issue] -> [Recommendation]

### Suggestions (Nice to Have)
1. [Suggestion]

### What's Working Well
1. [Positive observation]
```

## Step 5: Provide Fix Examples

For each critical issue, provide a concrete code example showing the correct implementation.
