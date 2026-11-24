import 'package:flutter/rendering.dart' show RenderBox;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';

// Long lists are read 20 items at a time (demande du développeur, 24/11/2026: « éviter les trop
// grosses requêtes »): the first page when the page opens, the next one when the end of the list
// comes into view. Searching, filtering or sorting a list the API doesn't filter needs all of it:
// every page is then asked, still 20 items a request.
//
// Flutter: each page is its own provider (`FutureProvider.family`, keyed by the page number), like
// [PagedGrid]: a page read once stays in memory while the screen shows it, and reading « more »
// only adds the next provider.

/// Items a page of the API's long lists.
const pageSize = 20;

/// Pages 1 to `count` of a list read page by page ([watchPages]).
class PagedItems<T> {
  const PagedItems({
    required this.items,
    required this.loading,
    required this.error,
    required this.totalPages,
    required this.loaded,
    this.totalResults,
    this.failedPage,
  });

  /// The items of the pages read in a row from the first, in order.
  final List<T> items;

  /// A page is still on its way.
  final bool loading;

  /// The first page failed: nothing to show.
  final Object? error;

  final int totalPages;

  /// Pages read in a row from the first.
  final int loaded;

  /// Every item of the list, when the API gives it.
  final int? totalResults;

  /// A page after the first one failed (« Réessayer » under the list).
  final int? failedPage;

  /// Every page is read.
  bool get complete => loaded >= totalPages;
}

/// Pages 1 to [count] of [page], watched together (a page that failed or is loading stops the
/// items there: they stay in order).
PagedItems<T> watchPages<T>(WidgetRef ref, FutureProvider<Paged<T>> Function(int page) page, int count) {
  final pages = [for (var p = 1; p <= count; p++) ref.watch(page(p))];
  final items = <T>[];
  var loaded = 0;
  for (final value in pages) {
    final paged = value.value;
    if (paged == null) break;
    items.addAll(paged.items);
    loaded++;
  }
  final first = pages.first;
  final failed = loaded < pages.length && loaded > 0 && pages[loaded].hasError ? loaded + 1 : null;
  return PagedItems(
    items: items,
    loading: pages.any((p) => p.isLoading && !p.hasValue),
    error: first.hasError && !first.hasValue ? first.error : null,
    totalPages: first.value?.totalPages ?? 1,
    loaded: loaded,
    totalResults: first.value?.totalResults,
    failedPage: failed,
  );
}

/// Asks for more once, after the frame being built: an item near the end of the list was built,
/// or the list came near its end ([LoadMoreOnScroll]). [load] decides whether there is more.
class NextPage {
  NextPage(this._load);

  final VoidCallback _load;
  bool _scheduled = false;

  /// How close to the end of a list (in items) the next page is asked.
  static const margin = 6;

  void request() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _load();
    });
  }
}

/// Calls [onEnd] when the list under it is less than a screen from its end, or too short to fill
/// the screen: for a page whose content is built at once (not item by item).
class LoadMoreOnScroll extends StatelessWidget {
  const LoadMoreOnScroll({super.key, required this.onEnd, required this.child});

  /// Null: nothing more to read.
  final VoidCallback? onEnd;
  final Widget child;

  bool _check(ScrollMetrics metrics, int depth) {
    final onEnd = this.onEnd;
    if (onEnd != null && depth == 0 && metrics.axis == Axis.vertical && metrics.extentAfter < metrics.viewportDimension) {
      onEnd();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
    // The first layout, and each time the content grows.
    onNotification: (n) => _check(n.metrics, n.depth),
    child: NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) => _check(n.metrics, n.depth),
      child: child,
    ),
  );
}

/// A list read 20 at a time ([page]): the first page when it shows, the next one when [builder]
/// says an item near the end was built (`nearEnd(index, count)`). With [all] (a search, a filter or
/// an order the API doesn't apply), every page is read, one after the other.
///
/// Like a Vue component with an infinite scroll: [builder] gets the items read so far and a
/// function to call while building each item.
class PagedBuilder<T> extends ConsumerStatefulWidget {
  const PagedBuilder({super.key, required this.page, required this.builder, this.all = false});

  final FutureProvider<Paged<T>> Function(int page) page;

  /// Read every page (one request after the other, 20 items each).
  final bool all;

  /// [nearEnd]: call it with the index of an item being built and the number of items shown.
  final Widget Function(BuildContext context, PagedItems<T> pages, void Function(int index, int count) nearEnd) builder;

  @override
  ConsumerState<PagedBuilder<T>> createState() => _PagedBuilderState<T>();
}

class _PagedBuilderState<T> extends ConsumerState<PagedBuilder<T>> {
  int _count = 1;
  late final _next = NextPage(_more);
  PagedItems<T>? _pages;

  void _more() {
    final pages = _pages;
    if (!mounted || pages == null || pages.failedPage != null) return;
    // The last page asked has come, and there is another one.
    if (pages.loaded >= _count && _count < pages.totalPages) setState(() => _count++);
  }

  void _nearEnd(int index, int count) {
    if (index >= count - NextPage.margin) _next.request();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages = watchPages(ref, widget.page, _count);
    if (widget.all && !pages.complete) _next.request();
    return widget.builder(context, pages, _nearEnd);
  }
}

/// Under a list read page by page: a loading circle while the next page comes, « Réessayer » when
/// it failed, nothing otherwise.
class PagedFooter extends ConsumerWidget {
  const PagedFooter({super.key, required this.pages, required this.page});

  final PagedItems<Object?> pages;
  final FutureProvider<Object?> Function(int page) page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = pages.failedPage;
    if (failed != null) {
      return Center(
        child: TextButton(onPressed: () => ref.invalidate(page(failed)), child: const Text('Réessayer')),
      );
    }
    if (pages.loading && pages.loaded > 0) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox.shrink();
  }
}

/// At the end of a list built at once inside a page that scrolls (like an IntersectionObserver):
/// calls [onVisible] when it comes less than a screen below what is shown, then each time the page
/// scrolls while it is that close. [child] (a loading circle…) is shown in its place.
class LoadMoreSentinel extends StatefulWidget {
  const LoadMoreSentinel({super.key, required this.onVisible, this.child = const SizedBox.shrink()});

  /// Null: nothing more to read.
  final VoidCallback? onVisible;
  final Widget child;

  @override
  State<LoadMoreSentinel> createState() => _LoadMoreSentinelState();
}

class _LoadMoreSentinelState extends State<LoadMoreSentinel> {
  ScrollableState? _scrollable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != _scrollable) {
      _scrollable?.position.removeListener(_check);
      _scrollable = scrollable?..position.addListener(_check);
    }
    _checkAfterFrame();
  }

  @override
  void didUpdateWidget(LoadMoreSentinel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAfterFrame();
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_check);
    super.dispose();
  }

  void _checkAfterFrame() => WidgetsBinding.instance.addPostFrameCallback((_) => _check());

  void _check() {
    final onVisible = widget.onVisible;
    if (!mounted || onVisible == null) return;
    final box = context.findRenderObject();
    final viewport = _scrollable?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || viewport is! RenderBox || !viewport.hasSize) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    if (top < viewport.size.height * 2) onVisible();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
