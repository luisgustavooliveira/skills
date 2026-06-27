# Implementation Checklist

Use this checklist before editing and before declaring the integration complete.

## Client And Configuration

- Define `Menshen:BaseUrl`.
- Define service-to-service authentication for Menshen calls.
- Add bounded timeouts and safe resilience policies.
- Propagate `X-Correlation-Id`.
- Treat invalid responses, timeouts, and unavailable Menshen as deny.
- Avoid retries that can exceed product request latency budgets.

## DTO And Contract Alignment

- Align request and response DTOs with `docs/api/menshen.openapi.json` when available.
- Use JSON `camelCase`.
- Do not invent undocumented decision codes when the contract is available.
- Preserve `allowed`, `decision`, `reasons`, `deniedBy`, `effectivePermissions`, and capability fields.

## Backend Enforcement

- Resolve user by Keycloak `sub`.
- Check product access before product entry.
- Load tenant list from Menshen.
- Validate every tenant-scoped request server-side.
- Check sensitive actions against Menshen effective permissions or `action/check`.
- Apply local business invariants only after Menshen governance allows the context.
- Reject missing or malformed `X-Tenant-Id` for tenant-scoped operations.
- Reject unknown or expired tenant selections.

## Frontend Integration

- Show only tenants returned by Menshen.
- Persist tenant selection only as UX preference, not authorization truth.
- Send `X-Tenant-Id` and `X-Correlation-Id` with API requests.
- Clear or reselect tenant when backend validation denies it.
- Show safe access-denied and governance-unavailable states.

## Audit

- Audit tenant selection and tenant switch.
- Audit support or platform-admin traversal when used.
- Include reason when policy requires one.
- Include channel, IP/user-agent when available, product id, tenant id, platform user id, and correlation id.

## Tests

- User without product access is denied.
- User with product access can list tenants.
- Invalid tenant id is denied server-side.
- Explicit deny overrides role and grant.
- Support access works only when honored and not denied.
- Platform-admin works only under declared policy.
- Menshen outage fails closed.
- UI does not expose stale tenant as valid after backend denial.

## Done Criteria

- Code builds.
- Relevant unit and integration tests pass.
- Frontend checks pass when frontend was changed.
- Role mapping and product policy are documented.
- Rollout notes explain config, migration, and fallback behavior.
