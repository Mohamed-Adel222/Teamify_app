import 'configure_url_strategy_stub.dart'
    if (dart.library.html) 'configure_url_strategy_web.dart';

void configureAppUrlStrategy() => configureUrlStrategy();
