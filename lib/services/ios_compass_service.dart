// Default implementation (Mobile/Desktop) - does nothing
Future<String> requestIOSCompassPermission() async {
  return 'not_supported';
}

Stream<double?> getIOSWebCompassStream() {
  return const Stream.empty();
}
