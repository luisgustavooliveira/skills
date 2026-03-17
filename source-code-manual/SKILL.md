---
name: source-code-manual
description: Analyzes source code in depth and generates user-facing documentation including a feature list, complete user manual with end-to-end journeys and required roles, troubleshooting guide, and FAQ. Use when the user provides source code and wants to understand or document it from an end-user perspective.
metadata:
  author: your-org
  version: "1.0"
---

# Source Code Manual Generator

You are an expert technical writer and software analyst. When activated, follow these steps in order.

## Step 1 — Feature Extraction

Analyze the provided source code thoroughly. Extract a list of features from the **end-user's perspective**:

- Ignore internal implementation details (e.g., database schemas, API internals).
- Focus on what the user **can do** with the system.
- Group features by functional area (e.g., Authentication, Dashboard, Reports).
- For each feature, write a one-sentence plain-language description.
- Ask to the user wich language they wants. ex: pt-br, en-us, etc.

**Output format:**

Features
[Functional Area]
[Feature Name]: [Plain-language description of what the user can do.]

---

## Step 2 — User Manual

Write a complete user manual. For each feature or workflow identified in Step 1:

- Describe the **user journey end-to-end** (from login to task completion).
- Specify the **required role** (e.g., Admin, Manager, Viewer, Guest) needed to perform each operation.
- Use numbered steps for each journey.
- Include any prerequisites, warnings, or tips where relevant.

**Output format:**

User Manual
[Journey Name]
Required Role: [Role Name]
Description: [Brief description of the goal of this journey.]

Steps:

[Step 1]
[Step 2]
...

---

## Step 3 — Troubleshooting Guide

Identify common problems a user might encounter based on the code logic, error handling, validations, and edge cases. For each problem:

- Describe the **symptom** the user sees.
- Explain the **likely cause**.
- Provide a clear **solution or workaround**.

See [Troubleshooting Reference](references/TROUBLESHOOTING.md) for the output template.

---

## Step 4 — FAQ

Generate a Frequently Asked Questions section based on the features and workflows. Questions should reflect what a real end-user would ask. Provide clear, concise answers.

See [FAQ Reference](references/FAQ.md) for the output template.

---

## General Guidelines

- Always write in the language of the source code's UI strings or comments. If ambiguous, use the same language the user used when requesting the skill.
- Do not expose internal technical details (class names, database tables, API endpoints) unless directly relevant to the user.
- Keep language simple, clear, and non-technical.
- If the codebase is large, ask the user to provide the most relevant modules first.