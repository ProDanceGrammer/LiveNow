import 'package:timezone/timezone.dart' as tz;

// Names and flags for IANA timezones ("Europe/Kyiv" -> "🇺🇦 Kyiv"), and the
// offset a zone has at a given instant. Pure; needs the timezone database
// initialised (initPostponeTimeZoneData) only for [zoneOffset].

/// The country of the common zones (ISO 3166 code). A zone missing here simply
/// gets no flag; its name and offset still work.
const Map<String, String> _zoneCountry = {
  'Europe/London': 'GB', 'Europe/Dublin': 'IE', 'Europe/Lisbon': 'PT',
  'Europe/Madrid': 'ES', 'Europe/Paris': 'FR', 'Europe/Brussels': 'BE',
  'Europe/Amsterdam': 'NL', 'Europe/Luxembourg': 'LU', 'Europe/Berlin': 'DE',
  'Europe/Zurich': 'CH', 'Europe/Vienna': 'AT', 'Europe/Rome': 'IT',
  'Europe/Malta': 'MT', 'Europe/Prague': 'CZ', 'Europe/Bratislava': 'SK',
  'Europe/Budapest': 'HU', 'Europe/Warsaw': 'PL', 'Europe/Copenhagen': 'DK',
  'Europe/Oslo': 'NO', 'Europe/Stockholm': 'SE', 'Europe/Helsinki': 'FI',
  'Europe/Tallinn': 'EE', 'Europe/Riga': 'LV', 'Europe/Vilnius': 'LT',
  'Europe/Kyiv': 'UA', 'Europe/Kiev': 'UA', 'Europe/Chisinau': 'MD',
  'Europe/Bucharest': 'RO', 'Europe/Sofia': 'BG', 'Europe/Athens': 'GR',
  'Europe/Belgrade': 'RS', 'Europe/Zagreb': 'HR', 'Europe/Ljubljana': 'SI',
  'Europe/Sarajevo': 'BA', 'Europe/Skopje': 'MK', 'Europe/Tirane': 'AL',
  'Europe/Podgorica': 'ME', 'Europe/Minsk': 'BY', 'Europe/Moscow': 'RU',
  'Europe/Istanbul': 'TR', 'Europe/Kaliningrad': 'RU', 'Europe/Samara': 'RU',
  'Europe/Monaco': 'MC', 'Europe/Andorra': 'AD', 'Europe/Vaduz': 'LI',
  'Atlantic/Reykjavik': 'IS', 'Atlantic/Azores': 'PT', 'Atlantic/Canary': 'ES',
  'Atlantic/Madeira': 'PT',
  'America/New_York': 'US', 'America/Chicago': 'US', 'America/Denver': 'US',
  'America/Los_Angeles': 'US', 'America/Phoenix': 'US', 'America/Anchorage': 'US',
  'America/Detroit': 'US', 'America/Boise': 'US', 'Pacific/Honolulu': 'US',
  'America/Toronto': 'CA', 'America/Vancouver': 'CA', 'America/Edmonton': 'CA',
  'America/Winnipeg': 'CA', 'America/Halifax': 'CA', 'America/St_Johns': 'CA',
  'America/Regina': 'CA', 'America/Mexico_City': 'MX', 'America/Monterrey': 'MX',
  'America/Cancun': 'MX', 'America/Tijuana': 'MX', 'America/Guatemala': 'GT',
  'America/Costa_Rica': 'CR', 'America/Panama': 'PA', 'America/Havana': 'CU',
  'America/Jamaica': 'JM', 'America/Santo_Domingo': 'DO',
  'America/Puerto_Rico': 'PR', 'America/Bogota': 'CO', 'America/Lima': 'PE',
  'America/Caracas': 'VE', 'America/La_Paz': 'BO', 'America/Santiago': 'CL',
  'America/Argentina/Buenos_Aires': 'AR', 'America/Buenos_Aires': 'AR',
  'America/Montevideo': 'UY', 'America/Asuncion': 'PY',
  'America/Sao_Paulo': 'BR', 'America/Manaus': 'BR', 'America/Bahia': 'BR',
  'America/Fortaleza': 'BR', 'America/Guayaquil': 'EC',
  'Africa/Cairo': 'EG', 'Africa/Johannesburg': 'ZA', 'Africa/Lagos': 'NG',
  'Africa/Nairobi': 'KE', 'Africa/Addis_Ababa': 'ET', 'Africa/Casablanca': 'MA',
  'Africa/Algiers': 'DZ', 'Africa/Tunis': 'TN', 'Africa/Tripoli': 'LY',
  'Africa/Accra': 'GH', 'Africa/Abidjan': 'CI', 'Africa/Dakar': 'SN',
  'Africa/Kampala': 'UG', 'Africa/Dar_es_Salaam': 'TZ', 'Africa/Khartoum': 'SD',
  'Africa/Maputo': 'MZ', 'Africa/Harare': 'ZW', 'Africa/Luanda': 'AO',
  'Asia/Jerusalem': 'IL', 'Asia/Beirut': 'LB', 'Asia/Amman': 'JO',
  'Asia/Damascus': 'SY', 'Asia/Baghdad': 'IQ', 'Asia/Riyadh': 'SA',
  'Asia/Kuwait': 'KW', 'Asia/Qatar': 'QA', 'Asia/Bahrain': 'BH',
  'Asia/Dubai': 'AE', 'Asia/Muscat': 'OM', 'Asia/Tehran': 'IR',
  'Asia/Baku': 'AZ', 'Asia/Tbilisi': 'GE', 'Asia/Yerevan': 'AM',
  'Asia/Kabul': 'AF', 'Asia/Karachi': 'PK', 'Asia/Tashkent': 'UZ',
  'Asia/Almaty': 'KZ', 'Asia/Bishkek': 'KG', 'Asia/Dushanbe': 'TJ',
  'Asia/Ashgabat': 'TM', 'Asia/Kolkata': 'IN', 'Asia/Calcutta': 'IN',
  'Asia/Colombo': 'LK', 'Asia/Kathmandu': 'NP', 'Asia/Dhaka': 'BD',
  'Asia/Thimphu': 'BT', 'Asia/Yangon': 'MM', 'Asia/Bangkok': 'TH',
  'Asia/Ho_Chi_Minh': 'VN', 'Asia/Phnom_Penh': 'KH', 'Asia/Vientiane': 'LA',
  'Asia/Jakarta': 'ID', 'Asia/Makassar': 'ID', 'Asia/Kuala_Lumpur': 'MY',
  'Asia/Singapore': 'SG', 'Asia/Manila': 'PH', 'Asia/Hong_Kong': 'HK',
  'Asia/Macau': 'MO', 'Asia/Shanghai': 'CN', 'Asia/Taipei': 'TW',
  'Asia/Seoul': 'KR', 'Asia/Tokyo': 'JP', 'Asia/Pyongyang': 'KP',
  'Asia/Ulaanbaatar': 'MN', 'Asia/Novosibirsk': 'RU', 'Asia/Yekaterinburg': 'RU',
  'Asia/Omsk': 'RU', 'Asia/Krasnoyarsk': 'RU', 'Asia/Irkutsk': 'RU',
  'Asia/Yakutsk': 'RU', 'Asia/Vladivostok': 'RU', 'Asia/Magadan': 'RU',
  'Asia/Kamchatka': 'RU', 'Asia/Nicosia': 'CY', 'Europe/Nicosia': 'CY',
  'Australia/Sydney': 'AU', 'Australia/Melbourne': 'AU',
  'Australia/Brisbane': 'AU', 'Australia/Perth': 'AU', 'Australia/Adelaide': 'AU',
  'Australia/Darwin': 'AU', 'Australia/Hobart': 'AU',
  'Pacific/Auckland': 'NZ', 'Pacific/Fiji': 'FJ', 'Pacific/Guam': 'GU',
  'Pacific/Port_Moresby': 'PG', 'Pacific/Tongatapu': 'TO',
  'Pacific/Apia': 'WS', 'Indian/Maldives': 'MV', 'Indian/Mauritius': 'MU',
};

