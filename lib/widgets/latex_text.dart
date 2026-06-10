import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class LatexText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double? fontSize;
  final Color? color;
  final TextAlign textAlign;

  const LatexText(
    this.text, {
    super.key,
    this.style,
    this.fontSize,
    this.color,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    // Logic: Split string by $ symbols
    // "Text $math$ Text" -> ["Text ", "math", " Text"]
    final List<String> parts = text.split('\$');
    
    if (parts.length == 1) {
      return Text(
        text,
        style: style ?? TextStyle(fontSize: fontSize, color: color),
        textAlign: textAlign,
      );
    }

    List<InlineSpan> spans = [];
    
    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 0) {
        // Plain text
        if (parts[i].isNotEmpty) {
          spans.add(TextSpan(
            text: parts[i],
            style: style ?? TextStyle(fontSize: fontSize, color: color),
          ));
        }
      } else {
        // Math text
        if (parts[i].isNotEmpty) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Math.tex(
                parts[i],
                textStyle: style?.copyWith(fontSize: (fontSize ?? 16) + 2) ?? 
                          TextStyle(fontSize: (fontSize ?? 16) + 2, color: color),
                onErrorFallback: (err) => Text(
                  '\$${parts[i]}\$',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ));
        }
      }
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
    );
  }
}
