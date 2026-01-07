import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkStatus {
  online,
  offline,
  unknown,
}

enum NetworkType {
  wifi,
  ethernet,
  mobile4G,
  mobile3G,
  mobile2G,
  vpn,
  none,
  unknown,
}

class ConnectivityService {
  final Connectivity _connectivity = Connectivity();
  final _statusController = StreamController<NetworkStatus>.broadcast();
  final _typeController = StreamController<NetworkType>.broadcast();
  
  NetworkStatus _currentStatus = NetworkStatus.unknown;
  NetworkType _currentType = NetworkType.unknown;
  StreamSubscription? _connectivitySubscription;

  Stream<NetworkStatus> get statusStream => _statusController.stream;
  Stream<NetworkType> get typeStream => _typeController.stream;
  NetworkStatus get currentStatus => _currentStatus;
  NetworkType get currentType => _currentType;
  bool get isOnline => _currentStatus == NetworkStatus.online;
  bool get isSlowNetwork => _currentType == NetworkType.mobile2G || _currentType == NetworkType.mobile3G;

  ConnectivityService() {
    _initialize();
  }

  void _initialize() {
    // Check initial connectivity
    _checkConnectivity();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
      onError: (error) {
        print('Connectivity error: $error');
      },
    );
  }

  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectionStatus(results);
    } catch (e) {
      print('Failed to check connectivity: $e');
      _updateStatus(NetworkStatus.unknown, NetworkType.unknown);
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      _updateStatus(NetworkStatus.offline, NetworkType.none);
      return;
    }

    final result = results.first;

    // Determine network type and status
    NetworkStatus status;
    NetworkType type;

    switch (result) {
      case ConnectivityResult.wifi:
        status = NetworkStatus.online;
        type = NetworkType.wifi;
        break;
      case ConnectivityResult.ethernet:
        status = NetworkStatus.online;
        type = NetworkType.ethernet;
        break;
      case ConnectivityResult.mobile:
        status = NetworkStatus.online;
        // Note: connectivity_plus doesn't distinguish 2G/3G/4G
        // We default to 4G but apps can use telephony_info package for precise detection
        type = NetworkType.mobile4G;
        break;
      case ConnectivityResult.vpn:
        status = NetworkStatus.online;
        type = NetworkType.vpn;
        break;
      case ConnectivityResult.none:
        status = NetworkStatus.offline;
        type = NetworkType.none;
        break;
      default:
        status = NetworkStatus.unknown;
        type = NetworkType.unknown;
    }

    _updateStatus(status, type);
  }

  void _updateStatus(NetworkStatus status, NetworkType type) {
    bool changed = false;
    
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);
      changed = true;
    }
    
    if (_currentType != type) {
      _currentType = type;
      _typeController.add(type);
      changed = true;
    }
    
    if (changed) {
      print('Network changed: $status ($type)');
    }
  }

  /// Force refresh connectivity status
  Future<void> refresh() async {
    await _checkConnectivity();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _statusController.close();
    _typeController.close();
  }
}
