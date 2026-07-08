import 'dart:convert';
import 'dart:io';

// The pure-Dart SVG extractor (no Flutter), so this CLI runs under a plain
// `dart`. It's the SAME extraction the runtime uses, so the baked manifest can't
// drift from a live parse.
import 'package:iconic_morph/src/svg/extract.dart';

/// Bakes a folder of SVG icons into an `iconic_morph` geometry manifest, so you
/// can ship the JSON instead of the SVGs and skip runtime parsing.
///
///     dart run iconic_morph:bake <svg-dir> <out.json> [--prefix <key-prefix>]
///
/// Then at startup: `IconGeometry.useManifest('<out.json>')`.
void main(List<String> args) {
  final positional = <String>[];
  String? prefix;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--prefix') {
      if (i + 1 >= args.length) {
        stderr.writeln('bake: --prefix needs a value\n\n$_usage');
        exitCode = 64;
        return;
      }
      prefix = args[++i];
    } else if (a == '-h' || a == '--help') {
      stdout.writeln(_usage);
      return;
    } else {
      positional.add(a);
    }
  }

  if (positional.length != 2) {
    stderr.writeln(_usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final svgDir = Directory(positional[0]);
  final outFile = File(positional[1]);
  if (!svgDir.existsSync()) {
    stderr.writeln('bake: input directory not found: ${svgDir.path}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  // Default key prefix = the input dir, so each key matches the on-disk asset
  // path (e.g. `assets/icons/foo.svg`) you declare in pubspec and pass to a
  // widget. Override with --prefix when your runtime paths differ.
  final rawBase = (prefix ?? svgDir.path).replaceAll(r'\', '/');
  final base = rawBase.isEmpty || rawBase.endsWith('/') ? rawBase : '$rawBase/';

  final files = svgDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.svg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final manifest = <String, Object?>{};
  for (final f in files) {
    final rel = f.path
        .substring(svgDir.path.length)
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'^/'), '');
    final g = extractSvgGeometry(f.readAsStringSync());
    manifest['$base$rel'] = {
      'vb': g.viewBox,
      'fill': g.isFill,
      'd': g.pathData,
    };
  }

  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest));
  stdout.writeln('bake: wrote ${manifest.length} icon(s) → ${outFile.path}');
}

const _usage = '''
Bake a folder of SVG icons into an iconic_morph geometry manifest.

Usage:
  dart run iconic_morph:bake <svg-dir> <out.json> [--prefix <key-prefix>]

  <svg-dir>     folder of .svg files (searched recursively)
  <out.json>    manifest file to write
  --prefix <p>  key prefix for each icon (default: "<svg-dir>/").
                Keys must match the asset paths you pass to the widgets.

Then at startup:
  IconGeometry.useManifest('<out.json>');
''';
