<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# my-finance-app

Early-stage Next.js 16.4.3 App Router app (React 19, Tailwind v4, TypeScript) for a single-user AI finance/receipt tracker. Read `PRD.md`, `PROJECT_PLAN.md`, and `docs/database-design.md` before changing data model or user flows; they are in Thai and are the actual product spec.

## Commands

- `npm run dev` / `npm run build` / `npm start`
- `npm run lint` — ESLint with no args.
- `npx tsc --noEmit` — typecheck (verified passing).
- No test runner, test script, formatter, or CI is configured. Do not invent a single-test command.
- `.env*` is gitignored and no env example exists yet.

## Stack quirks

- `next.config.ts` enables `cacheComponents` and `partialPrefetching` and wires Tailwind v4 via the Turbopack rule `@tailwindcss/turbopack`. Do not add a Tailwind v3 `postcss.config` or `tailwind.config`.
- This Next version generates typed route props (e.g. `LayoutProps<"/">` in `app/layout.tsx`). Use generated types; check `node_modules/next/dist/docs/` before relying on remembered APIs.
- Runtime deps are only `next`, `react`, `react-dom`. Supabase, shadcn/ui, React Hook Form, Zod, and the Gemini SDK are planned in docs but **not installed** — add them before importing.
- Path alias `@/*` maps to the repo root.

## Data / backend

- Authoritative migration: `migrations/20261023000100_initial_schema.sql`. `supabase/` is empty even though `docs/database-design.md` references `supabase/migrations/`; do not create a duplicate migration there without asking.
- Schema conventions: amounts are positive `numeric(14,2)` values plus `type` (`income`/`expense`); all user rows are isolated by RLS on `auth.uid()`; signup trigger seeds a profile and Thai starter categories with `THB` / `Asia/Bangkok`.
- Receipt flow contract: upload to private `receipts` bucket → insert `receipts` → create one `receipt_scans` row per attempt → user reviews/confirms → insert linked `transactions`. AI must never create transactions directly.
- Storage path is `{user_id}/{receipt_id}/{filename}`. The bucket and storage policies exist only as commented SQL at the end of the migration and still need manual setup.

## Conventions

- App code lives directly under `app/`; there is no `src/` directory.
- User-facing copy and docs are Thai; keep new UI text Thai unless told otherwise.
- `README.md` is untouched create-next-app boilerplate — trust the PRD, plan, and schema instead.
