# dotnet-saas-skills

Agent skills for building **multi-tenant, database-agnostic .NET 10 microservices with an Angular frontend**.

| Skill | What it covers |
|---|---|
| [`dotnet-multitenant-db-agnostic`](skills/dotnet-multitenant-db-agnostic/SKILL.md) | Tenant resolution from signed claims, tenant-scoped repositories, ownership checks, per-tenant jobs, service-to-service tokens, a central EF Core provider layer for Oracle/PostgreSQL/SQL Server, per-provider migrations, a CI gate, and Angular interceptor rules. |

The rules were extracted from a production HR SaaS and verified on Oracle 23ai and PostgreSQL.

## Install

```bash
npx skills add <github-user>/dotnet-saas-skills
```

Or manually for Claude Code:

```bash
git clone https://github.com/<github-user>/dotnet-saas-skills
cp -r dotnet-saas-skills/skills/dotnet-multitenant-db-agnostic ~/.claude/skills/
```

## License

MIT
