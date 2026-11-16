# Multi-tenancy (shared database, shared schema, `TENANT_ID` column)

## Request pipeline

```
UseForwardedHeaders (KnownProxies!) -> UseAuthentication -> TenantMiddleware
-> UseRateLimiter (partition by tenant claim) -> UseAuthorization -> controllers
```

### Tenant resolution middleware

```csharp
if (ctx.User.Identity?.IsAuthenticated == true)
{
    var claim = ctx.User.FindFirstValue("tenant_id");
    if (string.IsNullOrEmpty(claim)) { await Problem(403, "TENANT_CLAIM_MISSING"); return; } // fail closed
    if (ctx.Request.Headers.TryGetValue("X-Tenant-Id", out var h)
        && !string.Equals(h.ToString(), claim, StringComparison.Ordinal))
    { await Problem(403, "TENANT_MISMATCH"); return; }
    ctx.Items["TenantId"] = claim;
}
else
{
    // Never trust a client header for anonymous callers; resolve from the (proxy-validated) host.
    ctx.Items["TenantId"] = hostTenantResolver.Resolve(ctx.Request.Host.Host) ?? DefaultTenantId;
}
```

A base controller exposes `TenantId` from `HttpContext.Items`; services receive it as an explicit parameter.

## Data layer

- Every tenant-owned table: `TENANT_ID` **NOT NULL**; unique indexes are `(TENANT_ID, <business key>)`.
- Repository methods take `tenantId` and filter on it — reads, updates, deletes, existence checks, **by-id lookups**. Another tenant's record is "not found" (404).
- Request/Write models have **no `TenantId`**. If a client still sends one it is ignored; tests assert tenant B's data is unaffected.
- Audit/history (`*_LOG`) tables may be exempt from NOT NULL by decision; document it.
- Optional defence in depth: an EF global query filter on `TenantId` — keep explicit repository filtering as the primary guarantee (filters are bypassed by `IgnoreQueryFilters` and raw SQL).

## Authorization layers (all three are needed)

1. **Tenant boundary** — above; blocks cross-tenant access.
2. **Permission** — role → permission bits; fail closed (no record = deny).
3. **Ownership** — inside the service: `RequireOwnerOrRole(resource.OwnerPersonId, actor)`. Self-service routes with `{personId}`: the route person must equal the caller's `person_id` claim unless privileged (403); an id owned by someone else → 404.

Lesson: trusting a role name is not enough for cross-tenant authority. Platform-admin power requires the role **and** `tenant_id == platform tenant` **and** the expected signed client (`azp`). Reserve privileged role codes so tenants can't create them.

## Background jobs

- Iterate tenants; run each in its **own DI scope** with an ambient tenant scope (AsyncLocal) and an explicit audit actor (`job:<name>`).
- One tenant's failure must not stop the others; abort the round only on a real infrastructure outage.
- Exclude inactive tenants with a separate small query (avoid huge `IN` lists).

```csharp
foreach (var tenantId in activeTenants)
{
    using var scope  = provider.CreateScope();
    using var tenant = ServiceTenantScope.Begin(tenantId);
    using var actor  = AuditActorScope.Begin("job:" + JobName);
    try { await RunForTenant(scope.ServiceProvider, tenantId, ct); }
    catch (Exception ex) when (!IsOutage(ex))
    { log.LogError(ex, "{Job} failed for {Tenant}", JobName, tenantId); }
}
```

## Service-to-service calls (microservices)

- Machine identity via a short-lived **per-tenant service token** (e.g. `POST /auth/service-token {serviceName, secret, tenantId}` → 5 min, no refresh). Claims: `sub=svc:<name>`, `role=SERVICE`, `azp=<service client>`, `tenant_id`.
- Service tokens are **deny-by-default**: only endpoints marked e.g. `[AllowServiceCaller("Workflow")]` accept them; a snapshot test pins the allow-list.
- Service-only endpoints check `ServicePrincipal.IsService` in the action (403 `SERVICE_ONLY`); a reflection test fails when a marked endpoint lacks the check.
- An outgoing `DelegatingHandler` forwards the user token where appropriate, otherwise mints a service token for the ambient tenant; cache per tenant, evict on 401.
- When you fake an HTTP client in tests, also pin that the target endpoint **exists** — fakes hide missing endpoints.

## Rate and resource limits

- Partition limiters by `tenant:{tenant_id}` (signed claim); anonymous by IP.
- Expensive endpoints (bulk import, exports) get a per-tenant **concurrency** limiter (e.g. 2, queue 0 → 429), independent of the global rate-limit switch. Consider a global cap as well so many tenants can't exhaust a shared service.

## Tests that must exist

- Two tenants, two users each. For every resource: B cannot GET / LIST / PUT / DELETE A's records (404); B's body `tenantId` is ignored; header/claim mismatch → 403; claim-less token → 403.
- Ownership: user 2 cannot read user 1's self-service records.
- Jobs: tenant A failing does not prevent tenant B's processing.
