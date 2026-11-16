# Angular frontend (Angular 21, standalone, signals)

## Tenant context

- The tenant is **in the token**; the frontend does not choose it. Never put `tenantId` in request bodies or query strings.
- If the API expects an `X-Tenant-Id` header, add it in one interceptor from the authenticated session (it must equal the token's claim; the server rejects mismatches).
- Login sends a `clientId`; the server validates client ↔ tenant and embeds `azp`. Treat `azp` as a consistency label, never a permission grant.
- Separate apps (tenant app vs. platform-admin app) use separate storage prefixes so sessions don't collide.

## Interceptor chain (order matters)

```ts
provideHttpClient(withInterceptors([
  authInterceptor,      // bearer token + single-flight refresh
  tenantIdInterceptor,  // X-Tenant-Id from the session (if your API uses it)
  pagingInterceptor,    // paging/filter header
  errorInterceptor,     // RFC 9457 ProblemDetails -> user message
]))
```

## Errors

- Server errors are RFC 9457 ProblemDetails with top-level `errorCode` / `errorMessage`; read `err.error?.errorCode`.
- Map codes to localized messages in one constants file (`TENANT_MISMATCH`, `TENANT_CLAIM_MISSING`, `RATE_LIMIT_EXCEEDED`, …) with fallback text.
- A 404 on a cross-tenant id is expected — show "not found", don't retry.

## UI permission hints

- Hide write buttons with a role directive (`*appHasRole="writeRoles"`, fail closed). This is UX only; the server is the authority.

## Dates and "today"

- Business "today" comes from the tenant's business time zone, not UTC `new Date()`; centralize it (`businessToday()`).

## Paging

- Server-side paging; the server clamps page size (e.g. max 100). Pickers that need "all" must page or search instead of requesting `pageSize: 500`.
