---
name: menshen-client
description: "Guides an agent through evaluating and implementing a product integration with Menshen, the central product and tenant access governance service. Use when the user asks to integrate a product with Menshen, implement Menshen client governance, migrate product roles/tenants/permissions to Menshen, map product authorization to Menshen, compare a product role model against the Menshen catalog, add tenant validation, add product access checks, or run commands such as '$menshen-client Implemente a integracao com o sistema de governanca Menshen'."
---

# Menshen Client Integration

## Purpose

Use this skill to turn an existing product into a Menshen consumer. The output must be a working integration plan or implementation that respects Menshen's governance model: Keycloak authenticates, Menshen governs access, PostgreSQL-backed governance is authoritative, deny always wins, and synchronous authorization must not depend on RabbitMQ.

## Required Source Context

Before making product changes, load the minimum Menshen references needed for the task:

- `references/domain-primer.md` for Menshen concepts and non-negotiable rules.
- `references/product-discovery.md` for locating integration points in a product.
- `references/role-mapping.md` for mapping product roles, scopes, claims, permissions, grants, denies, support, and platform-admin.
- `references/implementation-checklist.md` before editing code or declaring done.

If the current repository is the Menshen service repo, also read the canonical docs directly:

- `docs/architecture-baseline.md`
- `docs/menshen-service-contract.md`
- `docs/menshen-decision-matrix.md`
- `docs/menshen-permission-catalog.md`
- `docs/api/menshen.openapi.json`

If the current repository is a product repo, find the Menshen docs from one of these sources, in order: explicit user path, `MENSHEN_REPO`, sibling repo paths such as `../Menshen` or `D:/Code/Menshen`, then bundled references in this skill. Do not invent contract fields when the OpenAPI file is available.

## Workflow

### 1. Establish the Product Context

Identify:

- product name and stable `productId`
- backend framework and auth middleware
- frontend framework and tenant selection UX
- existing role, permission, scope, claim, and tenant concepts
- current persistence tables or services that store user-product or user-tenant access
- current authorization gates in middleware, filters, policies, guards, services, route handlers, UI nav guards, and background jobs

Prefer code evidence over README claims. Search for auth and tenant vocabulary such as `role`, `roles`, `permission`, `scope`, `claim`, `tenant`, `organization`, `company`, `customer`, `access`, `policy`, `authorize`, `forbidden`, `admin`, `support`, `impersonation`, and `X-Tenant-Id`.

### 2. Build the Collision Map

Create a short map of where the product model collides with Menshen:

- identity collision: token claims or local users that do not map cleanly to Keycloak `sub`
- product access collision: local product enablement, subscriptions, or feature flags used as authorization
- tenant collision: tenant selected client-side without server-side governance validation
- role collision: product roles that are broader, narrower, or named differently than Menshen baseline roles
- permission collision: scopes or flags that need canonical `<resource>.<action>` permissions
- transversal collision: support or platform-admin behavior that currently bypasses tenant rules
- deny collision: missing explicit deny path, or allow paths that can override deny
- failure collision: fallback behavior that could fail open when Menshen is unavailable

Use this map to decide whether to implement directly or first produce a migration spec.

### 3. Design the Integration Contract

Define the product-side contract before editing runtime code:

- `productId`
- Menshen base URL and auth method for service-to-service calls
- request correlation strategy using `X-Correlation-Id`
- tenant propagation strategy using `X-Tenant-Id`
- global capabilities extracted from Keycloak roles, usually `support` and `platform-admin`
- product policy for `honorsSupport`, `honorsPlatformAdmin`, allowed actions, and reason requirements
- role-to-permission mapping using Menshen baseline roles where possible
- local extension permissions only when no canonical permission matches

The product must not depend on tenant claims in the token. The backend must validate tenant context with Menshen and must fail closed on governance failures.

### 4. Implement in Thin Vertical Slices

Implement the integration in this order unless the product architecture requires a different dependency order:

1. Configuration and typed Menshen client.
2. DTOs generated or aligned from `docs/api/menshen.openapi.json`.
3. Identity resolution from Keycloak `sub` via `POST /api/v1/menshen/users/resolve`.
4. Product entry check via `POST /api/v1/menshen/access/product/check`.
5. Tenant list via `POST /api/v1/menshen/access/product/tenants`.
6. Server-side tenant validation for every tenant-scoped request via `POST /api/v1/menshen/access/tenant/validate`.
7. Action checks for sensitive operations via `POST /api/v1/menshen/access/action/check`.
8. Tenant selection and tenant switch audit via `POST /api/v1/menshen/audit/tenant-context`.
9. UI tenant selector and request propagation of `X-Tenant-Id`.
10. Removal or containment of obsolete local authorization paths.

Keep local business authorization separate from Menshen governance. Menshen answers "may this user access this product, tenant, and action context"; the product still owns business invariants inside that authorized context.

### 5. Verification Standard

Do not declare complete without proving:

- valid user can resolve identity, enter product, list tenants, select tenant, and perform an allowed action
- missing product access denies entry
- invalid or revoked tenant denies server-side even if the UI sends `X-Tenant-Id`
- explicit deny wins over role or grant
- support and platform-admin only work when product policy honors them
- Menshen timeout, unavailable response, invalid response, or unknown decision fails closed
- correlation id appears in logs/errors and is propagated to Menshen
- tests cover role mapping, tenant validation, action checks, and failure behavior

Use product-native verification commands. For .NET products prefer `dotnet build` and `dotnet test`; for frontend changes prefer `npm run lint`, `npm run build`, and targeted browser or component checks where available.

## Expected Deliverables

For analysis-only requests, produce:

- discovered integration points
- collision map
- role and permission mapping table
- implementation plan with test plan
- open questions that block safe implementation

For implementation requests, produce:

- code changes
- tests
- updated config/docs or runbook entries
- verification output summary
- residual risks and rollout notes

## Stop Conditions

Stop and ask for direction only when:

- there is no stable `productId` and no safe default exists
- multiple incompatible identity providers are active and Keycloak `sub` cannot be identified
- a product role grants destructive access that has no clear Menshen permission equivalent
- implementing would require changing Menshen's canonical contract rather than adapting the product
- the detected design would fail open and no safe migration path can be inferred
