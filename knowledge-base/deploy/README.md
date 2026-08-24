# Deploying this vault (Quartz + GitHub Pages)

The vault (`../content/`) is symlinked into a Quartz clone; Quartz is what deploys.

## One-time
1. Push your Quartz clone (with `content/` → this vault) to a GitHub repo.
2. Copy `quartz-deploy.yml` → the Quartz repo `.github/workflows/deploy.yml`.
3. In the repo: **Settings → Pages → Source = GitHub Actions**.
4. In `quartz.config.ts` set `baseUrl` to your Pages URL
   (e.g. `<user>.github.io/<repo>`).

## Thereafter
Every push rebuilds and republishes. Because the specs are symlinked, committing this
vault plus the specs keeps last-modified dates accurate.

## Note on symlinks
`content/reference/specs`, `content/decisions/adrs`, `content/reference/curriculum.md`, and `content/meta/doc-prompts.md` are symlinks into the parent
docs repo. Quartz follows them locally. In CI, either (a) build from a checkout that
includes those paths, or (b) replace the symlinks with a copy step in the workflow:
`cp -RL` before `npx quartz build`.
