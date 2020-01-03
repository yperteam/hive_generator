import 'dart:typed_data';

import 'package:built_value/built_value.dart' as built_value;
import 'package:built_collection/built_collection.dart' as built_collection;
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:hive/hive.dart';
import 'package:hive_generator/src/builder.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';
import 'package:dartx/dartx.dart';

class ClassBuilder extends Builder {
  var hiveListChecker = const TypeChecker.fromRuntime(HiveList);
  var listChecker = const TypeChecker.fromRuntime(List);
  var mapChecker = const TypeChecker.fromRuntime(Map);
  var setChecker = const TypeChecker.fromRuntime(Set);
  var iterableChecker = const TypeChecker.fromRuntime(Iterable);
  var uint8ListChecker = const TypeChecker.fromRuntime(Uint8List);
  var builtChecker = const TypeChecker.fromRuntime(built_value.Built);
  var builtListChecker =
      const TypeChecker.fromRuntime(built_collection.BuiltList);

  ClassBuilder(
      ClassElement cls, List<AdapterField> getters, List<AdapterField> setters)
      : super(cls, getters, setters);

  String _constructorPrefix(bool isBuiltValue) {
    return isBuiltValue ? 'return ${cls.name}((e) => e' : 'return ${cls.name}(';
  }

  @override
  String buildRead() {
    var isBuiltValue = builtChecker.isAssignableFrom(cls);
    var code = StringBuffer();
    code.writeln('''
    var numOfFields = reader.readByte();
    var fields = <int, dynamic>{
      for (var i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    ${_constructorPrefix(isBuiltValue)}
    ''');

    var constr = cls.constructors.firstOrNullWhere((it) => it.name.isEmpty);
    check(constr != null, 'Provide an unnamed constructor.');

    // The remaining fields to initialize.
    var fields = setters.toList();

    var initializingParams =
        constr.parameters.where((param) => param.isInitializingFormal);
    for (var param in initializingParams) {
      var field = fields.firstOrNullWhere((it) => it.name == param.name);
      if (field != null) {
        if (param.isNamed) {
          code.write('${param.name}: ');
        }
        code.writeln('${_cast(param.type, 'fields[${field.index}]')},');
        fields.remove(field);
      }
    }

    if (!isBuiltValue) code.writeln(')');

    // There may still be fields to initialize that were not in the constructor
    // as initializing formals. We do so using cascades.
    for (var field in fields) {
      code.writeln(
          '..${field.name} = ${_cast(field.type, 'fields[${field.index}]')}');
    }

    code.writeln(isBuiltValue ? ');' : ';');

    return code.toString();
  }

  String _cast(DartType type, String variable) {
    if (builtListChecker.isAssignableFromType(type)) {
      return 'ListBuilder(($variable as List)${_castIterable(type)})';
    } else if (hiveListChecker.isExactlyType(type)) {
      return '($variable as HiveList)?.castHiveList()';
    } else if (iterableChecker.isAssignableFromType(type) &&
        !isUint8List(type)) {
      return '($variable as List)${_castIterable(type)}';
    } else if (mapChecker.isExactlyType(type)) {
      return '($variable as Map)${_castMap(type)}';
    } else if (builtChecker.isAssignableFromType(type)) {
      return '(${type.name}Builder()..replace($variable as ${type.name}))';
    } else {
      return '$variable as ${type.name}';
    }
  }

  bool isMapOrIterable(DartType type) {
    return listChecker.isExactlyType(type) ||
        setChecker.isExactlyType(type) ||
        iterableChecker.isExactlyType(type) ||
        mapChecker.isExactlyType(type);
  }

  bool isUint8List(DartType type) {
    return uint8ListChecker.isExactlyType(type);
  }

  String _castIterable(DartType type) {
    var paramType = type as ParameterizedType;
    var arg = paramType.typeArguments[0];
    if (isMapOrIterable(arg) && !isUint8List(arg)) {
      var cast = '';
      if (listChecker.isExactlyType(type)) {
        cast = '?.toList()';
      } else if (setChecker.isExactlyType(type)) {
        cast = '?.toSet()';
      }
      return '?.map((dynamic e)=> ${_cast(arg, 'e')})$cast';
    } else {
      return '?.cast<${arg.name}>()';
    }
  }

  String _castMap(DartType type) {
    var paramType = type as ParameterizedType;
    var arg1 = paramType.typeArguments[0];
    var arg2 = paramType.typeArguments[1];
    if (isMapOrIterable(arg1) || isMapOrIterable(arg2)) {
      return '?.map((dynamic k, dynamic v)=>'
          'MapEntry(${_cast(arg1, 'k')},${_cast(arg2, 'v')}))';
    } else {
      return '?.cast<${arg1.name}, ${arg2.name}>()';
    }
  }

  @override
  String buildWrite() {
    var code = StringBuffer();
    code.writeln('writer');
    code.writeln('..writeByte(${getters.length})');
    for (var field in getters) {
      var value = _convertIterable(field.type, 'obj.${field.name}');
      code.writeln('''
      ..writeByte(${field.index})
      ..write($value)''');
    }
    code.writeln(';');

    return code.toString();
  }

  String _convertIterable(DartType type, String accessor) {
    if (setChecker.isExactlyType(type) ||
        iterableChecker.isExactlyType(type) ||
        builtListChecker.isAssignableFromType(type)) {
      return '$accessor?.toList()';
    } else {
      return accessor;
    }
  }
}
