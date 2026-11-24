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
/appdonia-deploy laravel "use PostgreSQL, GitLab path is acme"
```

Or just ask: "make this project deployable on Appdonia". The skill finds your
GitLab path (your GitLab group or username) from the Appdonia MCP server or the
git remote, and asks for it if it cannot. Then it reports the files it wrote
and the variables to set before the first deploy. It does not commit, push, or
build anything unless you ask.

## Your GitLab

The image stays in your own GitLab:
`registry.gitlab.com/<your-gitlab-path>/<project>`. Invite the Appdonia deploy
account, **`@mobidonia-deploy`**, to the project that holds the image, with the
**Maintainer** role, so Appdonia can create the short-lived tokens that pull
the image for each install.

## Submit the item with the Appdonia MCP server

With the Appdonia MCP server connected, your agent also creates the item,
fills in the Docker settings, description, prices and images, and sends it for
review when you ask. Create your token on Appdonia under
**Portfolio > Submit with AI** and run the command shown there, for example:

```bash
claude mcp add --transport http appdonia https://appdonia.com/mcp/authors --header "Authorization: Bearer YOUR_TOKEN"
```

The MCP server also carries this skill (tool `get-deploy-guide`), so an agent
that has only the MCP server can follow it without installing anything.
Guide: https://appdonia.com/help-center/authors/submit-item

## What is inside

| Path                 | Purpose                                              |
|----------------------|------------------------------------------------------|
| `SKILL.md`           | The rules every stack follows and the workflow       |
| `stacks/laravel.md`  | The Laravel guide: what to inspect, adapt, validate  |
| `templates/laravel/` | Known-good baseline files the skill adapts           |

## License

[MIT](LICENSE)
