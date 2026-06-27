# Product Discovery Guide

Use this guide to find where Menshen must be introduced in a product.

## Repository Survey

Identify:

- backend entrypoints, middleware, filters, policies, and route groups
- frontend auth bootstrap, route guards, API client, and tenant selector
- existing user, tenant, company, organization, account, or customer models
- existing role and permission stores
- feature flag, subscription, product access, and entitlement checks
- audit or activity log pipeline
- service-to-service HTTP client patterns
- resilience, retry, timeout, logging, and correlation conventions

## Search Terms

Search code and config for:

- `Authorize`, `RequireRole`, `RequireClaim`, `policy`, `Permission`, `Role`
- `tenant`, `TenantId`, `X-Tenant-Id`, `organization`, `company`, `customer`
- `scope`, `scp`, `aud`, `sub`, `claims`, `Keycloak`, `OIDC`, `JWT`
- `Forbidden`, `Unauthorized`, `AccessDenied`, `HasAccess`, `Can`
- `admin`, `support`, `platform`, `impersonation`
- `feature`, `entitlement`, `subscription`, `license`
- `audit`, `activity`, `correlation`, `trace`

## Integration Point Categories

Classify each finding:

- identity resolution: where token identity becomes an application user
- product entry: where the user is allowed into the product
- tenant listing: where selectable tenants are loaded
- tenant validation: where requests become scoped to a tenant
- action authorization: where specific operations are allowed or denied
- UI propagation: where tenant id is stored and attached to requests
- audit: where tenant selection, tenant switch, and support access are recorded
- background work: where jobs use a user or tenant context

## Risk Signals

Treat these as high-risk and verify with tests:

- frontend tenant selection without backend validation
- tenant or organization claims trusted directly from JWT
- local admin role bypassing all tenant checks
- support or impersonation bypass without audit reason
- wildcard roles such as `admin`, `superuser`, `all`, or `*`
- authorization fallback to last selected tenant
- catch blocks that allow access when a dependency fails
- cached final decisions used as truth

## Output Template

Use this concise table for discovery results:

| Area | Current implementation | Menshen target | Collision | Required change |
| --- | --- | --- | --- | --- |
| Identity |  | Keycloak `sub` -> `users/resolve` |  |  |
| Product access |  | `product/check` |  |  |
| Tenant list |  | `product/tenants` |  |  |
| Tenant validation |  | `tenant/validate` |  |  |
| Action auth |  | `action/check` or effective permissions |  |  |
| Audit |  | `audit/tenant-context` |  |  |
