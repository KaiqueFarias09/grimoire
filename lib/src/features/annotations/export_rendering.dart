import 'package:e_livre_viewer/src/features/annotations/export_document.dart';
import 'package:e_livre_viewer/src/features/annotations/export_html.dart';
import 'package:e_livre_viewer/src/features/annotations/export_markdown.dart';
import 'package:e_livre_viewer/src/features/annotations/export_plain_text.dart';

/// Convenience rendering operations kept above the immutable document layer.
extension ViewerExportRendering on ViewerExportModel {
  /// Renders this document as Markdown.
  String toMarkdown({
    final ViewerMarkdownExportOptions options = const ViewerMarkdownExportOptions(),
  }) => renderMarkdown(this, options);

  /// Renders this document as a standalone HTML document, or as a fragment
  /// when [ViewerHtmlExportOptions.includeDocumentShell] is false.
  String toHtml({final ViewerHtmlExportOptions options = const ViewerHtmlExportOptions()}) =>
      renderHtml(this, options);

  /// Renders this document as plain text using its snapshot options.
  String toPlainText() => renderPlainText(this);
}
