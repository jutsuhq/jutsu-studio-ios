# App Store listing

The listing in fastlane `deliver` layout. Nothing here uploads by itself; check it with

```bash
scripts/check-store-metadata.py
```

When the listing is final and an App Store Connect API key is set up, `fastlane deliver --skip_binary_upload
--skip_screenshots` uploads the text; it shows an HTML preview and asks before sending.

- `metadata/en-US/`: name, subtitle, promotional text, description, keywords, release notes and the three URLs. The
  listing is English only.
- `metadata/copyright.txt`, `primary_category.txt`, `secondary_category.txt`.
- `metadata/review_information/notes.txt`: App Review notes.
- `app_privacy_details.json`: the App Privacy answers, in the format of fastlane's `upload_app_privacy_details_to_app_store`.

## Naming

The name and subtitle don't use "Higgsfield" (Guidelines 4.1 and 5.2.1); the description names it only to say the app
is an unofficial client for it, with a disclaimer. Keywords leave out other companies' marks (2.3.7) and the words
already in the name and subtitle, which Apple indexes anyway. The checker enforces both.

## Categories

- **Primary: Photo & Video.** Everything the app makes is video or images from your clips, and Info.plist already
  declares `public.app-category.photography`.
- **Secondary: Graphics & Design.** Restyles, image models, reframing and delivery sets for editors fit creative tools
  better than Entertainment, where the app would compete with streaming apps.

## Age rating answers

Apple's questionnaire (2025 version), as the app is today:

| Question | Answer |
| --- | --- |
| Violence, sexual content, nudity, profanity, horror, drugs, alcohol, tobacco, mature themes | None |
| Medical or treatment information | None |
| Simulated or real gambling, contests | No |
| Unrestricted web access | No (the only web view is the Higgsfield sign-in sheet) |
| User-generated content shared with others, messaging, chat | No (results stay private to the account) |
| Age assurance, parental controls, advertising | No |

These answers give 4+. The models can make open-ended video from any prompt, filtered by Higgsfield's moderation,
not by Jutsu, so App Review may ask for more; picking a higher rating in App Store Connect (for example 13+) heads that
off. That choice is the owner's.

## App Privacy

Derived from `App/Resources/PrivacyInfo.xcprivacy` and the code: no tracking, no third-party SDKs, no Jutsu server.
Data the app sends off the device goes only to Higgsfield, on the person's own account, to generate:

| Data type | Purpose | Linked to the user | Tracking |
| --- | --- | --- | --- |
| Photos or Videos (clips, photos, reference images) | App Functionality | Yes, the Higgsfield account | No |
| Other User Content (prompts) | App Functionality | Yes, the Higgsfield account | No |

Not collected: contact info (the account email is read from Higgsfield and only shown), identifiers, usage data,
diagnostics (MetricKit reports stay on the device unless the person shares them), location, purchases.
