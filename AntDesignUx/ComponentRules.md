# Component Rules - Do & Don't

Standard Operating Procedures for correct Ant Design component usage. Load this file when building or reviewing interfaces.

---

## Buttons

### DO
- Use **one primary button per group** to emphasize the main action (complete/recommend)
- Place buttons following reading patterns (F-shaped or Z-shaped)
- Order buttons by importance: most important left/top, less important right/bottom
- Use **verbs** for button labels (Publish, Login, Register, Delete)
- Provide sufficient spacing between button groups to avoid confusion with Toggle
- Use **Danger Button** for destructive actions to warn users of risks
- Set "Cancel" as primary when system does not recommend deletion
- Use **Dashed Button** to guide users to add content in an area
- Use **Ghost Button** on dark or colored backgrounds
- Limit to **1 Call to Action** button per screen
- Collapse less important buttons into dropdown menus, ordered by importance

### DON'T
- Don't put more than 1 primary button in the same group
- Don't put 2 icons in the same button
- Don't place button groups without spacing (confused with Toggle Button)
- Don't use nouns as button labels (use "Save" not "Settings")
- Don't add dividers between buttons in the same group
- Don't use Default Button type if a clear primary action exists

---

## Forms

### DO
- Use **single-column vertical layout** for maximum completion efficiency
- Use **consistent components** for the same type of content
- Provide hints/placeholders to help users understand expected input
- Use **help descriptions** (tooltip or inline text) for uncommon terms
- Group forms by content when items > 7
- Use **Step Form** for clear linear processes
- Use tabs when settings items > 15
- Provide save/undo/cancel mechanisms for complex forms
- Validate inline (next to the field) for immediate feedback
- Use appropriate editable patterns based on item count:
  - 2-3 items: Dynamic increase/decrease (inline)
  - 2-5 items: Editable table
  - 6-8 items: Collapsible panels
  - 8+ items: Drawer editing

### DON'T
- Don't use different components for the same type of content in one form
- Don't use incomprehensible jargon in form titles/prompts
- Don't make labels too long (increases comprehension cost)
- Don't use redundant placeholder text (e.g., "Name" field with placeholder "Please enter your name")
- Don't use multi-column layouts within a single form area (confuses reading order)
- Don't mix instant-effect and submission-effect modes on the same settings page

---

## Data Entry Components

### Radio Button
- **DO:** Use for 2-5 mutually exclusive options where all are visible
- **DON'T:** Use for more than 5 options (use Dropdown instead)
- **DON'T:** Use for fewer than 2 options

### Checkbox
- **DO:** Use for multiple selections from several options
- **DO:** Use single checkbox for binary toggle (with submit action)
- **DON'T:** Confuse with Switch (checkbox needs submit, switch is immediate)

### Switch
- **DO:** Use for immediate state changes (Enable/Disable, Allow/Disallow)
- **DO:** Display clear inline labels for both states
- **DON'T:** Pair Switch with a submit button (it takes effect immediately)
- **DON'T:** Use Switch when the change requires confirmation

### Dropdown / Select
- **DO:** Use when there are more than 5 options
- **DO:** Sort options logically and display content fully
- **DON'T:** Use for fewer than 5 options (use Radio instead)

### Slider
- **DO:** Use for intensity/grade values (volume, brightness, saturation)
- **DO:** Pair with NumberInput when precise values are needed
- **DON'T:** Use when exact numerical precision is the primary goal

### Transfer
- **DO:** Use for moving elements between two columns intuitively
- **DON'T:** Use when the source list is very small (use Checkbox instead)

### DatePicker
- **DO:** Use for visual date/date-range selection
- **DO:** Set reasonable default dates to reduce input effort

### Input
- **DO:** Provide placeholder hints for expected format/content
- **DO:** Use specific input types (number, URL, password) when appropriate
- **DON'T:** Leave inputs without any contextual hints

### Upload
- **DO:** Display upload progress
- **DO:** Specify accepted file formats and size limits
- **DO:** Use thumbnail upload for images, click upload for single files
- **DO:** Use drag-and-drop for better UX on large upload areas
- **DON'T:** Allow unlimited file sizes without warning

---

## Data Display

### Table vs List vs Card List

| Criteria | Table | List | Card List |
|----------|-------|------|-----------|
| **Best for** | Complex data comparison | Quick scanning overview | Visual presentation |
| **Layout** | Matrix (rows x cols) | Vertical hierarchical | Grid |
| **Browsing** | Horizontal + Vertical | Vertical | No specific order |
| **Space** | Needs wide area | Works in limited space | Flexible grid |

### DO
- Use **Table** when users need to compare data across multiple attributes
- Use **List** when space is limited (sidebars, popups, dropdowns)
- Use **Card List** when each item deserves equal visual attention
- Click **title** to navigate to details (not the entire row for tables)
- Provide **empty states** with clear prompts and suggested actions
- Use **pagination** by default; infinite scroll only when items are top-weighted
- Cache browsing position when user navigates away and returns
- Mark browsed items in the list
- Use **dashed button** for inline "New" actions
- Highlight newly created items briefly after creation

### DON'T
- Don't leave empty states without any prompt or guidance
- Don't use infinite scroll when users need to locate specific items
- Don't remove pagination when content exceeds one page

---

## Navigation

### DO
- Use **Sidebar Navigation** for enterprise products (6+ menu items, 1-3 levels)
- Use **Top Navigation** for 2-7 items, 1-2 levels
- Use **Breadcrumbs** when hierarchy is 3+ levels deep
- Keep information architecture shallow, flat, and wide
- Provide multiple entry points to the same destination
- Place utility tools (search, notifications, help) in upper right
- Use **Step Bar** for linear multi-step processes

### DON'T
- Don't make users follow narrow hover paths for navigation menus
- Don't force step-by-step menu opening to find items
- Don't place in-page operations in utility tool area
- Don't show breadcrumbs AND back button simultaneously (choose one)
- Don't use breadcrumbs when hierarchy is fewer than 3 levels

---

## Feedback & Messages

### DO
- Use **Global Message** for brief, non-interrupting success feedback
- Use **Modal Dialog** for important results requiring acknowledgment
- Use **Notification** for backend process failures requiring decisions
- Use **Inline text + Illustration** for end-of-process success/failure
- Use **Form Validation** inline for field-level errors
- Use **Alert** for critical errors requiring immediate attention
- Match feedback urgency to the action's importance

### DON'T
- Don't use Modal for trivial success messages (use Message instead)
- Don't use Notification for simple, expected outcomes
- Don't leave errors without clear next-step guidance
- Don't use generic "Error occurred" messages without context
- Don't say "Failure" coldly; use "Unable to complete" and explain next steps

---

## Empty States

### DO
- Provide clear explanation of WHY the state is empty
- Offer suggested actions or next steps
- Use illustrations to make empty states less jarring
- For new users: include feature guides and help documents
- For completed tasks: use simple graphic + confirmation message
- For no-data: combine illustration + prompt + suggested action

### DON'T
- Don't show a blank area with no guidance
- Don't omit the empty state entirely
- Don't show overly complex empty states for simple completion scenarios
