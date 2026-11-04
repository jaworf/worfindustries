# Database migrations

Production is the existing linked Supabase project. The migration filenames were reconciled on November 4, 2026 with `supabase_migrations.schema_migrations`: all 28 filename versions and names match production. Only filenames changed during that reconciliation; no migration was rerun and no database history was rewritten.

For future changes:

1. Create a new migration with `supabase migration new <name>`. Never modify already-applied SQL. A requested source-comment correction does not require rerunning the migration.
2. Test the complete migration set and permission checks locally.
3. With authenticated CLI access, inspect `supabase migration list --linked`, then `supabase db push --linked --dry-run`. Review the plan before applying the repo migrations using `supabase db push --linked`; this preserves filename versions.
4. Verify production history, permissions and application behavior after deployment. Publish the same SQL and versions in the pull request.

If deployment uses the Supabase connector's `apply_migration` instead, it assigns the production version. Immediately read the resulting version from production and rename the corresponding new repository file before publishing. Do not run db push while those versions differ. Do not repair history by marking unapplied SQL as applied.

The November 4 reconciliation used read-only queries through the connected Supabase service to compare every filename/version/name against production. CLI list/dry-run was unavailable because this shell had no Supabase access token; no credentials or database passwords were copied into the repository.
