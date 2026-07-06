import 'dart:async';
import 'package:flutter/material.dart';

/// Reusable search bar with built-in 300 ms debounce.
///
/// Fires [onChanged] with the trimmed query after the debounce window.
/// Fires immediately (with empty string) when the clear button is pressed.
/// Drop-in replacement for a plain [TextField] used for filtering.
///
/// Pass [controller] to allow external code (e.g. a "Clear all filters" button)
/// to clear the field programmatically. When omitted, an internal controller is
/// created and owned by this widget.
class AdminSearchBar extends StatefulWidget {
  final String hintText;
  final ValueChanged<String> onChanged;
  final double width;
  final Duration debounceDuration;
  final TextEditingController? controller;

  const AdminSearchBar({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.width = 320,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.controller,
  });

  @override
  State<AdminSearchBar> createState() => _AdminSearchBarState();
}

class _AdminSearchBarState extends State<AdminSearchBar> {
  late final TextEditingController _controller;
  late final bool _ownsController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onExternalClear);
  }

  void _onExternalClear() {
    if (_controller.text.isEmpty) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onExternalClear);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // refreshes clear-button visibility
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDuration, () {
      if (mounted) widget.onChanged(value.trim());
    });
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    setState(() {});
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: _clear,
                  tooltip: 'Clear search',
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        onChanged: _onChanged,
      ),
    );
  }
}