/// The flag emoji of a two-letter country code ("UA" -> 🇺🇦).
String flagOfCountry(String iso) => String.fromCharCodes([
  for (final c in iso.toUpperCase().codeUnits) 0x1F1E6 + (c - 0x41),
]);

/// The flag of [zone]'s country, or '' when the zone is not in the table.
String zoneFlag(String zone) {
  final iso = _zoneCountry[zone];
  return iso == null ? '' : flagOfCountry(iso);
}

/// "America/New_York" -> "New York"; "America/Argentina/Buenos_Aires" ->
/// "Buenos Aires".
String zoneCity(String zone) =>
    zone.split('/').last.replaceAll('_', ' ');

/// The label a new calendar zone starts with: flag + city ("🇺🇸 New York").
String zoneDefaultLabel(String zone) {
  final flag = zoneFlag(zone);
  return flag.isEmpty ? zoneCity(zone) : '$flag ${zoneCity(zone)}';
}

/// [zone]'s offset from UTC at the instant [utc].
Duration zoneOffset(String zone, DateTime utc) =>
    tz.TZDateTime.from(utc, tz.getLocation(zone)).timeZoneOffset;

/// "UTC+3", "UTC-5", "UTC+5:30".
String formatZoneOffset(Duration d) {
  final sign = d.isNegative ? '-' : '+';
  final minutes = d.inMinutes.abs();
  final h = minutes ~/ 60, m = minutes % 60;
  return 'UTC$sign$h${m == 0 ? '' : ':${m.toString().padLeft(2, '0')}'}';
}
