# **TFC Vault Namespaces — Automated Workshop Orchestration**

*Provision user namespaces in HCP Vault using Terraform.  
Generate per-attendee credentials.  
Issue wrapped story tokens.  
Package everything for your workshop in one go.*

© Personal project by **Raymon Epping**.  
*Not affiliated with official HashiCorp documentation. For workshops and education purposes.*

---

## 🚀 What This Project Does

This repository automates an entire Vault workshop flow:

1. Convert a ticket/export **CSV → JSON + extended JSON**
2. Convert JSON → **Terraform tfvars** (attendees + namespace suffixes)
3. Run a **preflight check** (tools, Vault reachability, admin token)
4. Run **Terraform apply** → create namespaces, auth, and policies
5. **Generate per-attendee credentials** (`.env` + CSV/JSON)
6. **Issue wrapped story tokens** (one-time, per-attendee story)
7. **Nuke all workshop namespaces safely** after the event
8. **Package everything into a zip** you can hand to participants or co-instructors

Everything is driven from a single orchestrator:

```bash
./scripts/workshop.sh
```

⸻

📂 Folder Structure

```bash
tfc_vault_namespaces/
├── main.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── attendees.auto.tfvars.json              # <- optional, can also be generated into scripts/output/
├── scripts/
│   ├── input/
│   │   └── tickets.csv                     # <- attendee export
│   ├── output/                             # <- all generated workshop files (git-ignored)
│   │   ├── tickets.json
│   │   ├── tickets_extended.json
│   │   ├── attendees.auto.tfvars.json
│   │   ├── credentials.csv
│   │   ├── credentials.json
│   │   ├── wrapped_story_tokens.csv
│   │   ├── wrapped_story_tokens.json
│   │   └── *.env                           # <- per-attendee env files
│   ├── convert_2_json.sh
│   ├── convert_2_tfvars.sh
│   ├── generate_credentials.sh
│   ├── issue_wrapped_story.sh
│   ├── unwrap_story.sh
│   ├── login_vault.sh
│   ├── workshop.sh                         # <- the orchestrator
│   ├── workshop_preflight.sh
│   ├── workshop_nuke_namespaces.sh
│   ├── workshop_package.sh                 # <- builds workshop_package_*.zip
│   └── workshop_admin.sh                   # (optional helper)
└── .gitignore
```

All generated workshop artefacts live in scripts/output/ and are ignored by git
(including .env, credentials.*, wrapped tokens, and generated tfvars).

⸻

🔧 Prerequisites

You will need:
	•	Terraform (v1.6+ recommended)
	•	Vault CLI
	•	jq
	•	A running HCP Vault cluster (or Vault Enterprise with namespaces)
	•	A .env file in scripts/ containing:

```bash
TF_VAR_vault_address="https://your-hcp-vault-cluster:8200"
TF_VAR_vault_admin_token="hvs.XXXXXXXX"
NUKE_ALLOWED=false
```

Only the instructor should ever set:
```bash
NUKE_ALLOWED=true
```

Attendees never need admin tokens or nuke access.

⸻

🧪 Before You Start: Preflight

Always start with:
```bash
cd scripts
./workshop.sh preflight
```

This checks:
	•	.env presence and loading
	•	terraform, vault, and jq availability
	•	TF_VAR_vault_address and TF_VAR_vault_admin_token
	•	Vault liveness + cluster status
	•	Whether the admin token can list namespaces

You get a clear green/red signal before touching Terraform.

⸻

🧩 Step 1 — Prepare Attendees (CSV → JSON → tfvars)

Put your attendee CSV at:

```bash
scripts/input/tickets.csv
```

The project supports rich exports (e.g. from event tools). A typical header might look like:

first_name;last_name;email;order.metadata.city;order.metadata.company;...

At minimum you need:
	•	first_name
	•	last_name
	•	email
	•	(optionally) order.metadata.company or similar

Then run:

```bash
cd scripts
./workshop.sh prepare tickets.csv
```

This will:
	1.	Read input/tickets.csv
	2.	Generate:
	•	output/tickets.json
	•	output/tickets_extended.json
	•	output/attendees.auto.tfvars.json

The extended JSON and tfvars include a stable namespace_suffix, with duplicate handling:
	•	raymon-e
	•	raymon-b
	•	etc.

This prevents collisions when you have multiple attendees with the same first name.

⸻

☠️ Interlude — When CSV Changes Break Terraform State

If you change your CSV after an initial terraform apply (for example, 
adding duplicate handling so team_raymon becomes team_raymon-e and team_raymon-b), 
Terraform might still track the old objects in state.

Typical symptoms:
	•	Error: object already exists
	•	Or a plan that wants to destroy/recreate the “wrong” namespace

In that case you may need to:

```bash
terraform state list
terraform state rm module.attendees_vault["raymon-epping-at-ibm-com"]
terraform apply -auto-approve
```

Rule of thumb:

When attendee identifiers change, make sure Terraform state reflects that new reality.

The nuke command (see below) gives you an easy way to completely reset Vault-side namespaces without touching state. Use whichever path fits your workshop lifecycle.

⸻

🚀 Step 2 — Full Workshop Automation

Once your CSV is ready, run the full pipeline:

```bash
cd scripts
./workshop.sh full tickets.csv
```

This will:
	1.	CSV → JSON (extended)
	2.	JSON → attendees.auto.tfvars.json
	3.	Run preflight
	4.	Run terraform init -upgrade
	5.	Run terraform apply using output/attendees.auto.tfvars.json
	6.	Generate per-attendee credentials (generate_credentials.sh)
	7.	Issue wrapped story tokens (issue_wrapped_story.sh)

Flags:

```bash
./workshop.sh full tickets.csv --skip-tf      # skip preflight + terraform
./workshop.sh full tickets.csv --skip-creds  # skip credentials generation
./workshop.sh full tickets.csv --skip-wrap   # skip wrapped story tokens
```

End result in scripts/output/:
	•	attendees.auto.tfvars.json
	•	credentials.csv
	•	credentials.json
	•	wrapped_story_tokens.csv
	•	wrapped_story_tokens.json
	•	One *.env file per attendee

⸻

📦 Step 3 — Build a Shareable Workshop Package

Instead of manually zipping things, use the package helper:

```bash
cd scripts
./workshop.sh package
```

This:
	•	Collects all attendee .env files from output/
	•	Includes:
	•	output/credentials.csv
	•	output/wrapped_story_tokens.csv
	•	output/attendees.auto.tfvars.json
	•	input/tickets.csv
	•	Stages them into a temporary structure:
	•	env/ → per-attendee .env
	•	meta/ → credentials.csv, wrapped_story_tokens.csv
	•	tfvars/ → attendees.auto.tfvars.json
	•	input/ → tickets.csv
	•	Creates a timestamped zip in scripts/, e.g.:

workshop_package_20251116_133143.zip

You can hand this archive to:
	•	Co-instructors
	•	Yourself on another machine
	•	A workshop host who will distribute the .env files

⸻

🎁 Step 4 — Hand Out Credentials

After full or generate_credentials.sh has run, each participant gets:
	•	Their personal .env file (from scripts/output/)
	•	(Optionally) Their row in wrapped_story_tokens.csv or a copy of their token

Instructor flow for handing off:
	1.	Extract the zip (or copy from output/).
	2.	Give each attendee their <name>.env file and, optionally, their wrapped token.

⸻

🔑 Step 5 — Attendees Log Into Vault

From the scripts directory, an attendee can log in with:

```bash
./login_vault.sh raymon-e.env
```

This script:
	•	Loads the .env
	•	Sets VAULT_ADDR and VAULT_NAMESPACE
	•	Uses VAULT_USERNAME / VAULT_PASSWORD with userpass auth
	•	Stores the token in the Vault CLI token helper
	•	Prints only safe metadata

Short version of the flow:

```bash
📦 Loading environment from raymon-e.env
🔐 Logging into Vault...

VAULT_ADDR     = https://...
VAULT_NAMESPACE= admin/team_raymon-e
VAULT_USERNAME = raymon

Password (will be hidden):
...
✅ Logged into Vault successfully.
💡 Next time: source raymon-e.env && ./login_vault.sh
```

From that point on, vault CLI commands automatically use the stored token.

⸻

🎫 Step 6 — Unwrap the Story Token

Each attendee receives a wrapped story token. They can unwrap it with either:

Direct vault CLI + jq:

```bash
vault unwrap -format=json "$WRAPPED_TOKEN" | jq '.data'
```

Or using the helper script:

```bash
./unwrap_story.sh hvs.CAESI...
```

This will:
	•	Call vault unwrap
	•	Show the payload (e.g. name, email, and a personal message)
	•	Fail safely if the token is already used or expired

This makes the “secret story” part of the workshop repeatable and easy to demo.

⸻

💣 Step 7 — Safe Nuke (After the Workshop)

When the workshop is over, you can safely delete all team_* namespaces in Vault without touching Terraform state.

Dry run:

```bash
./workshop.sh nuke --dry-run
```

Actual deletion (including orphans under admin/):

```bash
./workshop.sh nuke --include-orphans
```

Guardrails:
	•	Requires NUKE_ALLOWED=true in scripts/.env
	•	Prints a clear plan of which namespaces will be deleted
	•	Asks you to type:

YES_NUKE_WORKSHOP

	•	Deletes via Vault API (sys/namespaces/...)
	•	Does not modify or delete Terraform state

Namespaces like:

```bash
admin/team_cojan
admin/team_jorg
admin/team_mahil
...
```

are removed, leaving Vault clean for the next run.

⸻

📊 Status Overview — Your Mini Dashboard

At any time, you can run:

```bash
./workshop.sh status
```

This shows:
	•	Input
	•	Whether input/tickets.csv exists
	•	Number of attendee rows
	•	Output
	•	Presence/absence of:
	•	tickets.json
	•	tickets_extended.json
	•	attendees.auto.tfvars.json
	•	credentials.*
	•	wrapped_story_tokens.*
	•	Counts (attendees, credentials, wrapped tokens)
	•	Vault
	•	Reachability check
	•	Namespace count
	•	Names (if small)
	•	Extra hint when no team_* namespaces exist:

ℹ️  🧹 No team_* namespaces found — Vault looks freshly nuked.



This is your quick health view during workshop prep and after cleanup.

⸻

🛡️ Safety & Guardrails

This repo is intentionally designed to avoid “oops” moments:
	•	nuke is instructor-only (NUKE_ALLOWED=true + confirmation phrase)
	•	No admin tokens are ever written to attendee outputs
	•	Per-attendee .env files are git-ignored
	•	All generated artefacts live under scripts/output/
	•	Terraform input is driven by generated attendees.auto.tfvars.json

You get:
	•	Safe iteration while developing the workshop
	•	Clean reset paths
	•	Minimal blast radius if something goes wrong

⸻

🧩 Extending This Repo

You can extend this foundation with:
	•	Extra attendee metadata (roles, tracks, time slots)
	•	Dynamic policy templates per group or role
	•	Boundary target + credential brokering per namespace
	•	OpenShift / OIDC onboarding flows
	•	Terraform Cloud workspace creation per team
	•	Additional story layers in the wrapped payload

The current structure is modular enough that you can plug new steps into the same orchestrator (workshop.sh) without breaking existing flows.

⸻

🤝 Credits
	•	Original inspiration: Cojan’s Terraform user/team creation prototype
	•	Extended, automated, and turned into a workshop engine by Raymon Epping

⸻

🧠 Final Notes

This repository is built for real workshops, not slideware:
	•	Short commands
	•	Clear feedback
	•	Safe teardown
	•	Easy packaging and sharing

Use it as-is, or treat it as a starting point for your own internal training pipeline.

If you fork it, break it, or improve it — that’s exactly what it’s here for.
