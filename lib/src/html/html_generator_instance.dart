// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async' show Future;
import 'dart:convert' show JsonEncoder;
import 'dart:io' show File, stdout;

import 'package:collection/collection.dart' show compareNatural;
import 'package:path/path.dart' as path;

import '../model.dart';
import '../warnings.dart';
import 'html_generator.dart' show HtmlGeneratorOptions;
import 'resource_loader.dart' as loader;
import 'resources.g.dart' as resources;
import 'template_data.dart';
import 'templates.dart';

typedef void FileWriter(String path, Object content);

class HtmlGeneratorInstance {
  final HtmlGeneratorOptions _options;
  final Templates _templates;
  final Package _package;
  final List<ModelElement> _documentedElements = <ModelElement>[];
  final FileWriter _writer;

  HtmlGeneratorInstance(
      this._options, this._templates, this._package, this._writer);

  Future generate() async {
    if (_package != null) {
      _generateDocs();
      _generateSearchIndex();
    }

    await _copyResources();
    if (_options.faviconPath != null) {
      var bytes = new File(_options.faviconPath).readAsBytesSync();
      _writer(path.join('static-assets', 'favicon.png'), bytes);
    }
  }

  void _generateSearchIndex() {
    var encoder = _options.prettyIndexJson
        ? new JsonEncoder.withIndent(' ')
        : new JsonEncoder();

    final List<Map> indexItems =
        _documentedElements.where((e) => e.isCanonical).map((ModelElement e) {
      var data = <String, dynamic>{
        'name': e.name,
        'qualifiedName': e.name,
        'href': e.href,
        'type': e.kind,
        'overriddenDepth': e.overriddenDepth,
      };
      if (e is EnclosedElement) {
        EnclosedElement ee = e as EnclosedElement;
        data['enclosedBy'] = {
          'name': ee.enclosingElement.name,
          'type': ee.enclosingElement.kind
        };

        data['qualifiedName'] = e.fullyQualifiedName;
      }
      return data;
    }).toList();

    indexItems.sort((a, b) {
      var value = compareNatural(a['qualifiedName'], b['qualifiedName']);
      if (value == 0) {
        value = compareNatural(a['type'], b['type']);
      }
      return value;
    });

    String json = encoder.convert(indexItems);
    _writer(path.join('index.json'), '${json}\n');
  }

  void _generateDocs() {
    if (_package == null) return;

    generatePackage();

    for (var lib in _package.libraries) {
      generateLibrary(_package, lib);

      for (var clazz in lib.allClasses) {
        // TODO(jcollins-g): consider refactor so that only the canonical
        // ModelElements show up in these lists
        if (!clazz.isCanonical) continue;

        generateClass(_package, lib, clazz);

        for (var constructor in clazz.constructors) {
          if (!constructor.isCanonical) continue;
          generateConstructor(_package, lib, clazz, constructor);
        }

        for (var constant in clazz.constants) {
          if (!constant.isCanonical) continue;
          generateConstant(_package, lib, clazz, constant);
        }

        for (var property in clazz.staticProperties) {
          if (!property.isCanonical) continue;
          generateProperty(_package, lib, clazz, property);
        }

        for (var property in clazz.propertiesForPages) {
          if (!property.isCanonical) continue;
          generateProperty(_package, lib, clazz, property);
        }

        for (var method in clazz.methodsForPages) {
          if (!method.isCanonical) continue;
          generateMethod(_package, lib, clazz, method);
        }

        for (var operator in clazz.operatorsForPages) {
          if (!operator.isCanonical) continue;
          generateMethod(_package, lib, clazz, operator);
        }

        for (var method in clazz.staticMethods) {
          if (!method.isCanonical) continue;
          generateMethod(_package, lib, clazz, method);
        }
      }

      for (var eNum in lib.enums) {
        if (!eNum.isCanonical) continue;
        generateEnum(_package, lib, eNum);
        for (var property in eNum.propertiesForPages) {
          if (!property.isCanonical) continue;
          generateProperty(_package, lib, eNum, property);
        }
        for (var operator in eNum.operatorsForPages) {
          if (!operator.isCanonical) continue;
          generateMethod(_package, lib, eNum, operator);
        }
        for (var method in eNum.methodsForPages) {
          if (!method.isCanonical) continue;
          generateMethod(_package, lib, eNum, method);
        }
      }

      for (var constant in lib.constants) {
        if (!constant.isCanonical) continue;
        generateTopLevelConstant(_package, lib, constant);
      }

      for (var property in lib.properties) {
        if (!property.isCanonical) continue;
        generateTopLevelProperty(_package, lib, property);
      }

      for (var function in lib.functions) {
        if (!function.isCanonical) continue;
        generateFunction(_package, lib, function);
      }

      for (var typeDef in lib.typedefs) {
        if (!typeDef.isCanonical) continue;
        generateTypeDef(_package, lib, typeDef);
      }
    }
  }

