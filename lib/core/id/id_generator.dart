import 'package:uuid/uuid.dart';

class IdGenerator {
  IdGenerator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  String next() => _uuid.v7();
}
