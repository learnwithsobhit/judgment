/// In-app Terms of Use and Privacy Policy copy (Dehla / multi-game shell).
library;

import 'legal_consent.dart';

String termsOfUseBody() => '''
Last updated: $kLegalAgreementVersion
Agreement version: $kLegalAgreementVersion

1. Service
Dehla Pakad (and related table games in this app, including Judgement when offered from the same shell) are free guest multiplayer card games for social play. You use a nickname and a temporary session — there is no full account registration required to play.

2. Eligibility
By using the service you confirm that you are at least 16 years old, or the age of digital consent in your country if that age is higher.

3. Acceptable use
You agree not to harass other players, share illegal or harmful content, impersonate others, scrape or attack the service, or attempt to cheat or disrupt games.

4. Table media
Emotes, soundboard clips, and short voice notes (when available) are shared with players currently at your table for that game. Do not share passwords, payment details, or other sensitive information.

5. No real-money gaming
These games are social and skill-oriented. There is no cash entry, cash prizes, redeemable chips, or paid wagering.

6. No warranty / limitation of liability
The service is provided “as is” for social and hobby use. To the fullest extent permitted by law, $kLegalOperatorName is not liable for indirect or consequential losses arising from use of the game, including lost progress or temporary outages.

7. Changes
We may update these Terms. When the agreement version changes, you will need to accept the updated Terms before creating or joining a room again.

8. Contact
Questions about these Terms: $kLegalOperatorEmail
''';

String privacyPolicyBody() => '''
Last updated: $kLegalAgreementVersion
Agreement version: $kLegalAgreementVersion

1. Who we are
$kLegalOperatorName operates this web app. Contact: $kLegalOperatorEmail

2. Data we process
• Nickname, optional avatar id, and guest session token needed to play and reconnect
• Game and room state (plays, scores, presence, partnership seats)
• Technical logs and metrics for reliability, capacity, and security
• Short voice audio only while you send a voice note when that feature is enabled (ephemeral fan-out to the table)

3. Why we process it
To run multiplayer games, support reconnect, enforce capacity and abuse limits, and keep tables fair.

4. Sharing
Other players at your table can see your nickname, avatar, and table media you send. We do not sell your personal data.

5. Retention
Live game state is retained according to server policies. Clearing your browser site data removes local consent and client-side preferences.

6. Your choices
You may deny microphone permission in your browser when voice is offered, leave a table at any time, and clear this site’s data in your browser settings.

7. Children
This service is not directed at children under 16.

8. Contact
Privacy questions: $kLegalOperatorEmail
''';
