# Setup on a new machine

This guide sets up the Deal Desk demo on a fresh laptop, including a locked-down corporate one. It covers the [Salesforce](https://github.com/deepshikhalmp-dot/deal-desk-salesforce), [Agent Fabric network](https://github.com/deepshikhalmp-dot/deal-desk-network) and [mock agents](https://github.com/deepshikhalmp-dot/deal-desk-agents) repos.

All three runtime pieces already run in the cloud:

| Piece | Runs on |
|---|---|
| Deal Desk app and agent | The Salesforce org |
| Deal Desk broker | MuleSoft Omni Gateway |
| Pricing, Credit and Contract agents | Render |

Nothing has to run on your laptop to give the demo. Choose the path you need:

- **[A. Demo only](#a-demo-only-no-installs)** needs a browser and nothing else.
- **[B. Development](#b-development-setup)** is for changing code, deploying or testing.

---

## A. Demo only (no installs)

1. **Wake up the agents.** About two minutes before the demo, open `https://deal-desk-agents.onrender.com/health`. Wait until it shows `{"status":"UP"}`. The Render free tier sleeps when idle, and the first request can take up to a minute.
2. **Log in to Salesforce.** Go to `https://login.salesforce.com` and log in with a user that has the `DD_Deal_Desk_User` permission set. A new device may trigger an email verification code.
3. **Run the demo.** Open the **Deal Desk** app from the App Launcher, click the **Agentforce** button in the header, and follow the "Try it" steps in the [README](README.md#try-it).

---

## B. Development setup

### 1. Install the tools

On a managed laptop without admin rights, request these through the company software portal or IT.

| Tool | Why | Check |
|---|---|---|
| Git | Clone the repos | `git --version` |
| VS Code | Editor | – |
| Node.js 20 LTS | Run the mock agents; needed for the CLI install below | `node -v` |
| Salesforce CLI | Deploy, test and publish the agent | `sf --version` |

Once Node.js is installed, you can install the Salesforce CLI without admin rights:

```bash
npm install -g @salesforce/cli
```

VS Code extensions:

| Extension | Needed for |
|---|---|
| **Salesforce Extension Pack** | Apex and metadata |
| **Agentforce DX** | The `.agent` (Agent Script) file |
| **Anypoint Code Builder** | Changes to the MuleSoft network only |

> **Corporate proxy.** If `npm` or `sf` fail with network or certificate errors, ask IT for the proxy address and set it:
> ```bash
> npm config set proxy http://<proxy-host>:<port>
> npm config set https-proxy http://<proxy-host>:<port>
> ```
> If IT gives you a corporate root certificate, point Node at it with the `NODE_EXTRA_CA_CERTS` environment variable.

### 2. Clone the three repos

Keep the three repos side by side in one folder:

```bash
mkdir deal-desk && cd deal-desk
git clone https://github.com/deepshikhalmp-dot/deal-desk-salesforce.git
git clone https://github.com/deepshikhalmp-dot/deal-desk-network.git
git clone https://github.com/deepshikhalmp-dot/deal-desk-agents.git
```

The repos are public, so cloning needs no GitHub login.

### 3. Set your git identity per repo

A corporate laptop often has a work email in the global git config. Commits to these public repos would then show that address. Set the identity you want inside each repo:

```bash
cd deal-desk-salesforce
git config user.name  "<your name>"
git config user.email "<the email you want on public commits>"
```

Repeat this in `deal-desk-network` and `deal-desk-agents`.

### 4. Connect the Salesforce project to the org

```bash
cd deal-desk-salesforce
sf org login web --alias ProductPillarSDO1 --instance-url https://login.salesforce.com
sf config set target-org ProductPillarSDO1
sf org display
sf org open --path lightning/app/c__DD_Deal_Desk
```

- Log in as a **System Administrator**, because deploys need admin rights.
- Keep the alias `ProductPillarSDO1` so the commands in the README and the [tech design](docs/TECH_DESIGN.md) work unchanged.

Check that everything works:

```bash
sf apex run test --class-names DD_ReviewDealDiscountActionTest \
  --class-names DD_DealDeskBrokerServiceTest --code-coverage --wait 10
```

All 19 tests should pass.

**Deploy rules:**

- Deploy only the folders you changed, for example `sf project deploy start --source-dir force-app/main/default/classes`.
- Never deploy `bots/` or `genAiPlannerBundles/` by hand. `sf agent publish` creates them.
- To change the agent:
  1. Edit `aiAuthoringBundles/DD_Deal_Desk_Agent/DD_Deal_Desk_Agent.agent`.
  2. Run `sf agent validate authoring-bundle --api-name DD_Deal_Desk_Agent`.
  3. Deploy the bundle.
  4. Test it with `sf agent preview`.
  5. Run `sf agent publish authoring-bundle --api-name DD_Deal_Desk_Agent`.
  6. Run `sf agent activate --api-name DD_Deal_Desk_Agent`.
- Other projects may deploy to the same org. A full-org deploy from another project can overwrite Deal Desk metadata, so check before running one.

### 5. Run the mock agents locally (optional)

```bash
cd deal-desk-agents
npm install
npm start            # http://localhost:3000
```

A local server does not affect the live demo. However, **any push to `main` of `deal-desk-agents` redeploys the live Render service within seconds.** Work on a branch and merge only when you are ready.

### 6. Change the MuleSoft network (only when needed)

The deployed network keeps running without you, so day-to-day work does not need this step. To change the broker or the policy:

1. Open `deal-desk-network` in VS Code with Anypoint Code Builder.
2. Sign in to the Anypoint Platform organization that hosts the network.
3. Deploy. The deploy asks for `gemini.apiKey`.

The API key is **not in git**. Get it from Google AI Studio or your own secure note, and never commit it.

### 7. Pushing changes

Cloning needs no login, but pushing does. Before you sign in to a personal GitHub account on a corporate laptop, check your company's device policy. If personal accounts are not allowed, make the changes there and push from a personal machine.

---

## Not in git (bring these yourself)

| Item | Where to get it |
|---|---|
| Salesforce login | Run `sf org login web` on each machine |
| Gemini API key | Google AI Studio, or your own secure note |
| Anypoint Platform login | Your MuleSoft account |
| Demo test records | Already in the org: Opportunity "DD Live Test Opportunity - ACME-Q4", Deal ID `ACME-Q4` |
