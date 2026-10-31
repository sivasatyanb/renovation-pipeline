import 'package:flutter/foundation.dart';
import '../models/models.dart';

typedef OnCallPressedCallback = void Function(Contractor contractor);

void defaultOnCallPressed(Contractor contractor) {
  debugPrint('Call pressed for contractor: ${contractor.id}');
}
