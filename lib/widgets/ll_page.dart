import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/listenloop_theme.dart';
import 'll_backdrop.dart';

/// The one page skeleton: status-bar overlay, canvas colour, the style's
/// background material, the safe area, and (optionally) a level-2 app bar.
///
/// Before this existed those four things were written by hand on every screen,
/// and the drift showed: the background material was painted on 4 of 16 pages,
/// so 学堂/书院/都市 only looked like themselves on the settings and playback
/// screens; two pages drove the status bar icons from nothing at all, so their
/// icons stayed light-on-light in 白昼; six pages skipped the safe area.
///
/// A page passes only its content. The app bar appears when [title] is given —
/// level-1 pages (课程 / 精听 / 设置 hub) have none and keep their own heading
/// inside the scroll.
class LLPage extends StatelessWidget {
  const LLPage({
    required this.body,
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottomBar,
    this.safeArea = true,
  });

  final Widget body;

  /// Non-null turns this into a level-2 page with an app bar.
  final Widget? title;
  final List<Widget>? actions;

  /// Overrides the back button when the page's own tooltip or glyph matters.
  final Widget? leading;

  /// A pinned bar (the tab bar, a player's controls). Passing it here instead of
  /// as the last child of a Column keeps the safe area on the content only.
  final Widget? bottomBar;

  /// False for a page that already consumes the insets itself — a bottom
  /// navigation bar, or a player that pins its own controls.
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final ll = context.ll;
    final shape = context.llShape;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: llSystemOverlay(ll.brightness),
      child: Scaffold(
        backgroundColor: ll.bg,
        appBar: title == null
            ? null
            : AppBar(
                backgroundColor: ll.bg,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                titleSpacing: 0,
                // The same hairline the tab bar wears, so a level-2 page reads
                // as a page and not as a floating strip of text.
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(shape.hairline),
                  child: ColoredBox(color: ll.divider),
                ),
                leading:
                    leading ??
                    (Navigator.of(context).canPop()
                        ? BackButton(color: ll.textPrimary)
                        : null),
                title: title,
                actions: actions,
              ),
        body: LLBackdrop(
          child: safeArea ? SafeArea(child: body) : body,
        ),
        bottomNavigationBar: bottomBar,
      ),
    );
  }
}
