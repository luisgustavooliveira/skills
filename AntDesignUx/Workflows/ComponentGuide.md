# ComponentGuide Workflow

Help users select the correct Ant Design component for their use case.

## Step 1: Load Context

Read `ComponentRules.md` for component selection criteria.

## Step 2: Understand the Need

Gather from the user:
1. What data or action is involved?
2. How many options/items?
3. Is the context a form, display, navigation, or feedback?
4. Any space constraints?

## Step 3: Component Selection Decision Trees

### Selecting from options (user picks one or more values)

```
How many options?
├── 2 options (binary) -> Switch (if immediate effect) or Radio
├── 2-5 options (single select) -> Radio Button
├── 5+ options (single select) -> Select / Dropdown
├── Multiple select (few options) -> Checkbox
├── Multiple select (many options, two groups) -> Transfer
└── Continuous value range -> Slider (+ InputNumber for precision)
```

### Entering text data

```
What kind of text?
├── Short, single line -> Input
├── Long, multi-line -> TextArea
├── With autocomplete suggestions -> AutoComplete
├── Mentioning users/entities -> Mentions
├── Numeric value -> InputNumber
├── Date/time -> DatePicker / TimePicker
├── Color -> ColorPicker
└── Hierarchical selection -> Cascader / TreeSelect
```

### Displaying data collections

```
What is the priority?
├── Compare across attributes -> Table
├── Quick scan / overview -> List
├── Visual presentation / equal weight -> Card List (grid)
├── Hierarchical structure -> Tree
├── Key-value pairs -> Descriptions
├── Sequential events -> Timeline
└── Progress/completion -> Progress / Steps
```

### Providing feedback

```
What is the urgency?
├── Brief, auto-dismiss -> message
├── Needs acknowledgment, stays visible -> notification
├── Blocks workflow, critical -> Modal
├── Persistent in-page warning -> Alert
├── Field-level error -> Form validation (inline)
├── End-of-process result -> Result page
└── Confirm before action -> Popconfirm (simple) / Modal.confirm (complex)
```

### Navigation

```
How many items and levels?
├── 2-7 items, 1-2 levels -> Top Navigation (Menu horizontal)
├── 6+ items, 1-3 levels -> Sidebar Navigation (Menu vertical)
├── Step-by-step process -> Steps
├── Long single page -> Anchor
├── Hierarchy >= 3 levels -> Breadcrumb
├── Content categories on same page -> Tabs
├── Few toggle options (2-5) -> Segmented
└── Quick actions, floating -> FloatButton
```

### Layout & Structure

```
What are you organizing?
├── Page sections -> Layout (Header/Sider/Content/Footer)
├── Horizontal alignment -> Flex / Space
├── Grid of items -> Grid (Row/Col, 24 columns)
├── Content separation -> Divider
├── Grouped content -> Card
├── Collapsible sections -> Collapse
└── Overlay content -> Modal / Drawer
```

## Step 4: Provide Recommendation

For each recommendation, include:
1. **Component name** and import path
2. **Why** this component fits the use case
3. **Key props** to configure
4. **Do/Don't** reminders specific to the choice
5. **Code example** showing correct usage

## Step 5: Alternatives

Always mention 1-2 alternatives with tradeoffs:
- "If you need X instead, consider Y because Z"
