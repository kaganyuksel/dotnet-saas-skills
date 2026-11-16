---
name: dotnet-multitenant-db-agnostic
description: "Rules and patterns for building .NET 10 (ASP.NET Core + EF Core) microservices with an Angular frontend that are multi-tenant and database-agnostic (Oracle, PostgreSQL, SQL Server via config flip). Use when adding entities, repositories, migrations, endpoints, background jobs, service-to-service calls or Angular data services in a multi-tenant SaaS; when reviewing code for tenant isolation / IDOR leaks; or when code needs database-specific SQL, types or exceptions."
---

# Multi-tenant, database-agnostic .NET 10 + Angular

Two invariants govern every change:

1. **Tenant isolation is enforced on the server, from a signed claim — never from client input.**
2. **Database-specific code lives in one provider layer; everything else is provider-neutral.**

Read the reference that matches the work:

| Work | Read |
|---|---|
| Entities, repositories, queries, migrations, raw SQL, DB exceptions | [references/db-independence.md](references/db-independence.md) |
| Endpoints, tenant resolution, ownership, jobs, service-to-service calls | [references/multi-tenancy.md](references/multi-tenancy.md) |
| Angular services, interceptors, error handling | [references/angular-frontend.md](references/angular-frontend.md) |
| Review / pre-merge checklist | [Checklist](#checklist) below |

## Core rules (always apply)

### Tenancy
- Tenant id comes from the **JWT `tenant_id` claim**. An `X-Tenant-Id` header may exist, but if it differs from the claim → `403 TENANT_MISMATCH`. Authenticated token without the claim → `403 TENANT_CLAIM_MISSING` (fail closed; never fall back to a default tenant).
- **Anonymous** requests never trust a tenant header; derive the tenant from the host (subdomain) behind correctly configured `UseForwardedHeaders` + `KnownProxies`.
- **Request/Write models carry no `TenantId`.** The controller passes the resolved tenant explicitly: controller → service → repository.
- Every tenant-owned table has `TENANT_ID NOT NULL`, and **every** repository query — including by-id / by-key lookups and updates — filters on it. A record of another tenant returns **404**, not 403 (don't confirm existence).
- Ownership checks (a user may only touch *their* records) live **in the service** (e.g. `OwnershipGuard.RequireOwnerOrRole(resource.PersonId, actor)`), not in attributes, so non-HTTP paths are covered too.
- Tenant comparisons use `StringComparison.Ordinal`.

### Database independence
- Select the provider by config (`Database:Provider` enum + provider-named connection strings). Switching DB = config flip + rebuild, no code edits.
- **No provider types outside the provider layer**: no `OracleException`, `NpgsqlException`, `OracleParameter`, `UseOracle/UseNpgsql`, `SYSDATE`, `DUAL`, `NVARCHAR2/CLOB` column types in Application/Domain/Api/repositories.
- Need something DB-specific (current timestamp SQL, unique-violation detection, large text/binary mapping, multi-row insert support, transaction-abort semantics)? **Add a capability to the central provider contracts and implement it for every supported provider in the same change.**
- One migrations assembly **per provider** (`<Svc>.Migrations.PostgreSql`, …); never hand-edit an applied migration — add a new one.
- Guard it in CI with a static gate ([scripts/db-provider-gate.sh](scripts/db-provider-gate.sh)) and run integration tests on **every** provider (Testcontainers).

## Checklist
- [ ] New table: `TENANT_ID NOT NULL`; unique indexes include `TENANT_ID`.
- [ ] Repository: every query/update filters by tenant; by-id methods take `tenantId`.
- [ ] Write model has no `TenantId`; a foreign tenant id in a body is ignored; a cross-tenant id in a route → 404.
- [ ] Ownership-sensitive endpoint: service-level owner-or-role check + a test with a second user.
- [ ] Background job: runs per tenant, isolates failures, sets an explicit audit actor (`job:<name>`).
- [ ] Service-to-service endpoint: service tokens deny-by-default; explicit allow-list marker.
- [ ] No provider-specific symbols outside the provider layer (gate passes).
- [ ] Migrations generated for every provider; integration tests green on every provider.
- [ ] Frontend never sends `tenantId` in bodies or query strings.
- [ ] Two-tenant integration test: tenant B cannot read, update, delete or list tenant A's data.
