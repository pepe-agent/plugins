# Setting up the Canva skill

You do this once. About 15 minutes. Canva's screens change from time to time, so treat these steps as a map, not as exact clicks.

## What you need

- A Canva account on **Pro, Teams or Enterprise**. Filling brand templates through the API is not available on the free plan, and Canva may add usage limits.
- A **brand template** with fields the API can fill (next section).
- A place to run Pepe where `bash`, `curl` and `jq` exist.

## 1. Create the integration

1. Open https://www.canva.com/developers/ and sign in with the Canva account that owns the templates.
2. Create an integration (private, for your own use). Give it a name such as "Pepe".
3. Under **Scopes**, enable exactly these:
   - `design:content:read`
   - `design:content:write`
   - `brandtemplate:meta:read`
   - `brandtemplate:content:read`
   - `asset:read`
   - `asset:write`
4. Under **Authentication**, add a **redirect URL**. Any address you control works, because you only copy the code out of the address bar. For example `http://127.0.0.1:3000/callback` (the page will fail to load, and that is fine).
5. Copy the **client id** and generate the **client secret**. Canva shows the secret once.

## 2. Prepare the template

Open the template in Canva, select an element (a text box or a picture), and in the options choose to connect it to data (Canva calls these data fields). Give each one a short name without spaces, for example `title`, `subtitle`, `background`. Then publish the design as a **brand template**. The API only fills elements marked this way. `canva.sh fields TEMPLATE_ID` shows the names it sees.

## 3. Give Pepe the client id and secret

Put them in the environment of the Pepe server, as variables:

```
CANVA_CLIENT_ID=...
CANVA_CLIENT_SECRET=...
CANVA_REDIRECT_URI=http://127.0.0.1:3000/callback
```

The redirect address must be exactly the one you registered. In Pepe's settings, add the variable **names** (never the values) to `secrets.expose_env`, so the agent's `bash` tool can see them. Keep the values out of chats and notes.

Tokens are kept in `~/.pepe-canva/` (mode 600). Set `CANVA_STATE_DIR` to move it. Back it up like any other secret; nobody else should read it.

## 4. Authorize once

1. Ask the agent to sign in to Canva, or run `scripts/canva.sh auth-url` yourself.
2. Open the link, choose the Canva account and allow access.
3. The browser goes to your redirect address and shows an error page. Copy the full address from the address bar (it contains `code=...`).
4. Give it to the agent, or run `scripts/canva.sh auth-code "THE-ADDRESS"`.
5. `scripts/canva.sh status` should now say "authorized".

Canva's refresh tokens are single use. The script saves the new one after every refresh, so keep using the same state folder. If it is lost, repeat this section.

## Approvals

Pepe's `bash` tool asks for approval on each call unless the operator pre-approves this script. If you trust it, allow the exact command `bash skills/canva-template-image/scripts/canva.sh` (adjust the path to where the skill is installed) so the agent does not ask for every step.

## Testing

```
scripts/canva.sh templates
scripts/canva.sh fields TEMPLATE_ID
scripts/canva.sh make TEMPLATE_ID --text title="Test" --out test.png
```

Each design made this way stays in your Canva account; delete the tests there.
