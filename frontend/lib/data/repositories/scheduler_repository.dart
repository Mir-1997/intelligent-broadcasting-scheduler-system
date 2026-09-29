import '../api/scheduler_api_client.dart';
import '../models/models.dart';
import '../realtime/scheduler_socket.dart';

/// The single data entry point for the blocs.
///
/// Reads and commands go over REST ([SchedulerApiClient]); live state arrives
/// over the WebSocket ([SchedulerSocket]). Command responses are deliberately
/// not applied to UI state: the WebSocket is the single source of truth, which
/// keeps every open browser tab consistent (see docs/adr/0004).
class SchedulerRepository {
  SchedulerRepository({
    required SchedulerApiClient api,
    required SchedulerSocket socket,
  }) : _api = api,
       _socket = socket;

  final SchedulerApiClient _api;
  final SchedulerSocket _socket;

  Stream<ServerEvent> get events => _socket.events;

  Stream<ConnectionStatus> get connectionChanges => _socket.statusChanges;

  ConnectionStatus get connectionStatus => _socket.status;

  void connect() => _socket.connect();

  Future<Admin> fetchAdmin() => _api.getAdmin();

  Future<SchedulerSnapshot> fetchState() => _api.getState();

  Future<List<Assignment>> fetchAssignments({int limit = 50}) =>
      _api.getAssignments(limit: limit);

  Future<void> addPackage(PackageDraft draft) => _api.addPackage(draft);

  Future<void> addRider(RiderDraft draft) => _api.addRider(draft);

  Future<void> removePackage(String id) => _api.removePackage(id);

  Future<void> removeRider(String id) => _api.removeRider(id);

  Future<void> simulate(SimulationDraft draft) => _api.simulate(draft);

  Future<void> reset() => _api.reset();

  Future<void> dispose() async {
    await _socket.dispose();
    _api.close();
  }
}
