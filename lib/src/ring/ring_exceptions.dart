/// Errors surfaced by the Ring client.
///
/// Ring does not publish a developer API; everything here talks to the private
/// endpoints used by the official mobile apps. Amazon can change them without
/// notice, so failures are modelled explicitly rather than left as raw HTTP
/// errors — the UI needs to tell "wrong password" apart from "protocol drifted".
library;

class RingException implements Exception {
  const RingException(this.message);

  final String message;

  @override
  String toString() => 'RingException: $message';
}

/// Credentials were rejected outright.
class RingAuthException extends RingException {
  const RingAuthException(super.message);
}

/// Ring accepted the credentials but wants a two-factor code.
///
/// [phone] is the masked destination Ring reports (e.g. "+39 ***-**-1234") and
/// [tsvState] tells us how the code was delivered ("sms", "totp", ...).
class RingTwoFactorRequired extends RingException {
  const RingTwoFactorRequired({required this.phone, required this.tsvState})
    : super('Two-factor verification required');

  final String? phone;
  final String? tsvState;

  bool get isTotp => tsvState == 'totp';
}

/// The stored refresh token is no longer usable — the user must log in again.
class RingSessionExpired extends RingException {
  const RingSessionExpired() : super('Ring session expired, log in again');
}
