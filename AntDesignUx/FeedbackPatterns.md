# Feedback & Messaging Patterns

Standard Operating Procedures for user feedback, messaging, and empty states in Ant Design interfaces.

---

## Feedback Component Selection Matrix

| Scenario | Stay in Place | Redirect |
|----------|--------------|----------|
| **Success (brief)** | `message.success()` | - |
| **Success (important)** | `Modal` (success) | Result page with illustration |
| **Success (end of process)** | - | Result page + details |
| **Failure (field-level)** | Form validation inline | - |
| **Failure (critical)** | `Alert` (error type) | - |
| **Failure (action-level)** | `Modal` (error) | Result page + failure info |
| **Failure (background)** | `notification.error()` | - |
| **Warning** | `Modal.confirm()` | - |
| **Info (non-urgent)** | `message.info()` | - |
| **Background result** | `notification` | Notification center |

---

## Decision Flow

### Step 1: Determine Urgency
- **High urgency** (blocks workflow): Modal, Alert
- **Medium urgency** (needs attention): Notification
- **Low urgency** (informational): Message, inline text

### Step 2: Determine Context
- **User stays on page**: Modal, Message, Alert, Form validation
- **User redirected**: Result page with illustration
- **Background process**: Notification, Notification center

### Step 3: Match Component

---

## DO
- Use `message` for brief, auto-dismissing feedback (3-5 seconds)
- Use `notification` for important messages that need user acknowledgment
- Use `Modal.confirm()` before destructive operations
- Use `Alert` for persistent, in-page warnings
- Use inline **Form validation** for field-level errors (show next to field)
- Provide **actionable guidance** in error messages ("Unable to save. Check your network connection and try again.")
- Use illustrations on Result pages for end-of-process feedback
- Match feedback tone to severity: neutral for info, supportive for errors

## DON'T
- Don't use `Modal` for trivial confirmations (e.g., "Item saved" -> use `message`)
- Don't stack multiple `message` or `notification` simultaneously
- Don't use `notification` for expected, routine outcomes
- Don't say "Error" or "Failure" without explaining what happened and what to do
- Don't use `Alert` for transient states (it's for persistent warnings)
- Don't block the entire screen for non-critical feedback
- Don't use exclamation marks in error messages (creates anxiety)

---

## Copywriting in Feedback

### DO
- Write from the user's perspective ("You can..." not "The system will...")
- Use concise, direct language
- Provide the specific reason + next action
- Use "Unable to complete" instead of "Failed"
- Use Arabic numbers instead of written-out numbers
- Be friendly and supportive in error states

### DON'T
- Don't mix "my" and "your" in the same sentence
- Don't use jargon or technical codes as the primary message
- Don't use absolute words ("never", "always") in error states
- Don't use exclamation marks unless congratulating/welcoming
- Don't add unnecessary periods to labels, titles, or tooltips
- Don't blame the user ("You entered wrong data" -> "Please check the format")

---

## Empty States

### New User (First Use)
- **Show:** Feature explanation + help guide + suggested first action
- **Include:** Process overview if part of complex workflow
- **Goal:** Help users understand value and get started fast

### Task Completed / Cleared
- **Show:** Simple illustration + confirmation message
- **Don't include:** Action buttons (user voluntarily cleared data)
- **Goal:** Acknowledge completion positively

### No Data Available
- **Show:** Illustration + clear reason + suggested action
- **Always include:** At least one actionable next step
- **Goal:** Guide user out of empty state

---

## Deletion Patterns

### Low Risk (Undo Available)
Delete directly, show undo option via `message` with action button.

### Medium Risk (Standard Confirmation)
Use `Popconfirm` or `Modal.confirm()` with clear consequence description.

### High Risk (Security Check)
Require typed confirmation or authentication before executing.

### DO
- Always confirm destructive operations
- Use Danger Button for delete actions
- Set "Cancel" as primary when system discourages deletion
- Describe consequences clearly ("This will permanently delete 12 records")

### DON'T
- Don't delete without any confirmation mechanism
- Don't use vague confirmations ("Are you sure?" without context)
- Don't make the destructive option the default/primary choice
