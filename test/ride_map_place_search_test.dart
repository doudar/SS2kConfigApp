import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ss2kconfigapp/services/ride_map_place_search.dart';

void main() {
  test(
    'city lookup identifies SmartSpin2k to Photon and reads the result',
    () async {
      final places = await http.runWithClient(
        () => searchRideMapPlaces('Eau Claire, WI'),
        () => MockClient((request) async {
          expect(request.url.queryParameters['q'], 'Eau Claire, WI');
          expect(request.headers['User-Agent'], startsWith('SmartSpin2k/'));
          return http.Response(
            '{"features":[{"properties":{"name":"Eau Claire","state":"Wisconsin","country":"United States"},'
            '"geometry":{"coordinates":[-91.4984941,44.811349]}}]}',
            200,
          );
        }),
      );
      expect(places.single, (
        name: 'Eau Claire, Wisconsin, United States',
        lat: 44.811349,
        lon: -91.4984941,
      ));
    },
  );
}
