import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:hive_generator/src/class_builder.dart';
import 'package:hive_generator/src/enum_builder.dart';
import 'package:hive_generator/src/helper.dart';
import 'package:source_gen/source_gen.dart';
import 'package:hive/hive.dart';
import 'package:built_value/built_value.dart' as built_value;

class TypeAdapterGenerator extends GeneratorForAnnotation<HiveType> {
  var builtChecker = const TypeChecker.fromRuntime(built_value.Built);

  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    var cls = getClass(element);
    var fields = getFields(cls);
    var adapterName = getAdapterName(cls.name, annotation);
    var builder =
        cls.isEnum ? EnumBuilder(cls, fields) : ClassBuilder(cls, fields);

    return '''

    class $adapterName extends TypeAdapter<${cls.name}> {
      @override
      ${cls.name} read(BinaryReader reader) {
        ${builder.buildRead()}
      }

      @override
      void write(BinaryWriter writer, ${cls.name} obj) {
        ${builder.buildWrite()}
      }
    }
    ''';
  }

  ClassElement getClass(Element element) {
    check(element.kind == ElementKind.CLASS,
        'Only classes or enums are allowed to be annotated with @HiveType.');

    var cls = element as ClassElement;

    return cls;
  }

  Map<int, FieldElement> _getFields(ClassElement cls, bool isBuiltValue) {
    var typeFields = <int, FieldElement>{};
    var fieldNum = 0;
    for (var field in cls.fields) {
      if (isBuiltValue && field.name == 'serializer') {
        continue;
      } else if (!isBuiltValue) {
        var fieldAnn = getHiveFieldAnn(field);
        if (fieldAnn == null) continue;
        fieldNum = fieldAnn.index;
      }
      check(fieldNum >= 0 || fieldNum <= 255,
          'Field numbers can only be in the range 0-255.');
      check(!typeFields.containsKey(fieldNum),
          'Duplicate field number: $fieldNum.');
      typeFields[fieldNum] = field;
      fieldNum += 1;
    }
    return typeFields;
  }

  Map<int, FieldElement> getFields(ClassElement cls) {
    return _getFields(cls, builtChecker.isAssignableFrom(cls));
  }

  String getAdapterName(String typeName, ConstantReader annotation) {
    var annAdapterName = annotation.read('adapterName');
    if (annAdapterName.isNull) {
      return '${typeName}Adapter';
    } else {
      return annAdapterName.stringValue;
    }
  }
}
