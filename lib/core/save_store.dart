import 'save_data.dart';

/// Minimal key-value persistence. Implemented with SharedPreferences in the
/// app (works on Android, iOS and Web) and in-memory in tests.
abstract class KeyValueBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class MemoryBackend implements KeyValueBackend {
  final Map<String, String> data = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('disk full');
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async => data.remove(key);
}

/// Outcome of loading, so the UI can tell the player what happened.
enum LoadOutcome { fresh, primary, recoveredFromBackup, corruptReset }

/// Safe saving (doc 6.3, 12.1, 12.11, 12.14):
/// * every write is wrapped with a checksum;
/// * the previous good save rotates into N backups before overwriting;
/// * on load, a corrupt primary falls back to the newest valid backup;
/// * a "pending" slot makes a crash mid-write recoverable.
class SaveStore {
  final KeyValueBackend backend;
  final String prefix;
  final int backupCount;

  SaveStore(this.backend, {this.prefix = 'gs100', this.backupCount = 3});

  String get _primary => '$prefix.save';
  String get _pending => '$prefix.save.pending';
  String _backup(int i) => '$prefix.save.bak$i';

  LoadOutcome lastOutcome = LoadOutcome.fresh;
  int writeFailures = 0;

  /// Simple, fast checksum (Adler-32) of the payload.
  static int checksum(String s) {
    var a = 1, b = 0;
    for (final c in s.codeUnits) {
      a = (a + c) % 65521;
      b = (b + a) % 65521;
    }
    return (b << 16) | a;
  }

  static String wrap(String payload) => '${checksum(payload)}|$payload';

  static String? unwrap(String? stored) {
    if (stored == null) return null;
    final i = stored.indexOf('|');
    if (i <= 0) return null;
    final sum = int.tryParse(stored.substring(0, i));
    final payload = stored.substring(i + 1);
    if (sum == null || sum != checksum(payload)) return null;
    return payload;
  }

  SaveData? _parse(String? stored) {
    final payload = unwrap(stored);
    if (payload == null) return null;
    try {
      return SaveData.decode(payload);
    } catch (_) {
      return null;
    }
  }

  Future<SaveData> load() async {
    final primaryRaw = await backend.read(_primary);
    final pendingRaw = await backend.read(_pending);
    // A completed pending write that never got promoted is the newest data.
    final pending = _parse(pendingRaw);
    if (pending != null) {
      lastOutcome = LoadOutcome.recoveredFromBackup;
      await _promote(pendingRaw!);
      return pending;
    }
    final primary = _parse(primaryRaw);
    if (primary != null) {
      lastOutcome = LoadOutcome.primary;
      return primary;
    }
    for (var i = 0; i < backupCount; i++) {
      final b = _parse(await backend.read(_backup(i)));
      if (b != null) {
        lastOutcome = LoadOutcome.recoveredFromBackup;
        await save(b);
        return b;
      }
    }
    lastOutcome =
        primaryRaw == null ? LoadOutcome.fresh : LoadOutcome.corruptReset;
    return SaveData();
  }

  Future<void> _promote(String wrapped) async {
    await backend.write(_primary, wrapped);
    await backend.remove(_pending);
  }

  /// Returns false if the write failed (the in-memory state is kept and
  /// the next save retries).
  Future<bool> save(SaveData data) async {
    try {
      final wrapped = wrap(data.encode());
      await backend.write(_pending, wrapped);
      final old = await backend.read(_primary);
      if (unwrap(old) != null) {
        for (var i = backupCount - 1; i > 0; i--) {
          final prev = await backend.read(_backup(i - 1));
          if (prev != null) await backend.write(_backup(i), prev);
        }
        await backend.write(_backup(0), old!);
      }
      await _promote(wrapped);
      return true;
    } catch (_) {
      writeFailures++;
      return false;
    }
  }

  /// Exportable backup string (player can copy it / cloud sync later).
  String exportBackup(SaveData d) => wrap(d.encode());

  SaveData? importBackup(String text) => _parse(text.trim());

  Future<void> wipe() async {
    await backend.remove(_primary);
    await backend.remove(_pending);
    for (var i = 0; i < backupCount; i++) {
      await backend.remove(_backup(i));
    }
  }
}
