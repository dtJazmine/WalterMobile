import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

final FirebaseDatabase rtdb = FirebaseDatabase.instanceFor(
  app: Firebase.app(),
  databaseURL:
      'https://qr-based-real-time-monitoring-default-rtdb.asia-southeast1.firebasedatabase.app',
);