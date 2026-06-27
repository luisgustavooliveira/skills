# Menshen Domain Primer

## Responsibility Split

Menshen is a central governance service for contextual access. It is not an identity provider.

- Keycloak authenticates users and emits identity/capability claims.
- Menshen resolves the global platform user and governs product, tenant, and action access.
- Products enforce business behavior after Menshen validates the access context.

## Canonical Identifiers

- `user_external_id`: normally Keycloak token `sub`.
- `platformUserId`: Menshen global user id returned by `users/resolve`.
- `productId`: stable product identifier such as `enma`.
- `tenantId`: stable tenant identifier inside the product.
- `correlationId`: request trace id propagated through product and Menshen.

## Integration Flow

1. Product validates the Keycloak token.
2. Product extracts `sub`, user display data, and global capabilities.
3. Product calls `POST /api/v1/menshen/users/resolve`.
4. Product calls `POST /api/v1/menshen/access/product/check`.
5. Product calls `POST /api/v1/menshen/access/product/tenants`.
6. User selects a tenant in the product UI.
7. Frontend sends `X-Tenant-Id` on tenant-scoped requests.
8. Backend validates `X-Tenant-Id` with `POST /api/v1/menshen/access/tenant/validate`.
9. Backend checks sensitive actions with `POST /api/v1/menshen/access/action/check`.
10. Product audits tenant selection and switches with `POST /api/v1/menshen/audit/tenant-context`.

## Non-Negotiable Rules

- Deny always wins.
- Products must never trust `X-Tenant-Id` without server-side Menshen validation.
- Products must not depend on tenant or organization claims in the token.
- Menshen governance failures must fail closed.
- RabbitMQ must never be required for synchronous authorization.
- Redis or local caches may accelerate reads only when they cannot become the authoritative final access decision.
- `support` and `platform-admin` are global capabilities, not universal permissions.
- A product must explicitly declare whether it honors `support` and `platform-admin`.

## Decision Precedence

Use this order when reasoning about authorization:

1. global deny
2. product local deny
3. tenant deny
4. explicit deny
5. honored transversal capability
6. explicit grant
7. base role

If an allow and a deny both apply, the result is deny.
