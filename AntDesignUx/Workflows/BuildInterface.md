# BuildInterface Workflow

Guide the creation of a new interface following Ant Design best practices for functional, elegant, and non-fatiguing design.

## Step 1: Load Context

Read ALL context files before building:
- `ComponentRules.md` - Do/Don't for all components
- `LayoutGuide.md` - Spacing, typography, color, shadow rules
- `FeedbackPatterns.md` - Feedback and messaging patterns
- `CopywritingGuide.md` - Text and tone rules

## Step 2: Understand Requirements

Clarify with the user:
1. **Page type**: Form, list/table, dashboard, detail, settings, result?
2. **Data**: What entities and fields are involved?
3. **Actions**: What can users do? (CRUD, filter, export, etc.)
4. **User role**: Admin, operator, end-user?
5. **Context**: Where does this page sit in the navigation?

## Step 3: Choose Page Template

| Page Type | Template | When to Use |
|-----------|----------|-------------|
| Simple form | Basic Form | Few items, quick task |
| Complex form | Step Form | Clear linear process |
| Large form | Grouped Form | Many items, categorizable |
| Settings | Settings Page | Infrequent changes |
| Data listing | Table/List/Card | Browse and manage data |
| Detail view | Descriptions + Cards | View single entity |
| Dashboard | Card grid + Statistics | Overview and monitoring |
| Result | Result page | End of process feedback |
| Login/Register | Auth template | User authentication |

## Step 4: Apply Design Principles

### Anti-Fatigue Design (Critical for Extended Use)

These principles ensure users can work for hours without cognitive exhaustion:

1. **Visual Breathing Room**
   - Use generous whitespace (24px+ between sections)
   - Don't pack information densely; let the eye rest
   - Use Card grouping to create distinct visual zones

2. **Controlled Saturation**
   - Use neutral backgrounds (`colorBgLayout`, `colorBgContainer`)
   - Reserve saturated colors for actionable elements only
   - Avoid large areas of bright or saturated color

3. **Predictable Patterns**
   - Consistent layout across similar pages
   - Same component for same interaction type everywhere
   - Users build muscle memory, reducing conscious effort

4. **Progressive Disclosure**
   - Show essential info first, details on demand
   - Use Collapse, Tabs, or Drawer for secondary content
   - Don't overwhelm with everything at once

5. **Clear Visual Hierarchy**
   - One focal point per view area
   - Strong contrast between levels (not subtle)
   - Use typography scale + color tokens for hierarchy

6. **Minimal Cognitive Interruptions**
   - No unnecessary animations or blinking elements
   - Use `message` for brief feedback (auto-dismiss)
   - Reserve `Modal` for truly important decisions

7. **Flow State Support** (from Ant Design "Meaningful" value)
   - Moderate challenge level in interactions
   - Don't distract with unnecessary UI elements
   - Provide immediate feedback for every action
   - Let users focus on task, not interface

## Step 5: Build the Interface

### Layout Structure
```tsx
<ConfigProvider theme={{ token: { colorPrimary: '#1677ff' } }}>
  <Layout>
    <Layout.Sider>  {/* Sidebar nav for enterprise */}
    <Layout>
      <Layout.Header>  {/* Page header / breadcrumbs */}
      <Layout.Content>  {/* Main content area */}
      <Layout.Footer>   {/* Optional footer actions */}
    </Layout>
  </Layout>
</ConfigProvider>
```

### Implementation Checklist

- [ ] **Layout**: 24-column grid, 8px spacing multiples
- [ ] **Navigation**: Correct type for menu count and depth
- [ ] **Buttons**: One primary per group, verb labels, correct ordering
- [ ] **Forms**: Single column, consistent components, inline validation
- [ ] **Tables/Lists**: Correct type for data, pagination, empty states
- [ ] **Feedback**: Appropriate component per urgency level
- [ ] **Empty States**: Illustration + reason + suggested action
- [ ] **Copywriting**: User-centered, concise, sentence case
- [ ] **Theming**: Design tokens used (not raw hex), semantic tokens
- [ ] **Accessibility**: WCAG AAA contrast, ARIA labels, keyboard navigation
- [ ] **Anti-Fatigue**: Whitespace, controlled color, progressive disclosure

## Step 6: Self-Review

Before delivering, run the DesignReview checklist against the built interface. Fix any violations before presenting to the user.

## Step 7: Deliver

Present the implementation with:
1. Complete code
2. Brief explanation of key design decisions
3. Any trade-offs made and why
