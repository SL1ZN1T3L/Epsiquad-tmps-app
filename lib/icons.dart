import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class Ico {
  static const link =
      '<path d="M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1.5 1.5"/><path d="M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1.5-1.5"/>';
  static const copy =
      '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>';
  static const check = '<path d="M20 6 9 17l-5-5"/>';
  static const upload =
      '<path d="M12 16V4M7 9l5-5 5 5"/><path d="M20 16v3a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-3"/>';
  static const download =
      '<path d="M12 4v12M7 11l5 5 5-5"/><path d="M20 16v3a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-3"/>';
  static const trash =
      '<path d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6M10 11v6M14 11v6"/>';
  static const eye =
      '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>';
  static const archive =
      '<rect x="2" y="3" width="20" height="5" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8M10 12h4"/>';

  static const box = '<path d="M12 2 L21 6.5 L21 17.5 L12 22 L3 17.5 L3 6.5 Z"/>'
      '<path d="M3 6.5 L12 11 L21 6.5 M12 11 L12 22"/>';
  static const x = '<path d="M18 6 6 18M6 6l12 12"/>';
  static const external =
      '<path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>';
  static const clock = '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>';
  static const file = '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>';
  static const image =
      '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-5-5L5 21"/>';
  static const video = '<rect x="2" y="5" width="14" height="14" rx="2"/><path d="m22 8-6 4 6 4z"/>';
  static const audio =
      '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>';
  static const pdf =
      '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h2.5a1.5 1.5 0 0 1 0 3H8v-3zm0 3v2"/>';
  static const code = '<path d="m16 18 6-6-6-6M8 6l-6 6 6 6"/>';
  static const zip =
      '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M10 2v2M10 6v2M10 10v2M9 14h2v4H9z"/>';
  static const telegram =
      '<path d="M21.5 4.5 2.8 11.7c-.9.4-.9 1.6.1 1.9l4.6 1.4 1.8 5.6c.2.7 1.1.9 1.6.4l2.6-2.4 4.9 3.6c.6.4 1.4.1 1.6-.6L22.9 5.8c.2-.9-.6-1.6-1.4-1.3z"/><path d="m7.5 15 10-7-7.5 8.5"/>';
  static const plus = '<path d="M12 5v14M5 12h14"/>';
  static const user = '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>';
  static const logout = '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>';
  static const refresh = '<path d="M21 12a9 9 0 1 1-2.6-6.4L21 8"/><path d="M21 3v5h-5"/>';
  static const arrowUp = '<path d="M12 19V5M5 12l7-7 7 7"/>';
  static const phone = '<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M11 18.5h2"/>';
  static const lock = '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>';
  static const ban = '<circle cx="12" cy="12" r="9"/><path d="m5.7 5.7 12.6 12.6"/>';
  static const settings =
      '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>';

  static const eyeOff =
      '<path d="M10.6 6.2A9.9 9.9 0 0 1 12 6c6.5 0 10 6 10 6a17.4 17.4 0 0 1-3 3.6"/><path d="M6.6 6.7A17.2 17.2 0 0 0 2 12s3.5 6 10 6a9.7 9.7 0 0 0 4-.9"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/><path d="m3 3 18 18"/>';
  static const play = '<path d="M7 4.5 19.5 12 7 19.5z"/>';
  static const pause = '<rect x="6.5" y="4" width="3.8" height="16" rx="1.2"/><rect x="13.7" y="4" width="3.8" height="16" rx="1.2"/>';
  static const share =
      '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 13.5 6.8 4M15.4 6.5l-6.8 4"/>';
  static const alert = '<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/>';
  static const warning =
      '<path d="M10.3 3.9 2.4 17a2 2 0 0 0 1.7 3h15.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>';
  static const more = '<circle cx="12" cy="5" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="12" cy="19" r="1.2"/>';
  static const arrowDown = '<path d="M12 5v14M19 12l-7 7-7-7"/>';
  static const cloudOff =
      '<path d="M17.5 19H7a5 5 0 0 1-.6-10A7 7 0 0 1 8.3 6.4"/><path d="M11 5.1A5 5 0 0 1 19 9v.6a4.5 4.5 0 0 1 2.4 7.2"/><path d="m3 3 18 18"/>';
  static const fingerprint =
      '<path d="M12 4a8 8 0 0 0-8 8v1.5"/><path d="M20 13.5V12a8 8 0 0 0-4-6.9"/><path d="M12 8a4 4 0 0 0-4 4v2a11 11 0 0 0 1 4.6"/><path d="M16 12.5V12a4 4 0 0 0-2-3.5"/><path d="M12 12v3a14 14 0 0 0 1.3 5.8"/><path d="M16.4 15.6a18 18 0 0 0 .3 3.6"/>';
}

class TmpsIcon extends StatelessWidget {
  const TmpsIcon(this.path, {super.key, this.size = 22, this.color, this.stroke = 1.8});

  final String path;
  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? const Color(0xFFECEEF4);
    final markup = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="#000000" stroke-width="$stroke" '
        'stroke-linecap="round" stroke-linejoin="round">$path</svg>';

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: SvgPicture.string(
          markup,
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
        ),
      ),
    );
  }
}
