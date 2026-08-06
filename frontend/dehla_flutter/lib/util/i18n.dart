/// Minimal Hindi/English strings for home/lobby/table chrome.
library;

enum DehlaLang { en, hi }

DehlaLang dehlaLang = DehlaLang.en;

String t(String key) {
  final table = dehlaLang == DehlaLang.hi ? _hi : _en;
  return table[key] ?? _en[key] ?? key;
}

const _en = {
  'app_tagline': 'Protect the tens. Control the pile. Win the Kot.',
  'create_room': 'Create room',
  'join_game': 'Join game',
  'ready': 'Ready',
  'not_ready': 'Not ready',
  'start_game': 'Start game',
  'your_turn': 'Your turn — pick a card',
  'waiting_turn': 'Waiting for {name}…',
  'seat_open': 'Seat open',
  'table_paused': 'Table paused',
  'next_hand': 'Next hand',
  'rematch': 'Rematch',
  'legal_required': 'Please agree to the Terms of Use and Privacy Policy',
  'invite_friends': 'Invite friends',
  'copy_join_link': 'Copy join link',
};

const _hi = {
  'app_tagline': 'टेन बचाओ। पाइल कंट्रोल करो। कोट जीतो।',
  'create_room': 'कमरा बनाएं',
  'join_game': 'गेम जॉइन करें',
  'ready': 'रेडी',
  'not_ready': 'रेडी नहीं',
  'start_game': 'गेम शुरू',
  'your_turn': 'आपकी बारी — कार्ड चुनें',
  'waiting_turn': '{name} की प्रतीक्षा…',
  'seat_open': 'सीट खाली',
  'table_paused': 'टेबल रुका',
  'next_hand': 'अगला हैंड',
  'rematch': 'रीमैच',
  'legal_required': 'कृपया नियम और गोपनीयता नीति स्वीकार करें',
  'invite_friends': 'दोस्तों को आमंत्रित करें',
  'copy_join_link': 'जॉइन लिंक कॉपी',
};
