import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GatewaySupabase {
  static String get configuredUrl {
    const dartDefineUrl = String.fromEnvironment('SUPABASE_URL');
    return dartDefineUrl.isNotEmpty
        ? dartDefineUrl
        : dotenv.env['SUPABASE_URL'] ?? '';
  }

  static String get configuredServiceRoleKey {
    const dartDefineKey = String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');
    return dartDefineKey.isNotEmpty
        ? dartDefineKey
        : dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';
  }

  static Future<void> initialize() async {
    await dotenv.load(fileName: '.env', isOptional: true);

    final url = configuredUrl;
    final serviceRoleKey = configuredServiceRoleKey;

    assert(
      url.isNotEmpty,
      'SUPABASE_URL is missing. Set it in .env or via --dart-define.',
    );
    assert(
      serviceRoleKey.isNotEmpty,
      'SUPABASE_SERVICE_ROLE_KEY is missing. Set it in .env or via --dart-define.',
    );
    if (url.isEmpty || serviceRoleKey.isEmpty) {
      throw StateError(
        'Supabase configuration is missing. Set URL and service role key.',
      );
    }

    await Supabase.initialize(
      url: url,
      publishableKey: serviceRoleKey,
      debug: false,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
