# Role And Permission Mapping

## Mapping Principles

- Reuse Menshen canonical permissions when the product action has the same semantics.
- Add product-specific permissions only inside the product domain namespace.
- Keep roles as aggregators; final decisions are based on permissions after grants and denies.
- Prefer explicit permissions over broad `admin` or `manage` concepts.
- Never model `support` or `platform-admin` as unrestricted tenant access.

## Canonical Permission Naming

Use lowercase dot-separated permissions:

- `<resource>.<action>`
- `<resource>.<subresource>.<action>`

Common action suffixes:

- `.read`
- `.download`
- `.export`
- `.create`
- `.submit`
- `.update`
- `.delete`
- `.execute`
- `.config.read`
- `.config.write`

Avoid:

- `admin.full`
- `documents.manage`
- `all`
- `*`

## Baseline Tenant Roles

Use these when the product role semantics match:

| Menshen role | Intended semantics | Typical permissions |
| --- | --- | --- |
| `tenant-viewer` | read-only tenant access | `tenant.read`, `documents.read`, `documents.events.read`, `documents.timeline.read` |
| `tenant-operator` | normal operational user | viewer permissions plus `documents.download`, `documents.validate`, `documents.revalidate`, `ops.job.read`, `ops.job.submit` |
| `tenant-manager` | operational control | operator permissions plus `ops.job.cancel`, `ops.job.retry` |
| `tenant-admin` | tenant-level administration | manager permissions plus `product.config.read` |

Do not put `product.config.write` into `tenant-admin` by default unless product policy explicitly requires it.

## Transversal Capabilities

### support

Recommended mapping when the product honors support:

- `tenant.support.read`
- `tenant.support.diagnose`

Require an audit reason when the product policy requires one. Do not map support to destructive actions by default.

### platform-admin

Recommended mapping when the product honors platform-admin:

- `product.config.read`
- `product.config.write`
- `product.observability.read`
- `product.integrations.read`
- `product.integrations.write`

Platform-admin does not automatically imply functional access to every tenant.

## Mapping Table Template

| Product role/scope/claim | Current meaning | Menshen role | Menshen permissions | Deny behavior | Notes |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  | deny wins |  |

## Endpoint Permission Template

| Product endpoint/use case | Tenant-scoped? | Required Menshen permission | Requires action check? | Support allowed? | Platform-admin allowed? |
| --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |
