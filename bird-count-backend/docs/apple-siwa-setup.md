# One-time Apple Developer portal setup for Sign in with Apple

Prerequisite for Phase 1 (Cognito auth). Everything happens at
[developer.apple.com/account](https://developer.apple.com/account) →
**Certificates, Identifiers & Profiles**, signed in to team `352K435X8J`.

Cognito hosted UI domains (us-east-1):

| Env | Domain |
|---|---|
| dev | `birdcount-dev.auth.us-east-1.amazoncognito.com` |
| prod | `birdcount-prod.auth.us-east-1.amazoncognito.com` (added later) |

## 1. Enable Sign In with Apple on the App ID

**Identifiers** → select the existing App ID `org.antoninus.birdcount.app` →
check **Sign In with Apple** → Configure → "Enable as a primary App ID" → Save.

Note: editing capabilities invalidates existing provisioning profiles for this
App ID; Xcode automatic signing (or fastlane) regenerates them on next build.

## 2. Create a Services ID

This is the identifier Cognito presents to Apple (its `client_id` toward Apple).

**Identifiers** → click the blue **+** next to the "Identifiers" heading → on
the registration page choose the **Services IDs** radio button → Continue.
(Services IDs are not a sidebar section; the identifier list is filtered by the
dropdown at the top right, which defaults to "App IDs" — switch it to
"Services IDs" to see existing ones.)

- Description: `Bird Count Sign In`
- Identifier: `org.antoninus.birdcount.signin` (must differ from the App ID)

Register it, then click it and check **Sign In with Apple** → **Configure**:

- Primary App ID: `org.antoninus.birdcount.app`
- Domains and Subdomains: `birdcount-dev.auth.us-east-1.amazoncognito.com`
- Return URLs: `https://birdcount-dev.auth.us-east-1.amazoncognito.com/oauth2/idpresponse`

Save. When prod is set up, add the prod domain and return URL to this same
list — return URLs are editable anytime, no re-registration.

## 3. Create the Sign in with Apple key (.p8)

**Keys** → **+**:

- Name: `Bird Count SIWA`
- Check **Sign In with Apple** → Configure → Primary App ID `org.antoninus.birdcount.app`

Register → **download the .p8 file — this is the only chance**; Apple never
re-serves it. Note the **Key ID** (10 characters) shown on the download page.

## 4. Store everything in 1Password

Create an item (e.g. `BirdCount SIWA`) with fields:

| Field | Value |
|---|---|
| `APPLE_TEAM_ID` | `352K435X8J` |
| `APPLE_SERVICES_ID` | `org.antoninus.birdcount.signin` |
| `APPLE_KEY_ID` | Key ID from step 3 |
| `APPLE_PRIVATE_KEY` | full contents of the .p8 file, including BEGIN/END lines |

Then delete the .p8 from Downloads.

Phase 1 wires these into Terraform via the same pattern as `aws.env`: a
`siwa.env` with `op://` references, run through `op run`, so the key never
touches the repo or shell history.
