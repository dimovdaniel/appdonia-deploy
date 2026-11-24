---
name: appdonia-deploy
description: Helper for "Appdonia - platform deployment". Creates the basic docker/appdonia.yaml deployment file for a project and checks that docker-entrypoint.sh lets the app set itself up from environment variables, fixing or creating it only where needed. Use when asked to make a project deployable on Appdonia, to create or review appdonia.yaml, or when the user runs /appdonia-deploy. Supported stacks - laravel.
argument-hint: laravel "custom instructions"
---

# Appdonia - platform deployment

Arguments: `$ARGUMENTS`

The first word is the stack. Everything after it is the user's custom
instructions, which win over the defaults in this skill wherever they conflict
(but never over the hard rules below; if they conflict with a hard rule, say so
and ask).

| Stack     | Guide               | Templates            |
|-----------|---------------------|----------------------|
| `laravel` | `stacks/laravel.md` | `templates/laravel/` |

If the stack is missing, detect it from the project (`artisan` + `composer.json`
requiring `laravel/framework` means `laravel`) and say which one you picked. If
the stack is not in the table, stop and tell the user it is not supported yet.
Do not improvise a deployment for an unsupported stack.

## What Appdonia expects

Appdonia deploys a project from one file, `docker/appdonia.yaml`. It is a
Docker Compose file with a metadata header. Appdonia pulls the
images, generates secrets and the public URL, attaches the domain and TLS, and
starts the services. Nobody runs a command or clicks through an installer, so
the application must reach a working, logged-in-able state from environment
variables alone.

## Scope

This skill is a helper for any project of a supported stack. It knows nothing
about a particular product: every name, port, path, driver and command comes
from inspecting the project in front of you, never from the templates.

- **Always:** create `docker/appdonia.yaml` (create the `docker` folder if it
  is missing). This is the deliverable.
- **Always:** check the project's container entrypoint and image against the
  "Application behaviour" rules below, because the yaml only works if the app
  behaves that way.
- **Always:** make sure the image can be built. If the project has no
  `Dockerfile`, create one from the template. If it has no `.gitlab-ci.yml`
  job that builds the image and pushes it to the GitLab registry, add one from
  the template.
- **Only where a rule is not met:** make the smallest change that meets it:
  adapt the existing `docker-entrypoint.sh`, or create one from the template
  if there is none; add the small helper commands from the stack guide.

Leave everything else alone. Do not restructure the project, rename things,
change its web server, or "improve" a Docker setup that already satisfies the
rules. If the project already complies, the only file you write is
`docker/appdonia.yaml`.

## Hard rules

These apply to every stack. A template that breaks one of them will not deploy
correctly.

**appdonia.yaml**

- Prebuilt images only. Every service has `image:`; never `build:`.
- The app image is written as a literal URL, never through a variable:
  `image: registry.gitlab.com/<gitlab-path>/<project>:latest`
  (see "Image name" below).
- No `ports:`, `container_name:`, `networks:`, or host bind mounts. Appdonia
  routes traffic and names containers itself. Use named volumes only.
- No hardcoded secrets, passwords, keys or domains. Use the platform-generated
  variables below.
- Every service has a `healthcheck`. Services wait for their dependencies with
  `depends_on: { <service>: { condition: service_healthy } }`.
- Everything that must survive a redeploy lives in a named volume: the
  database, uploaded files, and any settings the app writes to disk.
- Start with the metadata header (see the template). `port` is the port the
  app listens on inside the container.

**Application behaviour**

- No install wizard and no manual step. On start, the app container waits for
  the database, migrates, seeds once, and creates the first admin user.
- The first admin comes from `ADMIN_EMAIL` and `ADMIN_PASSWORD`. Creation is
  idempotent: it never modifies an existing admin and is skipped if either
  variable is empty.
- One app container runs the web server, the queue worker and the scheduler.
  Do not add separate worker or scheduler services unless the custom
  instructions ask for them.
- Start-up is safe to repeat. Every restart and redeploy runs the same
  entrypoint; nothing in it may destroy or duplicate data.
- If the app has its own settings screen (mail, integrations, ...), those
  values are not set in `appdonia.yaml`. An environment variable would
  override what the administrator saved.

## Image name

The app image lives in the **author's own GitLab**, in the container registry
of the project that holds the code (or of a separate project, if the author
does not want to share the source):

```
registry.gitlab.com/<gitlab-path>/<project>:latest
```

- **`<gitlab-path>`** is the author's GitLab group or username, with any
  subgroups (`acme` or `acme/apps`). It is the path that is connected to their
  Appdonia author account; Appdonia only accepts a private image below it.
  Find it in this order, and say which source you used:
  1. the custom instructions;
  2. the Appdonia MCP server, if it is connected: `get-account` returns it as
     `gitlab.path`, and the ready prefix as `gitlab.image_prefix`;
  3. the project's git remote, if it points to GitLab
     (`gitlab.com/<gitlab-path>/<project>`);
  4. otherwise **ask the user**: "What is your GitLab group or username (the
     one connected to your Appdonia account)?"

  Never guess it from the project, the vendor name in `composer.json`, or this
  skill.
