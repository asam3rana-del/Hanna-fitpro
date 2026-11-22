/// App / developer ki public maloomat — About screen, receipts aur store listing ek hi jagah se.
class AppInfo {
  AppInfo._();

  /// App ka naam (phone / PC par icon ke neeche). Badalna ho to yahan + build.yml + tools/android_fix.sh.
  static const appName = 'Hanna Fitness';
  static const tagline = 'Premium Gym Management';
  static const developer = 'Asam Hameed';
  static const business = 'Hanna Solutions';
  static const appId = 'com.hannasolutions.fitness';
  static const address = 'Ibtisaam Traders, Bhikhi';
  static const supportEmail = 'hannasolutions1@gmail.com';
  static const supportPhone = '03006296815';
  static const supportWhatsAppIntl = '923006296815';

  /// CI: `--dart-define=APP_BUILD=<run number>`; local / purani build par khali.
  static const build = String.fromEnvironment('APP_BUILD');
}
