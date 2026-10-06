# Pepe plugins

Plugins for [Pepe](https://github.com/pepe-agent/pepe), the agent runtime. Each folder is one plugin you can install on its own, published on [PepeHub](https://hub.pepe-agent.com):

```bash
pepe plugin install @jhonathas/jira
```

| Plugin | What it connects | Status |
|---|---|---|
| [`jira`](jira/) | Jira Cloud: search, read, create, comment, move issues | ready to try |

More are planned: GitHub, Notion, Google Drive, Zapier, Stripe (read only), Instagram publishing and Meta Ads reporting.

Every plugin has a README with a step by step setup, the fields to fill in, how to test it and what to be careful with. The same text is what shows on the plugin's page on the hub.

## How a plugin is laid out

```
jira/
  manifest.json   name, version, the tools it provides, and the settings the dashboard asks for
  jira.exs        the code (Pepe compiles it when it is installed)
  README.md       what it does and how to set it up (README.pt-BR.md in Portuguese)
```

The settings in `manifest.json` become the **Configure** form in the Pepe dashboard. A value written as `${ENV_VAR}` is kept as that reference and read from the environment only when used, so secrets never sit in a settings file.

## Working on a plugin

```bash
mix deps.get
mix test
```

The tests run each plugin against a fake of the service it talks to, so they need no account and no network. The Pepe runtime is **not** a dependency (it is large); the few modules a plugin leans on are stood in for under `test/support/`. Keep that file in step with Pepe's own contract.

What a plugin must hold to:

- **Read and write are separate tools**, so an agent can be given one without the other.
- **Writing can be limited** to what the operator allows, and is refused before any request is made.
- **Text that came from the service** (a ticket, a page) is returned framed with `Pepe.Security.ExternalContent.mark_untrusted/2`, and a tool that returns such text says so with `outside_content?/0` (a Pepe from the release after 0.20 on; older ones ignore it).
- **No secret in the code.** Settings come from the plugin's configuration, falling back to environment variables.
- **A clear message for every failure** (bad credentials, not found, refused field), written for the model to read.

## License

MIT
