import 'ring_auth.dart';
import 'ring_client.dart';
import 'token_store.dart';

/// The app's single set of Ring services.
///
/// One [RingAuth] for the whole process matters: it caches the access token and
/// serialises refreshes, so a grid of tiles polling at once cannot stampede the
/// token endpoint.
class Services {
  Services._();

  static Services? _instance;

  static Services get instance => _instance ??= Services._();

  late final TokenStore store = TokenStore();
  late final RingAuth auth = RingAuth(store: store);
  late final RingClient client = RingClient(auth: auth);
}

/// Shorthand for [Services.instance].
Services get services => Services.instance;
