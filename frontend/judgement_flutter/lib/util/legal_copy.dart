/// In-app Terms of Use and Privacy Policy copy.
library;

import '../util/legal_consent.dart';

String termsOfUseBody() => '''
Last updated: $kLegalAgreementVersion
Agreement version: $kLegalAgreementVersion

1. Service
Judgement is a free guest multiplayer card game provided for social play. You use a nickname and a temporary session — there is no full account registration required to play.

2. Eligibility
By using Judgement you confirm that you are at least 16 years old, or the age of digital consent in your country if that age is higher.

3. Acceptable use
You agree not to harass other players, share illegal or harmful content, impersonate others, scrape or attack the service, or attempt to cheat or disrupt games.

4. Table media
Emotes, soundboard clips, and short voice notes are shared with players currently at your table for that game. Do not share passwords, payment details, or other sensitive information. Microphone access requires a separate device permission and is only used when you choose to send a voice note.

5. No warranty / limitation of liability
The service is provided “as is” for social and hobby use. To the fullest extent permitted by law, $kLegalOperatorName is not liable for indirect or consequential losses arising from use of the game, including lost progress or temporary outages.

6. Changes
We may update these Terms. When the agreement version changes, you will need to accept the updated Terms before creating or joining a room again.

7. Contact
Questions about these Terms: $kLegalOperatorEmail
''';

String privacyPolicyBody() => '''
Last updated: $kLegalAgreementVersion
Agreement version: $kLegalAgreementVersion

1. Who we are
$kLegalOperatorName operates Judgement (web and mobile apps). Contact: $kLegalOperatorEmail

2. Data we process
• Nickname and guest session token needed to play and reconnect
• Game and room state (bids, plays, scores, presence)
• Optional scheduled-event RSVP: display name, mobile number, and whether you opted in to be contacted about that game
• Technical logs and metrics for reliability, capacity, and security
• Short voice audio only while you send a voice note (ephemeral fan-out to the table — not kept as a durable chat archive)

3. Why we process it
To run multiplayer games, support reconnect, enforce capacity and abuse limits, power scheduled events, and — only if you opt in — allow the host to contact you about that specific game.

4. Sharing
Other players at your table can see your nickname, avatar, emotes, and hear soundboard/voice notes you send. We do not sell your personal data.

5. Retention
Live game state is retained according to server policies (lobbies and finished games are cleaned up on a short schedule). RSVP mobile numbers are kept only as needed for the event and related host contact, then removed. Clearing app data (or site data in a browser) removes local consent and client-side preferences.

6. Your choices
You may decline optional event contact consent, deny microphone permission on your device, leave a table at any time, and clear local app or browser data in your device settings.

7. Children
Judgement is not directed at children under 16.

8. Contact
Privacy questions: $kLegalOperatorEmail
''';
