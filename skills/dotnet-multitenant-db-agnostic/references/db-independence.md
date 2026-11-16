# Database independence (EF Core 10, Oracle / PostgreSQL / SQL Server)

## Architecture

```
SharedKernel/Data/Providers/
  ProviderContracts.cs     # capability interfaces (below)
  DbProviderSelector.cs    # picks the implementation from Database:Provider
  OracleProvider.cs
  PostgreSqlProvider.cs
  (SqlServerProvider.cs)
<Svc>.Infrastructure/Migrations/            # default-provider migrations
<Svc>.Migrations.PostgreSql/Migrations/     # one assembly per additional provider
```

Config (same schema in every service):

```json
"Database": { "Provider": 1 },
"ConnectionStrings": { "Oracle": "...", "PostgreSql": "...", "SqlServer": "..." }
```
`Provider` is an enum (1=Oracle, 2=PostgreSql, 3=SqlServer).

## Capability contracts

Model each DB difference as a capability on a small interface, resolved through one selector:

```csharp
public interface IDbProviderSelector
{
    IDbContextConfigurer ContextConfigurer { get; }   // UseOracle/UseNpgsql + options
    IDbDialect Dialect { get; }                       // SQL fragments & behaviour flags
    IDbExceptionMapper ExceptionMapper { get; }       // provider exception -> meaning
    IDbModelCustomizer ModelCustomizer { get; }       // conventions, large text/binary, naming
    IDbHealthCheckRegistrar HealthCheckRegistrar { get; }
    IHangfireStorageFactory HangfireStorageFactory { get; } // if you use Hangfire
}

public interface IDbDialect
{
    string CurrentTimestampSql { get; }
    string ParameterPrefix { get; }
    bool FailedStatementAbortsTransaction => false; // PostgreSQL: true -> use savepoints
    bool SupportsMultiRowInsert => true;            // Oracle + identity: false
}

public interface IDbExceptionMapper
{
    bool IsUniqueViolation(Exception ex, string? constraintName = null);
    string? GetErrorCode(Exception ex) => null;
    bool IsSchemaError(Exception ex) => false;
}

public interface IDbModelCustomizer
{
    void ConfigureConventions(ModelConfigurationBuilder b); // e.g. DateOnly converters
    void ConfigureModel(ModelBuilder b);                    // identifier quoting, filters
    void ConfigureLargeText(PropertyBuilder p);             // CLOB / text / nvarchar(max)
    void ConfigureLargeBinary(PropertyBuilder p);           // BLOB / bytea / varbinary(max)
}
```

Application code asks for a meaning, never a provider:

```csharp
catch (DbUpdateException ex) when (_db.ExceptionMapper.IsUniqueViolation(ex, "UX_PERSON_NO"))
{
    throw new ConflictException("PERSON_NO_TAKEN");
}
```

## Rules

1. **Adding a capability = implementing it for all providers in the same PR.** If one provider cannot support it, surface that as a blocker; don't ship a one-provider feature.
2. Prefer LINQ over raw SQL. Raw SQL only through dialect fragments or inside a provider class.
3. Avoid recursive CTEs / vendor functions in services; if unavoidable, put the query behind a provider capability.
4. Migrations: generate per provider (`dotnet ef migrations add X --project <Svc>.Migrations.PostgreSql --startup-project <Svc>.Migrations.PostgreSql`). Never edit an applied migration. Check constraints EF can't model go in migration SQL with an idempotent pre-check.
5. Config keys must not look like bind parameters to the gate regex (avoid `:SomethingName` / `:SomethingId` shapes in strings).

## Cross-provider traps (found in practice)

| Trap | Fix in the provider layer |
|---|---|
| Npgsql rejects non-UTC `DateTime` for `timestamptz` | One policy (UTC everywhere, or the legacy-timestamp switch) set in `PostgreSqlProvider` |
| Unquoted identifiers in index filters / check constraints fold to lowercase in PostgreSQL | Model customizer quotes identifiers |
| `bool` column compared with `= 1` | Dialect emits `= TRUE` on PostgreSQL |
| Timestamp precision differs (PostgreSQL 6 digits) → optimistic-concurrency equality fails | Truncate audit/concurrency stamps to microseconds before saving |
| Oracle treats `''` as `NULL` | Normalize empty strings at the boundary; don't rely on `''` |
| Oracle multi-row INSERT into identity tables can corrupt NVARCHAR2 | `SupportsMultiRowInsert=false` → row-by-row inserts |
| PostgreSQL aborts the transaction after any failed statement | `FailedStatementAbortsTransaction=true` → wrap best-effort writes in savepoints |
| Oracle IN-list limit (1000) | Recent EF providers split automatically; verify for your provider version |

## Static gate (CI)

Fail the build when provider-specific symbols appear outside the provider layer or migrations: [../scripts/db-provider-gate.sh](../scripts/db-provider-gate.sh). Adapt paths and patterns.

## Tests

- Integration tests with WebApplicationFactory + **Testcontainers** for each provider, selected by an env var (e.g. `IT_PROVIDER=Oracle|PostgreSql`). Run the full suite on every provider in CI.
- One characterization test per capability (unique violation detected, timestamps round-trip bit-exact, large text works).