  void generatePackage() {
    TemplateData data =
        new PackageTemplateData(_options, _package, _options.useCategories);
    stdout.write('\ndocumenting ${_package.name}');

    _build('index.html', _templates.indexTemplate, data);
  }

  void generateLibrary(Package package, Library lib) {
    stdout
        .write('\ngenerating docs for library ${lib.name} from ${lib.path}...');
    if (!lib.isAnonymous && !lib.hasDocumentation) {
      package.warnOnElement(lib, PackageWarning.noLibraryLevelDocs);
    }
    TemplateData data =
        new LibraryTemplateData(_options, package, lib, _options.useCategories);

    _build(path.join(lib.dirName, '${lib.fileName}'),
        _templates.libraryTemplate, data);
  }

  void generateClass(Package package, Library lib, Class clazz) {
    TemplateData data = new ClassTemplateData(_options, package, lib, clazz);
    _build(path.joinAll(clazz.href.split('/')), _templates.classTemplate, data);
  }

  void generateConstructor(
      Package package, Library lib, Class clazz, Constructor constructor) {
    TemplateData data =
        new ConstructorTemplateData(_options, package, lib, clazz, constructor);

    _build(path.joinAll(constructor.href.split('/')),
        _templates.constructorTemplate, data);
  }

  void generateEnum(Package package, Library lib, Enum eNum) {
    TemplateData data = new EnumTemplateData(_options, package, lib, eNum);

    _build(path.joinAll(eNum.href.split('/')), _templates.enumTemplate, data);
  }

  void generateFunction(Package package, Library lib, ModelFunction function) {
    TemplateData data =
        new FunctionTemplateData(_options, package, lib, function);

    _build(path.joinAll(function.href.split('/')), _templates.functionTemplate,
        data);
  }

  void generateMethod(
      Package package, Library lib, Class clazz, Method method) {
    TemplateData data =
        new MethodTemplateData(_options, package, lib, clazz, method);

    _build(
        path.joinAll(method.href.split('/')), _templates.methodTemplate, data);
  }

  void generateConstant(
      Package package, Library lib, Class clazz, Field property) {
    TemplateData data =
        new ConstantTemplateData(_options, package, lib, clazz, property);

    _build(path.joinAll(property.href.split('/')), _templates.constantTemplate,
        data);
  }

  void generateProperty(
      Package package, Library lib, Class clazz, Field property) {
    TemplateData data =
        new PropertyTemplateData(_options, package, lib, clazz, property);

    _build(path.joinAll(property.href.split('/')), _templates.propertyTemplate,
        data);
  }

  void generateTopLevelProperty(
      Package package, Library lib, TopLevelVariable property) {
    TemplateData data =
        new TopLevelPropertyTemplateData(_options, package, lib, property);

    _build(path.joinAll(property.href.split('/')),
        _templates.topLevelPropertyTemplate, data);
  }

  void generateTopLevelConstant(
      Package package, Library lib, TopLevelVariable property) {
    TemplateData data =
        new TopLevelConstTemplateData(_options, package, lib, property);

    _build(path.joinAll(property.href.split('/')),
        _templates.topLevelConstantTemplate, data);
  }

  void generateTypeDef(Package package, Library lib, Typedef typeDef) {
    TemplateData data =
        new TypedefTemplateData(_options, package, lib, typeDef);

    _build(path.joinAll(typeDef.href.split('/')), _templates.typeDefTemplate,
        data);
  }

  // TODO: change this to use resource_loader
  Future _copyResources() async {
    final prefix = 'package:dartdoc/resources/';
    for (String resourcePath in resources.resource_names) {
      if (!resourcePath.startsWith(prefix)) {
        throw new StateError('Resource paths must start with $prefix, '
            'encountered $resourcePath');
      }
      String destFileName = resourcePath.substring(prefix.length);
      _writer(path.join('static-assets', destFileName),
          await loader.loadAsBytes(resourcePath));
    }
  }

  void _build(String filename, TemplateRenderer template, TemplateData data) {
    String content = template(data,
        assumeNullNonExistingProperty: false, errorOnMissingProperty: true);

    _writer(filename, content);
    if (data.self is ModelElement) {
      _documentedElements.add(data.self);
    }
  }
}