- **`<project>`** comes from the project: the repository name from the git
  remote, otherwise the project folder name. Do not ask for it unless neither
  gives a usable name.
- Both are written GitLab style: lower case; letters, digits and hyphens only;
  spaces and underscores become hyphens; no leading or trailing hyphen
  ("My Business" becomes `my-business`). If the user gives a name that needs
  changing, show them the slug you will use.

The image is built from the project's `Dockerfile` by GitLab CI in that
project, `gitlab.com/<gitlab-path>/<project>`, which is what makes the registry
path above exist.

### Access for Appdonia

Appdonia pulls the image with a short-lived, read-only token it creates for
each install. For that, the author invites the Appdonia deploy account,
**`@mobidonia-deploy`**, to the GitLab project that holds the image, with the
**Maintainer** role (GitLab: **Manage > Members > Invite members**). Tell the
user to do this; you cannot do it for them. If `get-account` says the GitLab
is not connected yet, the author also tells Appdonia their GitLab group or
username once, so it is linked to their author account.

A stack that uses only public images needs none of this.

## Platform-generated variables

Appdonia fills these in when it sees them in `appdonia.yaml`. `<NAME>` is the
service name in upper case; `<ID>` is any identifier you choose. The same
identifier yields the same value in every service that uses it.

| Variable                          | Value                                                      |
|-----------------------------------|------------------------------------------------------------|
| `SERVICE_URL_<NAME>_<PORT>`       | Declares that the service is public on that container port |
| `SERVICE_URL_<NAME>`              | The public URL of that service, with scheme                |
| `SERVICE_USER_<ID>`               | Random username                                            |
| `SERVICE_PASSWORD_<ID>`           | Random password                                            |
| `SERVICE_REALBASE64_32_<ID>`      | 32 random bytes, base64 encoded (encryption keys)          |

Variables written as `${NAME:-default}` appear in the Appdonia UI as editable
fields with that default. `${NAME}` appears as an empty field the deployer must
fill in. Use these for anything the deployer should choose (admin email, admin
password, app name).

Keep service names to a single lower-case word (`app`, `mariadb`) so the
generated variable names stay unambiguous.

## Workflow

1. **Get the GitLab path** as described under "Image name", unless it is
   already known. Then **read the stack guide** from the table above and the
   templates it names.
2. **Inspect the project** as the guide describes. Read what exists before
   writing: an existing `Dockerfile`, entrypoint, compose files, and any
   installer. Never overwrite an existing file without reading it; adapt it.
3. **Write `docker/appdonia.yaml`**, starting from the template, and make any
   changes the Scope section calls for. The templates are a known-good
   baseline, not a form to fill in: remove what the project does not need and
   resolve every `ADAPT:` comment. No `ADAPT:` marker may remain in the
   output.
4. **Validate** with the checks in the stack guide. Fix what fails.
5. **Report** to the user:
   - the files created and changed, and for each change outside
     `docker/appdonia.yaml`, which rule required it;
   - the variables the deployer must set before the first deploy;
   - the image URL `docker/appdonia.yaml` points to, and that the project
     must be pushed to `gitlab.com/<gitlab-path>/<project>` so CI builds
     that image before the first deploy;
   - that `@mobidonia-deploy` must be a Maintainer of that GitLab project
     (see "Access for Appdonia");
   - how to put it on Appdonia (see "Submitting to Appdonia");
   - anything you assumed or could not verify (for example, that you did not
     build the image or boot the containers).

Do not commit, push, build or publish images unless the user asks.

## Submitting to Appdonia

The file becomes the **Docker Settings** of the author's item on Appdonia.

- **With the Appdonia MCP server connected** (tools `get-account`,
  `create-item`, `update-item`, `submit-item`): offer to do it. Look for the
  item with `list-items` first. Send the content of `docker/appdonia.yaml` as
  `docker_compose` and the app image with its tag as `private_image`, together
  with the title, descriptions and category. Ask the user for the prices; never
  make them up. The item is saved as a draft. Call `submit-item` only when the
  user asks for the review.
- **Without it**: tell the user to open their item on Appdonia
  (**Portfolio > Edit > Docker Settings**), paste the file into **Docker
  Compose (YAML)** and put the image URL with its tag into **Private Image**.
  The MCP server is set up under **Portfolio > Submit with AI**.

Either way, the user should run **Test install** on the item before sending it
for review. For a new version: push a `vX.Y.Z` git tag, use that tag in the
yaml and in the private image, and add a changelog entry on Appdonia.
