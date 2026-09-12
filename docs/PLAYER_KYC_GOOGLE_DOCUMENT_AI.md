# PlayPro Player KYC — Google Document AI Integration

## Production flow

`PLAYER PROFILE → KYC → private document upload → Supabase Edge Function → Google Document AI → provider result → PlayPro KYC review → VERIFIED → Football Passport`

### Implemented

- Private Supabase Storage bucket: `kyc-documents`.
- Player-owned upload path: `<auth.uid>/<random-file>.<ext>`.
- MyKad accepts front + back; MyKid/Passport accepts one primary document.
- KYC request is stored in `identity_verifications`.
- `kyc-verify-player` is an authenticated Supabase Edge Function (v2).
- `kyc-review-player` is an authenticated privileged review Edge Function.
- Google Document AI is called server-side; Google credentials are never placed in browser code.
- Provider result stores verification metadata and masked identifier fields; raw OCR text is not persisted by the function.
- The provider pre-check extracts a legal-name candidate, document type, birth date and MyKad state code when available.
- Name/DOB matching is a pre-check only. A `match` result does not itself grant PlayPro verification.
- `approve_player_kyc()` is the single official verification gate; approval updates the player's legal name, locks the legal identity fields, updates the profile legal name, sets `verification_status='verified'`, and generates Football Passport ID.
- `preferred_name` remains editable after KYC. The display-name mode can continue to choose the legal name or preferred/alias name for public presentation.
- A verified player cannot be attached to a club through the normal player row unless KYC is already verified.
- Legacy KYC approval path `approve_player_kyc(UUID,TEXT)` has been removed so there is no second approval route that can bypass the document-backed flow.
- Player KYC submission UI: `public/player_kyc.html`.
- Privileged KYC review UI: `public/kyc_review.html`.

## Google Cloud configuration

The Google OAuth client ID is **not** a Document AI service credential. It identifies an OAuth client and should not be used as a secret for KYC processing.

The Edge Function expects these Supabase Edge Function secrets/environment values:

- `GOOGLE_SERVICE_ACCOUNT_JSON` — service-account JSON containing `client_email` and `private_key`.
- `GOOGLE_DOCUMENT_AI_PROJECT_ID` — Google Cloud project ID that owns the processor.
- `GOOGLE_DOCUMENT_AI_LOCATION` — processor location; default is `asia-southeast1`.
- `GOOGLE_DOCUMENT_AI_PROCESSOR_ID` — the Document AI processor ID.

The service account must have permission to process the selected Document AI processor. Do not commit the JSON key to GitHub or place it in `public/`.

## Important verification boundary

Google Document AI processes the submitted document and returns OCR/entities according to the configured processor. PlayPro keeps the final `VERIFIED` decision behind the privileged PlayPro approval gate. This prevents provider output from becoming an uncontrolled identity decision.

For Malaysian MyKad/MyKid, the current implementation uses the configured Document AI processor as the processing provider. The exact processor chosen in Google Cloud remains an external configuration value rather than being hard-coded into PlayPro.
