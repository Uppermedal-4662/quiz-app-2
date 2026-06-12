import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class LatexText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double? fontSize;
  final Color? color;
  final TextAlign textAlign;
  final bool showTTS;

  const LatexText(
    this.text, {
    super.key,
    this.style,
    this.fontSize,
    this.color,
    this.textAlign = TextAlign.start,
    this.showTTS = true,
  });

  Future<void> _speak(String text) async {
    FlutterTts flutterTts = FlutterTts();
    
    // Improved Mathematical TTS Cleanup
    String cleanText = text
        .replaceAll('\$', '')
        .replaceAll(RegExp(r'\\frac\{(.*?)\}\{(.*?)\}'), r'$1 divided by $2')
        .replaceAll(RegExp(r'\\sqrt\{(.*?)\}'), r'square root of $1')
        .replaceAll(RegExp(r'\\times'), 'times')
        .replaceAll(RegExp(r'\\div'), 'divided by')
        .replaceAll(RegExp(r'\\pm'), 'plus or minus')
        .replaceAll(RegExp(r'\^\{(.*?)\}'), r' to the power of $1')
        .replaceAll(RegExp(r'\^(.)'), r' to the power of $1')
        .replaceAll(RegExp(r'_\{(.*?)\}'), r' subscript $1')
        .replaceAll(RegExp(r'_(.)'), r' subscript $1')
        .replaceAll('\\', ' ');

    await flutterTts.speak(cleanText);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final List<String> parts = text.split('\$');
    
    Widget content;
    if (parts.length == 1) {
      content = Text(
        text,
        style: style ?? TextStyle(fontSize: fontSize, color: color),
        textAlign: textAlign,
      );
    } else {
      List<InlineSpan> spans = [];
      for (int i = 0; i < parts.length; i++) {
        if (i % 2 == 0) {
          if (parts[i].isNotEmpty) {
            spans.add(TextSpan(
              text: parts[i],
              style: style ?? TextStyle(fontSize: fontSize, color: color),
            ));
          }
        } else {
          if (parts[i].isNotEmpty) {
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
              ),
            ));
          }
        }
      }
      content = Text.rich(
        TextSpan(children: spans),
        textAlign: textAlign,
      );
    }

    if (settings.enableTTS && showTTS) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: content),
          IconButton(
            icon: const Icon(Icons.volume_up, size: 20, color: Colors.blue),
            onPressed: () => _speak(text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      );
    }

    return content;
  }
}
