# appdonia-deploy

An AI agent skill that makes a project deployable on **Appdonia**.

It inspects your project, writes `docker/appdonia.yaml` (the one file Appdonia
deploys from), and checks that the container can set itself up from environment
variables alone: migrate, seed once, create the first admin. Where the project
does not already do that, it adds the smallest fix: an entrypoint, a
`Dockerfile`, a GitLab CI image build, and two small console commands.

Supported stacks: **Laravel**.

## Install

### Claude Code

For all your projects:

```bash
git clone https://github.com/dimovdaniel/appdonia-deploy.git ~/.claude/skills/appdonia-deploy
```

For one project only (run in the project root):

```bash
git clone https://github.com/dimovdaniel/appdonia-deploy.git .claude/skills/appdonia-deploy
```

Start a new Claude Code session afterwards. Update later with:

```bash
git -C ~/.claude/skills/appdonia-deploy pull
```

### Any agent (Claude Code, Codex, Cursor, and others)

The [`skills`](https://github.com/vercel-labs/skills) CLI detects the agents
you have installed and puts the skill in the right place for each:

```bash
npx skills add dimovdaniel/appdonia-deploy -g
```

Leave out `-g` to install it into the current project only.

### Claude desktop and claude.ai

Download this repository as a ZIP (**Code > Download ZIP**), then upload it
under **Settings > Capabilities > Skills**.

### Other agents, by hand

A skill is just this folder. Clone it into the directory your agent reads
skills from, keeping the folder name `appdonia-deploy`. For Codex that is
`~/.codex/skills/`.

## Use

In the project you want to deploy:

```
/appdonia-deploy laravel
```

Add your own instructions after the stack; they win over the skill's defaults:

```
/appdonia-deploy laravel "use PostgreSQL, business name is acme"
```

Or just ask: "make this project deployable on Appdonia". The skill asks for
your business name (your subgroup in the `appdonia` GitLab group) if it cannot
find it, then reports the files it wrote and the variables to set before the
first deploy. It does not commit, push, or build anything unless you ask.

## What is inside

| Path                 | Purpose                                              |
|----------------------|------------------------------------------------------|
| `SKILL.md`           | The rules every stack follows and the workflow       |
| `stacks/laravel.md`  | The Laravel guide: what to inspect, adapt, validate  |
| `templates/laravel/` | Known-good baseline files the skill adapts           |

## License

[MIT](LICENSE)
