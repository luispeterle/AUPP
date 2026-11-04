import 'package:flutter_test/flutter_test.dart';
import 'package:aupp/dinzo/dinzo-rate-limit.dart';
import 'package:aupp/services/service-config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const now = 1000000;

  test('under the budget nothing waits', () {
    final sent = [for (var i = 0; i < 79; i++) now - i * 100];
    expect(DinzoRateLimiter.waitFor(sent, now), Duration.zero);
  });

  test('at 80 in the last minute, waits until the oldest leaves it', () {
    // 80 requests, the oldest 50 s ago.
    final sent = [now - 50000, for (var i = 0; i < 79; i++) now - i * 10];
    expect(DinzoRateLimiter.waitFor(sent, now), const Duration(seconds: 10));
  });

  test('requests older than a minute do not count (app reopened later)', () {
    final sent = [for (var i = 0; i < 200; i++) now - 61000 - i];
    expect(DinzoRateLimiter.waitFor(sent, now), Duration.zero);
  });

  test('counts the last minute and the last 24 h, kept in preferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    ServiceConfig.sharedPreferences = await SharedPreferences.getInstance();
    for (var i = 0; i < 3; i++) {
      await DinzoRateLimiter.acquire();
    }
    expect(DinzoRateLimiter.lastMinute, 3);
    expect(DinzoRateLimiter.last24h, 3);
    expect(
      ServiceConfig.sharedPreferences!.getString('dinzoRequestDaily'),
      isNotNull,
    );
    await DinzoRateLimiter.recordServer('"default";r=117;t=60');
    expect(DinzoRateLimiter.serverRemaining, 117);
  });
}
