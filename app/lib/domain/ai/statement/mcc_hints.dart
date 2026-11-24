/// Category words (Ukrainian) a merchant category code suggests, or null.
/// The words feed the same hint path as a bank's own category.
String? mccHint(int mcc) {
  if (const {5411, 5422, 5462, 5499, 5441, 5451}.contains(mcc)) return 'Продукти';
  if (const {5812, 5813, 5814}.contains(mcc)) return 'Кафе і ресторани';
  if (const {4131, 4111, 4121}.contains(mcc)) return 'Проїзд';
  if (const {4722, 4511, 7011, 4112}.contains(mcc)) return 'Подорожі';
  if (const {5912, 5047, 8011, 8021, 8062}.contains(mcc)) return "Здоров'я";
  if (const {5651, 5691, 5699, 5661}.contains(mcc)) return 'Одяг';
  if (mcc == 5977) return 'Косметика';
  if (const {4812, 4814}.contains(mcc)) return "Зв'язок";
  if (const {5262, 5311, 5399}.contains(mcc)) return 'Покупки';
  if (const {7399, 7999, 7991}.contains(mcc)) return 'Розваги';
  if (const {5719, 5983}.contains(mcc)) return 'Дім';
  return null;
}
