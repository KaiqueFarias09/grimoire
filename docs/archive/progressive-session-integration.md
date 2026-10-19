# Archived progressive-session integration notes

This Portuguese note records one integration stage for Unseal's `BookSession`
path. Its source details and test counts are historical. See the current
[architecture guide](../architecture.md) and
[development guide](../development.md) for package boundaries and commands.

## API introduzida

- `ViewerController.session(BookSession session, {…mesmas opções do
  construtor})` — `book` exposto é `session.book` (header: estrutura
  completa, `files` vazio). `dispose()` fecha a sessão.
  `BookSession? get session` exposto para consumidores (Narration).
- `BookServer(contentResolver: …)` (io e web): resolver opcional
  `Future<Object?> Function(String path)` (String = texto, Uint8List =
  binário). `isResolverBacked` indica o modo. Sem resolver, o snapshot
  de `book.files` no `start()` continua existindo (compatibilidade).

## Como o caminho da sessão difere

1. **Serving**: cada requisição passa pelo resolver (sessão
   `loadResource`/`loadDocumentSource`), com dedupe de fetches
   simultâneos do mesmo path e byte-ranges preservados no io. No web,
   blobs são criados quando o conteúdo chega (`urlForPathAsync`).
2. **Progressão**: `session.computeProgression()` roda em background
   pós-abertura; `progress` reflete o valor quando chega (0 antes).
3. **Busca**: `session.search`; sem sessão, `book.search` inline.
4. **CFI**: book-level via `session.resolveCfi`; build via
   `session.buildCfi`. O scan file-local carrega candidatos por
   `loadDocumentSource` e NÃO memoiza falhas (o cache negativo antigo
   envenenava índices).
5. **Texto de capítulo** (`documentTextFor`, usado por TTS e excerpts):
   fetch sob demanda pela sessão, memoizado só após chegar.
6. **MathJax**: decisão por página no prepare do HTML; o sniff global
   de abertura só roda sem sessão.
7. **FXL**: inalterado — spine/rendition/viewports vêm no header; o
   spread garante o par carregado antes de montar a URL.
8. **Narration**: `MediaOverlayCatalog(book, loadDocumentSource:)`
   recebe `session.loadDocumentSource` (commit 591236d na Narration).

## Fallbacks

- O exemplo abre leitura por `BookSession.open/openFile` e cai para
  `Unseal.read/readFile` em `SessionUnsupportedFormatException`
  (formatos fora da fatia progressiva: MOBI, PDF, CBR, …).
- Web: `main.dart` configura `UnsealWorker` (`unseal_worker.js`
  compilado; ver `parsing_worker_bootstrap.dart`); worker ausente →
  engine inline, mesmo contrato.
- `E2E_OPEN_BOOK_MODE=session` no probe de abertura
  (`example/integration_test/e2e_open_probe_test.dart`) comuta o
  caminho A/B.

## Evidência de testes

- Pacote: 338/338 (`flutter test`), incluindo
  `book_server_session_test.dart` (resolver async, byte-ranges, FXL) e
  `viewer_controller_session_test.dart` (busca, texto, footnote,
  descarte fecha sessão).
- e2e macOS: `e2e_scenario` (fake engine, 10 transições),
  `e2e_real_reader` (10 transições reais + busca 54/54),
  `e2e_fxl_reader` — todos verdes; o turn de ~30 s do harness FXL é
  pré-existente (idêntico no worktree de baseline).
- Unseal: 1107 VM + 41 Chrome verdes.
