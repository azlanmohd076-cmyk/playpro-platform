# PlayPro Player KYC — Google Document AI Integration

## Production flow

`PLAYER PROFILE → KYC → private document upload → Supabase Edge Function → Google Document AI → provider result → PlayPro KYC review → VERIFIED → Football Passport`

### Implemented

- Private Supabase Storage bucket: `kyc-documents`.
- Player-owned upload path: `<auth.uid>/<random-file>.<ext>`.
- MyKad accepts front + back; MyKid/Passport accepts one primary document.
- KYC request is stored in `identity_verifications`.
- `kyc-verify-player` is an authenticated Supabase Edge Function.
- Google Document AI is called server-side; Google credentials are never placed in browser code.
- Provider result stores only verification metadata and masked identifier fields; raw OCR text is not persisted by the function.
- Name matching is a pre-check only. A `match` result does not itself grant PlayPro verification.
- Existing PlayPro `approve_player_kyc()` remains the official verification gate and generates Football Passport ID.

## Google Cloud configuration

The Google OAuth client ID is **not** a Document AI service credential. It identifies an OAuth client and should not be used as a secret for KYC processing.

The Edge Function expects these Supabase Edge Function secrets/environment values:

- `GOOGLE_SERVICE_ACCOUNT_JSON` — service-account JSON containing `client_email` and `private_key`.
- `GOOGLE_DOCUMENT_AI_PROJECT_ID` — Google Cloud project ID that owns the processor.
- `GOOGLE_DOCUMENT_AI_LOCATION` — processor location; default is `asia-southeast1`.
- `GOOGLE_DOCUMENT_AI_PROCESSOR_ID` — the Document AI processor ID.

The service account must have permission to process the selected Document AI processor. Do not commit the JSON key to GitHub or place it in `public/`.

## Important verification boundary

Google Document AI can process documents and provide extraction/quality/fraud signals depending on the selected processor. The PlayPro implementation intentionally keeps the final `VERIFIED` decision behind the existing PlayPro approval gate. This prevents OCR/model output from becoming an uncontrolled identity decision.

For Malaysian MyKad/MyKid, the current implementation uses the configured Document AI processor as the processing provider. The exact processor chosen in Google Cloud remains an external configuration value rather than being hard-coded into PlayPro.
