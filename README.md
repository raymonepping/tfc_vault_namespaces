# **TFC Vault Namespaces — Automated Workshop Orchestration**

*Provision user namespaces in HCP Vault using Terraform.
Generate per-attendee credentials.
Issue wrapped story tokens.
Run the whole workshop with one command.*

© Personal project by **Raymon Epping**.
*Not affiliated with official HashiCorp documentation. For workshops and education.*

---

## 🚀 What This Project Does

This repository automates an entire Vault workshop flow:

1. **Convert a ticket/export CSV** → JSON + extended JSON
2. Convert JSON → **Terraform tfvars** (attendees + namespace suffixes)
3. **Preflight check** (tools, Vault reachability, admin token)
4. **Terraform apply** → Creates namespaces + workshop policies
5. **Generate per-attendee credentials**
6. **Issue wrapped story tokens** (one-time tokens for personalized messages)
7. **Nuke everything safely** after the workshop, using guardrails

Everything is driven from a single orchestrator:

```
./scripts/workshop.sh
```

---

## 📂 Folder Structure

```
tfc_vault_namespaces/
├── main.tf
├── providers.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── attendees.auto.tfvars.json        # <- generated
├── scripts/
│   ├── input/
│   │   └── tickets.csv
│   ├── output/                       # <- all generated workshop files
│   ├── convert_2_json.sh
│   ├── convert_2_tfvars.sh
│   ├── generate_credentials.sh
│   ├── issue_wrapped_story.sh
│   ├── unwrap_story.sh
│   ├── login_vault.sh
│   ├── workshop.sh                   # <- the orchestrator
│   ├── workshop_preflight.sh
│   ├── workshop_nuke_namespaces.sh
│   └── workshop_admin.sh             # (optional helper)
└── .gitignore
```

Everything generated lives inside `scripts/output/` and is **ignored by git**.

---

## 🔧 Prerequisites

You will need:

* **Terraform** (v1.6+)
* **Vault CLI**
* **jq**
* A valid HCP Vault cluster
* A `.env` file (in `scripts/`) containing:

```
TF_VAR_vault_address="https://your-hcp-vault-cluster:8200"
TF_VAR_vault_admin_token="hvs.XXXXXXXX"
NUKE_ALLOWED=false
```

> Only the instructor should ever set `NUKE_ALLOWED=true`.

---

## 🧪 Before You Start: Run Preflight

```
./scripts/workshop.sh preflight
```

This checks:

* Vault reachability
* Admin token permissions
* Required binaries
* Correct `.env` file

You get a quick green/red signal before touching Terraform.

---

## 🧩 Step 1 — Prepare Attendees

Put your attendee export at:

```
scripts/input/tickets.csv
```

Format:

```
first_name,last_name,email
Raymon,Epping,raymon.epping@ibm.com
...
```

Then:

```
./scripts/workshop.sh prepare tickets.csv
```

This produces:

```
scripts/output/tickets.json
scripts/output/tickets_extended.json
scripts/output/attendees.auto.tfvars.json
```

---

## 🚀 Step 2 — Full Workshop Automation

Run:

```
./scripts/workshop.sh full tickets.csv
```

This will:

1. Transform CSV → JSON
2. JSON → tfvars
3. Preflight
4. Terraform init/plan/apply
5. Generate per-attendee credentials
6. Generate wrapped story tokens

You end with:

* `/scripts/output/credentials.csv`
* `/scripts/output/credentials.json`
* `/scripts/output/wrapped_story_tokens.json`
* Per-user `*.env` files

---

## 🎁 Step 3 — Hand Out Credentials

Each participant receives:

* Their `.env` file
* (Optional) Their wrapped story token (CSV or JSON)

Your instructor workflow simplifies to:

```
source NAME.env
./scripts/login_vault.sh NAME.env
```

---

## 🧨 Step 4 — Safe Nuke (After the Workshop)

```
./scripts/workshop.sh nuke --dry-run
```

Or permanently:

```
./scripts/workshop.sh nuke --include-orphans
```

Safety features:

* Requires `NUKE_ALLOWED=true` in `.env`
* Requires typing `YES_NUKE_WORKSHOP`
* Never touches Terraform state
* Deletes only namespaces under `admin/team_*`

---

## 📊 Workshop Status Dashboard

At any time:

```
./scripts/workshop.sh status
```

Shows:

* Input CSV status
* Output file presence + counts
* Vault namespace list
* Post-nuke detection
* Health signals

It looks like this:

```
📊 Workshop status overview

📂 Input
  ✓ tickets.csv present (4 attendees)

📤 Output
  ✓ tfvars (5 attendees)
  ✓ credentials.json (5 items)
  ✓ wrapped story tokens (5 items)

🔐 Vault
  ✓ Reachable, 5 namespaces
```

---

## 🛡️ Safety & Guardrails

This repo is intentionally built with strict guardrails:

* `nuke` cannot run unless `NUKE_ALLOWED=true`
* Terraform only reads from generated tfvars
* No shared admin tokens in attendee output
* `.env` files per attendee are small and isolated
* All generated files are ignored by git

This ensures your workshop is:

* Safe
* Reproducible
* Resettable
* Instructor-only controls remain protected

---

## 🧩 Extending This Repo

You can add:

* Additional attendee metadata
* Group assignments
* Dynamic policy generation
* Boundary integration
* OpenShift / OIDC onboarding
* Terraform Cloud workspace creation

I can generate modules for any of these if you want.

---

## 🤝 Credits

Original inspiration from **Cojan’s Terraform user/team creation prototype**
Expanded, automated, and fully weaponized by **Raymon Epping**

---

## 🧠 Final Notes

This repo is designed for **real workshops**, not toy demos.
Everything is optimized for:

* Speed
* Safety
* Instructor sanity
* Workshop repeatability
